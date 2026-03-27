import Cocoa

/// 覆盖窗口管理器 - 管理所有屏幕上的透明绘图窗口
class OverlayWindowManager {
    
    var windows: [NSWindow] = []
    var drawingViews: [DrawingView] = []
    var isActive = false
    var isPassthroughMode = false
    
    var floatingToolbar: FloatingToolbarPanel?
    var onToggleDrawing: (() -> Void)?
    var onSaveScreenshot: (() -> Void)?
    var onSaveWhiteBackground: (() -> Void)?
    
    /// CGEvent tap
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsObserver: NSObjectProtocol?
    /// 系统光标是否已隐藏
    var isCursorHidden = false
    /// 保存 passRetained 的指针，用于在 stopEventTap 时释放
    private var retainedSelfPtr: UnsafeMutableRawPointer?
    /// 数位板激活前的前台应用，笔离开时恢复
    var previousActiveApp: NSRunningApplication?
    
    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: BrushSettings.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncTabletOnlyMode()
        }
    }
    
    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        stopEventTap()
    }
    
    func show() {
        guard !isActive else { return }
        isActive = true
        
        // 隐藏 Dock，防止绘图时鼠标移到屏幕底部触发程序坞
        NSApp.presentationOptions.insert(.hideDock)
        
        for screen in NSScreen.screens {
            let (window, drawingView) = createOverlayWindow(for: screen)
            window.orderFrontRegardless()
            windows.append(window)
            drawingViews.append(drawingView)
        }
        
        if floatingToolbar == nil {
            floatingToolbar = FloatingToolbarPanel()
            floatingToolbar?.onClose = { [weak self] in self?.onToggleDrawing?() }
            floatingToolbar?.onUndo = { [weak self] in self?.undo() }
            floatingToolbar?.onClear = { [weak self] in self?.clearAll() }
            floatingToolbar?.onSaveScreenshot = { [weak self] in self?.onSaveScreenshot?() }
            floatingToolbar?.onSaveWhiteBackground = { [weak self] in self?.onSaveWhiteBackground?() }
        }
        
        if let mainScreen = NSScreen.main, let toolbar = floatingToolbar {
            let x = mainScreen.frame.maxX - toolbar.frame.width - 40
            let y = mainScreen.frame.midY - toolbar.frame.height / 2
            toolbar.setFrameOrigin(NSPoint(x: x, y: y))
            toolbar.orderFrontRegardless()
        }
        
        syncTabletOnlyMode()
    }
    
    func hide() {
        isActive = false
        isPassthroughMode = false
        stopEventTap()
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        drawingViews.removeAll()
        floatingToolbar?.orderOut(nil)
        
        // 恢复 Dock 显示
        NSApp.presentationOptions.remove(.hideDock)
    }
    
    func clearAll() { for view in drawingViews { view.clearAll() } }
    func undo() { drawingViews.first?.undo() }
    func redo() { drawingViews.first?.redo() }
    
    func switchToPassthrough() {
        guard BrushSettings.shared.isTabletOnlyMode else { return }
        isPassthroughMode = true
    }
    
    func switchToAccept() {
        isPassthroughMode = false
    }
    
    // MARK: - 数位板专属模式
    
    private func syncTabletOnlyMode() {
        guard isActive else { return }
        
        if BrushSettings.shared.isTabletOnlyMode {
            // 数位板专属模式：
            // - ignoresMouseEvents = true → 所有事件自然穿透到桌面
            // - CGEvent tap 拦截数位板事件 → return nil 阻止到桌面 → 直接分发到 DrawingView
            // - 绕过 macOS 窗口事件路由，无 timing 问题
            for window in windows {
                window.ignoresMouseEvents = true
            }
            startEventTap()
        } else {
            // 普通模式：正常接收所有事件
            for view in drawingViews {
                view.clearTabletCursor()
            }
            stopEventTap()
            for window in windows {
                window.ignoresMouseEvents = false
            }
        }
    }
    
    // MARK: - CGEvent Tap
    
    private func startEventTap() {
        guard eventTap == nil else { return }
        
        let eventMask = CGEventMask(1 << CGEventType.tabletProximity.rawValue) |
                        CGEventMask(1 << CGEventType.mouseMoved.rawValue) |
                        CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
                        CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
                        CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        
        // 使用 passRetained 确保 event tap 回调期间 self 不会被释放
        let retainedPtr = Unmanaged.passRetained(self).toOpaque()
        retainedSelfPtr = retainedPtr
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tabletEventTapCallback,
            userInfo: retainedPtr
        )
        
        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // CGEvent tap 创建失败，回退到普通模式
            releaseRetainedSelf()
            for window in windows { window.ignoresMouseEvents = false }
        }
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        // 释放 passRetained 的引用
        releaseRetainedSelf()
    }
    
    /// 释放 event tap 持有的 retained 引用
    private func releaseRetainedSelf() {
        if let ptr = retainedSelfPtr {
            Unmanaged<OverlayWindowManager>.fromOpaque(ptr).release()
            retainedSelfPtr = nil
        }
    }
    
    private func createOverlayWindow(for screen: NSScreen) -> (NSWindow, DrawingView) {
        let drawingView = DrawingView(frame: NSRect(origin: .zero, size: screen.frame.size))
        
        let window = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.overlayManager = self
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.level = .statusBar + 1
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = drawingView
        window.setFrame(screen.frame, display: true)
        
        return (window, drawingView)
    }
}

// MARK: - CGEvent Tap 回调

/// 判断 CGEvent 是否来自数位板
private func isTabletCGEvent(_ event: CGEvent) -> Bool {
    let subtype = event.getIntegerValueField(.mouseEventSubtype)
    if subtype == 1 { return true }
    let tabletPressure = event.getIntegerValueField(.tabletEventPointPressure)
    if tabletPressure > 0 { return true }
    let pressure = event.getDoubleValueField(.mouseEventPressure)
    if pressure > 0.001 && pressure < 0.999 { return true }
    return false
}

/// CGEvent tap 回调
private func tabletEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<OverlayWindowManager>.fromOpaque(userInfo).takeUnretainedValue()
    
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    
    guard BrushSettings.shared.isTabletOnlyMode, manager.isActive else {
        return Unmanaged.passUnretained(event)
    }
    
    // Proximity 事件
    if type == .tabletProximity {
        let entering = event.getIntegerValueField(.tabletProximityEventEnterProximity) != 0
        if !entering {
            // 笔离开近场 → 清除自绘光标 + 恢复系统光标 + 恢复之前的前台应用
            for view in manager.drawingViews {
                view.clearTabletCursor()
            }
            if manager.isCursorHidden {
                NSCursor.unhide()
                manager.isCursorHidden = false
            }
            // 恢复笔进入前的前台应用，避免用户需要额外点击
            if let prevApp = manager.previousActiveApp {
                prevApp.activate()
                manager.previousActiveApp = nil
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    let isTablet = isTabletCGEvent(event)
    let cgPoint = event.location
    let screenHeight = NSScreen.main?.frame.height ?? 1080
    let screenPoint = NSPoint(x: cgPoint.x, y: screenHeight - cgPoint.y)
    
    // mouseMoved
    if type == .mouseMoved {
        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        if subtype == 1 {
            // 数位板悬停 → 激活应用 + 隐藏系统光标 + 显示自绘光标
            if !manager.isCursorHidden {
                // 保存当前前台应用，以便笔离开时恢复
                if manager.previousActiveApp == nil {
                    manager.previousActiveApp = NSWorkspace.shared.frontmostApplication
                }
                NSApp.activate(ignoringOtherApps: true)
                NSCursor.hide()
                manager.isCursorHidden = true
            }
            for (i, window) in manager.windows.enumerated() {
                if window.frame.contains(screenPoint) {
                    manager.drawingViews[i].updateTabletCursor(screenPoint: screenPoint)
                    break
                }
            }
        } else if manager.isCursorHidden {
            // 鼠标移动 → 恢复系统光标 + 清除自绘光标
            NSCursor.unhide()
            manager.isCursorHidden = false
            for view in manager.drawingViews {
                view.clearTabletCursor()
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    if !isTablet {
        // 非数位板事件 → 放行，穿透到桌面
        if manager.isCursorHidden {
            NSCursor.unhide()
            manager.isCursorHidden = false
            for view in manager.drawingViews {
                view.clearTabletCursor()
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    // ===== 数位板事件 → 拦截并直接分发到 DrawingView =====
    
    // 确保系统光标隐藏
    if !manager.isCursorHidden {
        // 保存当前前台应用，以便笔离开时恢复
        if manager.previousActiveApp == nil {
            manager.previousActiveApp = NSWorkspace.shared.frontmostApplication
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        manager.isCursorHidden = true
    }
    
    let pressure = CGFloat(event.getDoubleValueField(.mouseEventPressure))
    
    for (i, window) in manager.windows.enumerated() {
        if window.frame.contains(screenPoint) {
            let drawingView = manager.drawingViews[i]
            
            switch type {
            case .leftMouseDown:
                drawingView.externalDown(screenPoint: screenPoint, pressure: pressure)
                drawingView.updateTabletCursor(screenPoint: screenPoint)
            case .leftMouseDragged:
                drawingView.externalDragged(screenPoint: screenPoint, pressure: pressure)
                drawingView.updateTabletCursor(screenPoint: screenPoint)
            case .leftMouseUp:
                drawingView.externalUp(screenPoint: screenPoint, pressure: pressure)
                drawingView.updateTabletCursor(screenPoint: screenPoint)
            default:
                break
            }
            break
        }
    }
    
    return nil
}

/// 自定义 Panel
class OverlayPanel: NSPanel {
    weak var overlayManager: OverlayWindowManager?
    
    // 必须为 true 才能在非数位板模式下控制光标
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    override func sendEvent(_ event: NSEvent) {
        // 键盘事件：不处理，让系统传递给其他应用
        if event.type == .keyDown || event.type == .keyUp || event.type == .flagsChanged {
            return
        }
        // 非数位板模式：所有鼠标事件都设置画笔光标，防止抬笔瞬间闪回箭头
        if !BrushSettings.shared.isTabletOnlyMode {
            switch event.type {
            case .mouseMoved, .mouseEntered,
                 .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                 .rightMouseDown, .rightMouseDragged, .rightMouseUp:
                if let drawingView = contentView as? DrawingView {
                    drawingView.brushCursor?.set()
                }
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}
