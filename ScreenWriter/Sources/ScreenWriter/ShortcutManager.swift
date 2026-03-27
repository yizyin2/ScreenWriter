import Cocoa
import Carbon.HIToolbox

/// 快捷键配置
struct ShortcutConfig {
    var quickLaunchModifiers: NSEvent.ModifierFlags = [.control, .shift]
    var quickLaunchKeyCode: UInt16 = UInt16(kVK_ANSI_D)
    
    var clearCanvasModifiers: NSEvent.ModifierFlags = [.control, .shift]
    var clearCanvasKeyCode: UInt16 = UInt16(kVK_ANSI_C)
    
    var saveScreenshotModifiers: NSEvent.ModifierFlags = [.control, .shift]
    var saveScreenshotKeyCode: UInt16 = UInt16(kVK_ANSI_S)
    
    var undoModifiers: NSEvent.ModifierFlags = [.command]
    var undoKeyCode: UInt16 = UInt16(kVK_ANSI_Z)
    
    var redoModifiers: NSEvent.ModifierFlags = [.command, .shift]
    var redoKeyCode: UInt16 = UInt16(kVK_ANSI_Z)
    
    var toggleEraserModifiers: NSEvent.ModifierFlags = [.control, .shift]
    var toggleEraserKeyCode: UInt16 = UInt16(kVK_ANSI_E)
    
    var toggleTabletPassthroughModifiers: NSEvent.ModifierFlags = [.control, .shift]
    var toggleTabletPassthroughKeyCode: UInt16 = UInt16(kVK_ANSI_T)
    
    /// 返回默认配置
    static func defaultConfig() -> ShortcutConfig {
        return ShortcutConfig()
    }
}

/// 快捷键管理器 - 处理全局和本地快捷键
class ShortcutManager {
    
    /// 快捷键变更通知
    static let configChangedNotification = Notification.Name("ShortcutConfigChanged")
    
    /// 快捷键配置
    var config = ShortcutConfig()
    
    /// 是否启用快捷键处理（录制时应禁用）
    var isEnabled: Bool = true
    
    /// 全局事件监听器
    private var globalMonitor: Any?
    /// 本地事件监听器
    private var localMonitor: Any?
    
    /// 回调
    var onQuickLaunch: (() -> Void)?
    var onEscape: (() -> Void)?
    var onClearCanvas: (() -> Void)?
    var onSaveScreenshot: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onToggleEraser: (() -> Void)?
    var onToggleTabletPassthrough: (() -> Void)?
    
    /// 开始监听快捷键
    func startMonitoring() {
        // 全局监听（非焦点窗口时也能响应）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // 本地监听（焦点在本应用时）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // 消耗事件
            }
            return event
        }
    }
    
    /// 停止监听
    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    /// 处理按键事件
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // 录制快捷键时暂停处理
        guard isEnabled else { return false }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode
        
        // ESC 键退出书写模式（无需修饰键）
        if keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onEscape?()
            }
            return true
        }
        
        // 快捷启动书写模式: Ctrl+Shift+D
        if modifiers == config.quickLaunchModifiers && keyCode == config.quickLaunchKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onQuickLaunch?()
            }
            return true
        }
        
        // 清除画布: Ctrl+Shift+C
        if modifiers == config.clearCanvasModifiers && keyCode == config.clearCanvasKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onClearCanvas?()
            }
            return true
        }
        
        // 保存截图: Ctrl+Shift+S
        if modifiers == config.saveScreenshotModifiers && keyCode == config.saveScreenshotKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onSaveScreenshot?()
            }
            return true
        }
        
        // 撤销: Cmd+Z
        if modifiers == config.undoModifiers && keyCode == config.undoKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onUndo?()
            }
            return true
        }
        
        // 重做: Cmd+Shift+Z
        if modifiers == config.redoModifiers && keyCode == config.redoKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onRedo?()
            }
            return true
        }
        
        // 切换橡皮擦: Ctrl+Shift+E
        if modifiers == config.toggleEraserModifiers && keyCode == config.toggleEraserKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleEraser?()
            }
            return true
        }
        
        // 切换数位板绘画/鼠标穿透: Ctrl+Shift+T
        if modifiers == config.toggleTabletPassthroughModifiers && keyCode == config.toggleTabletPassthroughKeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleTabletPassthrough?()
            }
            return true
        }
        
        return false
    }
    
    /// 获取快捷键显示文本
    static func shortcutDisplayText(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        // 键码映射
        let keyMap: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
        ]
        
        if let keyName = keyMap[keyCode] {
            parts.append(keyName)
        }
        
        return parts.joined()
    }
    
    /// 保存快捷键配置
    func saveConfig() {
        let defaults = UserDefaults.standard
        defaults.set(config.quickLaunchModifiers.rawValue, forKey: "shortcut_toggle_modifiers")
        defaults.set(config.quickLaunchKeyCode, forKey: "shortcut_toggle_keycode")
        defaults.set(config.clearCanvasModifiers.rawValue, forKey: "shortcut_clear_modifiers")
        defaults.set(config.clearCanvasKeyCode, forKey: "shortcut_clear_keycode")
        defaults.set(config.saveScreenshotModifiers.rawValue, forKey: "shortcut_save_modifiers")
        defaults.set(config.saveScreenshotKeyCode, forKey: "shortcut_save_keycode")
        defaults.set(config.undoModifiers.rawValue, forKey: "shortcut_undo_modifiers")
        defaults.set(config.undoKeyCode, forKey: "shortcut_undo_keycode")
        defaults.set(config.redoModifiers.rawValue, forKey: "shortcut_redo_modifiers")
        defaults.set(config.redoKeyCode, forKey: "shortcut_redo_keycode")
        defaults.set(config.toggleEraserModifiers.rawValue, forKey: "shortcut_eraser_modifiers")
        defaults.set(config.toggleEraserKeyCode, forKey: "shortcut_eraser_keycode")
        defaults.set(config.toggleTabletPassthroughModifiers.rawValue, forKey: "shortcut_tabletpass_modifiers")
        defaults.set(config.toggleTabletPassthroughKeyCode, forKey: "shortcut_tabletpass_keycode")
    }
    
    /// 加载快捷键配置
    func loadConfig() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "shortcut_toggle_modifiers") != nil {
            config.quickLaunchModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_toggle_modifiers")))
            config.quickLaunchKeyCode = UInt16(defaults.integer(forKey: "shortcut_toggle_keycode"))
        }
        if defaults.object(forKey: "shortcut_clear_modifiers") != nil {
            config.clearCanvasModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_clear_modifiers")))
            config.clearCanvasKeyCode = UInt16(defaults.integer(forKey: "shortcut_clear_keycode"))
        }
        if defaults.object(forKey: "shortcut_save_modifiers") != nil {
            config.saveScreenshotModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_save_modifiers")))
            config.saveScreenshotKeyCode = UInt16(defaults.integer(forKey: "shortcut_save_keycode"))
        }
        if defaults.object(forKey: "shortcut_undo_modifiers") != nil {
            config.undoModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_undo_modifiers")))
            config.undoKeyCode = UInt16(defaults.integer(forKey: "shortcut_undo_keycode"))
        }
        if defaults.object(forKey: "shortcut_redo_modifiers") != nil {
            config.redoModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_redo_modifiers")))
            config.redoKeyCode = UInt16(defaults.integer(forKey: "shortcut_redo_keycode"))
        }
        if defaults.object(forKey: "shortcut_eraser_modifiers") != nil {
            config.toggleEraserModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_eraser_modifiers")))
            config.toggleEraserKeyCode = UInt16(defaults.integer(forKey: "shortcut_eraser_keycode"))
        }
        if defaults.object(forKey: "shortcut_tabletpass_modifiers") != nil {
            config.toggleTabletPassthroughModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "shortcut_tabletpass_modifiers")))
            config.toggleTabletPassthroughKeyCode = UInt16(defaults.integer(forKey: "shortcut_tabletpass_keycode"))
        }
    }
    
    /// 更新快捷键配置并重新启动监听
    func updateConfig(_ newConfig: ShortcutConfig) {
        config = newConfig
        saveConfig()
        // 延迟到下一个 RunLoop 迭代重启监听，避免在事件回调内部操作监听器
        DispatchQueue.main.async { [weak self] in
            self?.stopMonitoring()
            self?.startMonitoring()
        }
        NotificationCenter.default.post(name: ShortcutManager.configChangedNotification, object: self)
    }
    
    /// 重置为默认快捷键
    func resetToDefault() {
        updateConfig(ShortcutConfig.defaultConfig())
    }
    
    deinit {
        stopMonitoring()
    }
}
