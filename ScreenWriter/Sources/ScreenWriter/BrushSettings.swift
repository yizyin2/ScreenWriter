import Cocoa

// MARK: - 压感灵敏度级别

/// 压感灵敏度级别
enum PressureSensitivity: Int, CaseIterable {
    case off = -1     // 关闭压感
    case low = 0
    case medium = 1
    case high = 2
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
    
    /// 压感系数 - 乘以基础粗细
    var multiplier: CGFloat {
        switch self {
        case .off: return 0.0    // 固定粗细，不受压力影响
        case .low: return 0.5
        case .medium: return 1.0
        case .high: return 2.0
        }
    }
    
    /// 是否启用压感
    var isEnabled: Bool {
        return self != .off
    }
}

// MARK: - 画笔预设数据模型

/// 画笔预设 - 可自定义的画笔配置
class BrushPreset: Codable, Equatable {
    /// 唯一标识
    var id: String
    /// 显示名称
    var displayName: String
    /// 粗细
    var size: CGFloat
    /// 颜色 RGB（用于序列化）
    var colorRed: CGFloat
    var colorGreen: CGFloat
    var colorBlue: CGFloat
    /// 不透明度
    var opacity: CGFloat
    /// 压感灵敏度
    var sensitivityRawValue: Int
    /// 是否为橡皮擦
    var isEraser: Bool
    /// 是否为荧光笔
    var isHighlighter: Bool
    
    // MARK: - Computed Properties
    
    /// NSColor 对象
    var color: NSColor {
        get { NSColor(red: colorRed, green: colorGreen, blue: colorBlue, alpha: 1.0) }
        set {
            if let rgb = newValue.usingColorSpace(.sRGB) {
                colorRed = rgb.redComponent
                colorGreen = rgb.greenComponent
                colorBlue = rgb.blueComponent
            }
        }
    }
    
    /// 压感灵敏度
    var sensitivity: PressureSensitivity {
        get { PressureSensitivity(rawValue: sensitivityRawValue) ?? .medium }
        set { sensitivityRawValue = newValue.rawValue }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: BrushPreset, rhs: BrushPreset) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - 初始化
    
    init(id: String, displayName: String, size: CGFloat, color: NSColor,
         opacity: CGFloat = 1.0, sensitivity: PressureSensitivity = .medium,
         isEraser: Bool = false, isHighlighter: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.size = size
        self.opacity = opacity
        self.sensitivityRawValue = sensitivity.rawValue
        self.isEraser = isEraser
        self.isHighlighter = isHighlighter
        
        // 提取颜色分量
        if let rgb = color.usingColorSpace(.sRGB) {
            self.colorRed = rgb.redComponent
            self.colorGreen = rgb.greenComponent
            self.colorBlue = rgb.blueComponent
        } else {
            self.colorRed = 0
            self.colorGreen = 0
            self.colorBlue = 0
        }
    }
    
    // MARK: - 内置默认预设
    
    static func defaultPresets() -> [BrushPreset] {
        return [
            BrushPreset(id: "builtin_thin", displayName: "细笔", size: 2,
                        color: .black, sensitivity: .medium),
            BrushPreset(id: "builtin_pen", displayName: "钢笔", size: 3,
                        color: NSColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1.0),
                        sensitivity: .medium),
            BrushPreset(id: "builtin_red", displayName: "红笔", size: 5,
                        color: NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1.0),
                        sensitivity: .medium),
            BrushPreset(id: "builtin_highlighter", displayName: "荧光笔", size: 20,
                        color: NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0),
                        opacity: 0.35, sensitivity: .off,
                        isHighlighter: true),
        ]
    }
}

// MARK: - 画笔设置管理器

/// 画笔设置 - 单例管理当前画笔配置
class BrushSettings {
    
    static let shared = BrushSettings()
    
    /// 当前画笔颜色
    var color: NSColor = .black
    /// 当前画笔粗细
    var size: CGFloat = 5.0
    /// 不透明度 (0.0 - 1.0)
    var opacity: CGFloat = 1.0
    /// 压感灵敏度（直接持久化到 UserDefaults，避免内存值和持久化值不同步）
    var pressureSensitivity: PressureSensitivity {
        get {
            let raw = UserDefaults.standard.integer(forKey: "pressureSensitivityV2")
            // UserDefaults.integer 默认返回 0，用 -99 标记未设置
            if UserDefaults.standard.object(forKey: "pressureSensitivityV2") == nil {
                return .medium
            }
            return PressureSensitivity(rawValue: raw) ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "pressureSensitivityV2")
        }
    }
    /// 是否为橡皮擦模式
    var isEraser: Bool = false
    /// 是否为索套选择模式
    var isLassoMode: Bool = false
    /// 是否为整笔擦除模式
    var isStrokeEraser: Bool = false
    /// 上次使用的橡皮擦是否为整笔擦除（用于快捷键记忆，持久化）
    var lastEraserWasStroke: Bool {
        get { UserDefaults.standard.bool(forKey: "lastEraserWasStroke") }
        set { UserDefaults.standard.set(newValue, forKey: "lastEraserWasStroke") }
    }
    /// 橡皮擦粗细
    var eraserSize: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: "eraserSize")
            return saved > 0 ? CGFloat(saved) : 30.0
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: "eraserSize")
        }
    }
    /// 是否为荧光笔模式
    var isHighlighter: Bool = false
    /// 是否为数位板专属模式（仅数位板可绘画，鼠标/触摸板穿透）
    var isTabletOnlyMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isTabletOnlyMode, forKey: "isTabletOnlyMode")
            notifyChanges()
        }
    }
    /// 当前选中的预设
    var currentPreset: BrushPreset? = nil
    
    /// 上次使用的颜色
    var lastColor: NSColor?
    /// 上次使用的粗细
    var lastSize: CGFloat?
    /// 上次使用的不透明度
    var lastOpacity: CGFloat?
    /// 上次使用的压感
    var lastPressureSensitivity: PressureSensitivity?
    /// 上次是否为荧光笔
    var lastHighlighter: Bool?
    
    /// 所有预设
    private(set) var allPresets: [BrushPreset] = []
    /// 初始化中标志（防止 init 过程中自动保存覆盖用户设置）
    private var isInitializing = true
    
    /// 设置变更通知
    static let settingsChangedNotification = Notification.Name("BrushSettingsChanged")
    /// 预设列表变更通知
    static let presetsChangedNotification = Notification.Name("BrushPresetsChanged")
    
    private init() {
        loadPresets()
        // 先恢复保存的设置（颜色、粗细、压感、数位板模式等）
        loadSettings()
        // 保存用户上次的各项设置（loadSettings 恢复的）
        let userColor = self.color
        let userSize = self.size
        let userOpacity = self.opacity
        let hadSavedColor = UserDefaults.standard.object(forKey: "brushColorR") != nil
        let hadSavedSize = UserDefaults.standard.object(forKey: "brushSize") != nil
        let hadSavedOpacity = UserDefaults.standard.object(forKey: "brushOpacity") != nil
        
        // 应用预设（会设置预设的颜色/粗细/压感等）
        if let lastId = UserDefaults.standard.string(forKey: "lastUsedPresetId"),
           let lastPreset = allPresets.first(where: { $0.id == lastId }) {
            applyPreset(lastPreset)
        } else if allPresets.count > 1 {
            applyPreset(allPresets[1])
        }
        
        // 恢复用户独立保存的设置（覆盖预设的值）
        // 注：pressureSensitivity 已是 UserDefaults 计算属性，无需手动恢复
        if hadSavedColor { self.color = userColor }
        if hadSavedSize { self.size = userSize }
        if hadSavedOpacity { self.opacity = userOpacity }
        
        isInitializing = false
    }
    
    // MARK: - 预设管理
    
    /// 加载预设列表（使用内置默认预设）
    func loadPresets() {
        // 清除旧的自定义画笔数据
        UserDefaults.standard.removeObject(forKey: "brushPresets")
        allPresets = BrushPreset.defaultPresets()
    }
    

    
    /// 保存当前设置为\"上次使用\"
    private func saveCurrentAsLast() {
        if !isEraser && !isStrokeEraser && !isLassoMode {
            lastColor = color
            lastSize = size
            lastOpacity = opacity
            lastPressureSensitivity = pressureSensitivity
            lastHighlighter = isHighlighter
        }
    }
    
    /// 应用预设
    func applyPreset(_ preset: BrushPreset) {
        saveCurrentAsLast()
        currentPreset = preset
        size = preset.size
        isEraser = preset.isEraser
        isStrokeEraser = false
        isLassoMode = false
        isHighlighter = preset.isHighlighter
        // 压感是用户级偏好，仅在用户从未设置过时使用预设默认值
        if UserDefaults.standard.object(forKey: "pressureSensitivityV2") == nil {
            pressureSensitivity = preset.sensitivity
        }
        
        if !isEraser {
            color = preset.color
            opacity = preset.opacity
        }
        
        // 记忆上次使用的画笔预设 ID
        UserDefaults.standard.set(preset.id, forKey: "lastUsedPresetId")
        
        notifyChanges()
    }
    
    /// 切换到普通橡皮擦模式
    /// 强制恢复为普通画笔模式（关闭橡皮擦、索套等，并恢复上次的颜色和粗细）
    @objc func forcePenMode() {
        if isEraser || isStrokeEraser || isLassoMode {
            isEraser = false
            isStrokeEraser = false
            isLassoMode = false
            
            // 如果之前有选中的预设，应用它；否则恢复上次的全部状态
            if let preset = currentPreset {
                applyPreset(preset)
            } else {
                if let c = lastColor { color = c }
                if let s = lastSize { size = s }
                if let o = lastOpacity { opacity = o }
                if let p = lastPressureSensitivity { pressureSensitivity = p }
                if let h = lastHighlighter { isHighlighter = h }
            }
            notifyChanges()
        }
    }
    func setEraserMode(size: CGFloat? = nil) {
        saveCurrentAsLast()
        self.size = size ?? eraserSize
        isEraser = true
        isStrokeEraser = false
        isLassoMode = false
        isHighlighter = false
        currentPreset = nil
        pressureSensitivity = .off
        lastEraserWasStroke = false  // 记住使用了普通橡皮擦
        notifyChanges()
    }
    
    /// 设置橡皮擦粗细
    func setEraserSize(_ newSize: CGFloat) {
        let clamped = max(5, min(100, newSize))
        eraserSize = clamped
        if isEraser || isStrokeEraser {
            size = clamped
            notifyChanges()
        }
    }
    
    /// 切换到整笔擦除模式
    func setStrokeEraserMode() {
        saveCurrentAsLast()
        isEraser = false
        isStrokeEraser = true
        isLassoMode = false
        isHighlighter = false
        currentPreset = nil
        lastEraserWasStroke = true  // 记住使用了整笔橡皮擦
        notifyChanges()
    }
    
    /// 切换橡皮擦模式（快捷键专用）
    /// 如果当前在任一橡皮擦模式，恢复之前的笔刷；否则切换到上次使用的橡皮擦类型
    func toggleEraserMode() {
        if isEraser || isStrokeEraser {
            // 当前在橡皮擦模式，恢复之前的笔刷
            forcePenMode()
        } else {
            // 当前在笔刷模式，切换到上次使用的橡皮擦类型
            if lastEraserWasStroke {
                setStrokeEraserMode()
            } else {
                setEraserMode()
            }
        }
    }
    
    /// 切换到索套选择模式
    func setLassoMode() {
        saveCurrentAsLast()
        isEraser = false
        isStrokeEraser = false
        isLassoMode = true
        isHighlighter = false
        currentPreset = nil
        notifyChanges()
    }
    
    /// 恢复上次使用的设置
    func restoreLastUsed() {
        guard let savedColor = lastColor, let savedSize = lastSize else { return }
        saveCurrentAsLast()
        color = savedColor
        size = savedSize
        opacity = lastOpacity ?? 1.0
        isEraser = false
        isLassoMode = false
        isHighlighter = false
        currentPreset = nil
        notifyChanges()
    }
    
    /// 设置自定义颜色
    func setCustomColor(_ newColor: NSColor) {
        saveCurrentAsLast()
        color = newColor
        currentPreset = nil
        isEraser = false
        isStrokeEraser = false
        isLassoMode = false
        // 如果当前压感为关闭状态（例如从荧光笔切换过来），恢复为中等压感
        if !pressureSensitivity.isEnabled {
            pressureSensitivity = .medium
        }
        // 同步到颜色气泡的最近使用列表
        ColorBubblePanel.pushRecentColor(newColor)
        // 保留 isHighlighter 状态，允许荧光笔换色
        notifyChanges()
    }
    
    /// 设置自定义粗细
    func setCustomSize(_ newSize: CGFloat) {
        saveCurrentAsLast()
        size = max(1, min(50, newSize))
        currentPreset = nil
        notifyChanges()
    }
    
    /// 获取压感调整后的粗细
    func pressureAdjustedSize(pressure: CGFloat) -> CGFloat {
        if !pressureSensitivity.isEnabled {
            // 压感关闭时返回固定粗细
            return size
        }
        let minSize = size * 0.2
        let maxSize = size * (1.0 + pressureSensitivity.multiplier)
        return minSize + (maxSize - minSize) * pressure
    }
    
    /// 通知设置变更（并自动保存）
    private func notifyChanges() {
        if !isInitializing {
            saveSettings()
        }
        NotificationCenter.default.post(
            name: BrushSettings.settingsChangedNotification,
            object: self
        )
    }
    
    // MARK: - 保存路径设置
    
    /// 截图默认保存路径
    var screenshotSavePath: String {
        get {
            return UserDefaults.standard.string(forKey: "screenshotSavePath")
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
                ?? NSHomeDirectory()
        }
        set { UserDefaults.standard.set(newValue, forKey: "screenshotSavePath") }
    }
    
    /// 白色背景图片默认保存路径
    var whiteBackgroundSavePath: String {
        get {
            return UserDefaults.standard.string(forKey: "whiteBackgroundSavePath")
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
                ?? NSHomeDirectory()
        }
        set { UserDefaults.standard.set(newValue, forKey: "whiteBackgroundSavePath") }
    }
    
    
    /// 从 UserDefaults 加载设置
    func loadSettings() {
        let defaults = UserDefaults.standard
        
        // 用 RGB 分量加载颜色（更可靠）
        if defaults.object(forKey: "brushColorR") != nil {
            let r = CGFloat(defaults.double(forKey: "brushColorR"))
            let g = CGFloat(defaults.double(forKey: "brushColorG"))
            let b = CGFloat(defaults.double(forKey: "brushColorB"))
            color = NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }
        
        if defaults.object(forKey: "brushSize") != nil {
            size = CGFloat(defaults.float(forKey: "brushSize"))
        }
        
        if defaults.object(forKey: "brushOpacity") != nil {
            opacity = CGFloat(defaults.float(forKey: "brushOpacity"))
        }
        
        // pressureSensitivity 已是 UserDefaults 计算属性，无需手动加载
        
        // 恢复数位板专属模式状态
        isTabletOnlyMode = defaults.bool(forKey: "isTabletOnlyMode")
    }
    
    /// 保存设置到 UserDefaults
    func saveSettings() {
        let defaults = UserDefaults.standard
        
        // 确定要保存的画笔颜色和粗细
        // 如果当前在橡皮擦/索套模式，保存上次的画笔状态（而非橡皮擦的值）
        let isInSpecialMode = isEraser || isStrokeEraser || isLassoMode
        let saveColor = isInSpecialMode ? (lastColor ?? color) : color
        let saveSize = isInSpecialMode ? (lastSize ?? size) : size
        let saveOpacity = isInSpecialMode ? (lastOpacity ?? opacity) : opacity
        
        // 用 RGB 分量保存颜色
        if let rgb = saveColor.usingColorSpace(.sRGB) {
            defaults.set(Double(rgb.redComponent), forKey: "brushColorR")
            defaults.set(Double(rgb.greenComponent), forKey: "brushColorG")
            defaults.set(Double(rgb.blueComponent), forKey: "brushColorB")
        }
        
        defaults.set(Float(saveSize), forKey: "brushSize")
        defaults.set(Float(saveOpacity), forKey: "brushOpacity")
        // pressureSensitivity 已是 UserDefaults 计算属性，无需手动保存
    }
}
