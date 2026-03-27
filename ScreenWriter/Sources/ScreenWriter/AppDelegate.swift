import Cocoa

/// 应用代理 - 管理应用生命周期
class AppDelegate: NSObject, NSApplicationDelegate {
    
    /// 状态栏控制器
    var statusBarController: StatusBarController!
    /// 快捷键管理器
    var shortcutManager: ShortcutManager!
    /// 覆盖窗口管理器
    var overlayManager: OverlayWindowManager!
    /// 设置窗口
    var settingsWindow: SettingsWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查辅助功能权限（全局快捷键需要此权限）
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            // 辅助功能权限未授予，全局快捷键可能无法在其他应用中使用
        }
        
        // 初始化画笔设置
        BrushSettings.shared.loadSettings()
        
        // 初始化覆盖窗口管理器
        overlayManager = OverlayWindowManager()
        overlayManager.onToggleDrawing = { [weak self] in
            self?.toggleDrawing()
        }
        overlayManager.onSaveScreenshot = { [weak self] in
            self?.saveScreenshot()
        }
        overlayManager.onSaveWhiteBackground = { [weak self] in
            self?.saveWhiteBackground()
        }
        
        // 初始化状态栏控制器
        statusBarController = StatusBarController(
            onToggleDrawing: { [weak self] in
                self?.toggleDrawing()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onClearCanvas: { [weak self] in
                self?.clearCanvas()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
        
        // 初始化快捷键管理器
        shortcutManager = ShortcutManager()
        shortcutManager.loadConfig()
        shortcutManager.onQuickLaunch = { [weak self] in
            self?.toggleDrawing()
        }
        shortcutManager.onEscape = { [weak self] in
            guard let self = self, self.overlayManager.isActive else { return }
            // 数位板专属模式下，穿透状态时不拦截 ESC，让其他应用正常使用
            if BrushSettings.shared.isTabletOnlyMode,
               self.overlayManager.isPassthroughMode {
                return
            }
            self.stopDrawing()
        }
        shortcutManager.onClearCanvas = { [weak self] in
            self?.clearCanvas()
        }
        shortcutManager.onSaveScreenshot = { [weak self] in
            self?.saveScreenshot()
        }
        shortcutManager.onUndo = { [weak self] in
            self?.overlayManager.undo()
        }
        shortcutManager.onRedo = { [weak self] in
            self?.overlayManager.redo()
        }
        shortcutManager.onToggleEraser = {
            BrushSettings.shared.toggleEraserMode()
        }
        shortcutManager.onToggleTabletPassthrough = { [weak self] in
            self?.toggleTabletPassthrough()
        }
        shortcutManager.startMonitoring()
    }
    
    /// 切换书写模式
    func toggleDrawing() {
        if overlayManager.isActive {
            stopDrawing()
        } else {
            startDrawing()
        }
    }
    
    /// 开始书写
    func startDrawing() {
        overlayManager.show()
        statusBarController.updateState(isDrawing: true)
    }
    
    /// 停止书写
    func stopDrawing() {
        // 询问是否保存截图
        let alert = NSAlert()
        alert.messageText = "停止书写"
        alert.informativeText = "是否保存当前屏幕截图？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        
        // 确保弹窗在最前面
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // 保存截图
            saveScreenshot()
            overlayManager.hide()
            statusBarController.updateState(isDrawing: false)
        case .alertSecondButtonReturn:
            // 不保存，直接关闭
            overlayManager.hide()
            statusBarController.updateState(isDrawing: false)
        default:
            // 取消，继续书写
            break
        }
    }
    
    /// 清除画布
    func clearCanvas() {
        overlayManager.clearAll()
    }
    
    /// 保存截图
    func saveScreenshot() {
        ScreenCapture.captureAndSave(
            overlayWindows: overlayManager.windows,
            drawingViews: overlayManager.drawingViews,
            saveMode: .screenshotOnly
        )
    }
    
    /// 保存白色背景
    func saveWhiteBackground() {
        ScreenCapture.captureAndSave(
            overlayWindows: overlayManager.windows,
            drawingViews: overlayManager.drawingViews,
            saveMode: .whiteBackgroundOnly
        )
    }
    
    /// 切换数位板绘画/鼠标穿透模式
    func toggleTabletPassthrough() {
        guard overlayManager.isActive, BrushSettings.shared.isTabletOnlyMode else { return }
        // 切换穿透状态
        if overlayManager.isPassthroughMode {
            // 当前穿透 → 切回绘画模式
            overlayManager.switchToAccept()
        } else {
            // 当前绘画 → 切到穿透模式
            overlayManager.switchToPassthrough()
        }
    }
    
    /// 打开设置面板
    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
