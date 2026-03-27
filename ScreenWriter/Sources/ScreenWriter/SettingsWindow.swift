import Cocoa
import Carbon.HIToolbox

/// 颜色方块按钮 - 现代化的自定义颜色选择按钮
class ColorSwatchButton: NSButton {
    var swatchColor: NSColor
    var isSelectedColor: Bool = false {
        didSet { needsDisplay = true }
    }
    
    init(color: NSColor) {
        self.swatchColor = color
        super.init(frame: .zero)
        self.setButtonType(.momentaryChange)
        self.isBordered = false
        self.title = ""
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        swatchColor.setFill()
        path.fill()
        
        // 浅色需要边框（安全计算亮度）
        if let rgb = swatchColor.usingColorSpace(.sRGB) {
            let brightness = (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
            if brightness > 0.8 {
                NSColor(white: 0.8, alpha: 1).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        
        if isSelectedColor {
            let ringPath = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.setStroke()
            ringPath.lineWidth = 2
            ringPath.stroke()
        }
    }
}

/// 设置窗口控制器
class SettingsWindowController: NSWindowController {
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        
        super.init(window: window)
        
        let visualEffectView = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        
        let settingsView = SettingsView(frame: visualEffectView.bounds)
        settingsView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(settingsView)
        
        window.contentView = visualEffectView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
}

/// 设置面板视图
class SettingsView: NSView {
    
    // UI 控件
    private var sizeSlider: NSSlider!
    private var sizeLabel: NSTextField!

    private var colorWell: NSColorWell!
    private var previewView: BrushPreviewView!
    private var sensitivityPopup: NSPopUpButton!
    private var screenshotPathLabel: NSTextField!
    private var whiteBackgroundPathLabel: NSTextField!
    private var shortcutRecorders: [ShortcutRecorderView] = []
    private weak var shortcutManager: ShortcutManager?
    private var colorSwatches: [ColorSwatchButton] = []
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: BrushSettings.settingsChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: BrushSettings.presetsChangedNotification, object: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func settingsChanged() {
        updateUI()
    }
    
    // MARK: - UI 辅助方法
    
    private func createLabel(_ text: String, fontSize: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createSymbolImageView(symbolName: String, size: CGFloat = 16, color: NSColor = .secondaryLabelColor) -> NSImageView {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let imgView: NSImageView
        if let image = image {
            imgView = NSImageView(image: image)
        } else {
            imgView = NSImageView()
        }
        imgView.contentTintColor = color
        imgView.translatesAutoresizingMaskIntoConstraints = false
        return imgView
    }
    
    private func createSectionContainer() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        stack.layer?.cornerRadius = 10
        stack.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        stack.layer?.borderWidth = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    private func createRowStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    private func createSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
    
    // MARK: - UI 搭建
    
    private func setupUI() {
        // 使用 ScrollView 包裹所有内容，防止底部被截断
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        // 使用 flipped view 作为 documentView，确保内容从顶部开始排列
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 20
        mainStack.alignment = .centerX
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            // documentView 宽度跟随 scrollView
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            mainStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 10),
            mainStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
        ])
        
        setupBrushSection(in: mainStack)
        setupPathSection(in: mainStack)
        setupShortcutSection(in: mainStack)
        
        updateUI()
    }
    
        private func createGridRow(icon: String, label: String, view: NSView, viewWidth: CGFloat? = nil) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 16
        row.alignment = .centerY
        
        let labelStack = NSStackView()
        labelStack.orientation = .horizontal
        labelStack.spacing = 8
        labelStack.alignment = .centerY
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        labelStack.widthAnchor.constraint(equalToConstant: 80).isActive = true // 固定左列宽度
        
        if !icon.isEmpty {
            labelStack.addArrangedSubview(createSymbolImageView(symbolName: icon, size: 14))
        } else {
            let spacer = NSView()
            spacer.widthAnchor.constraint(equalToConstant: 16).isActive = true
            labelStack.addArrangedSubview(spacer)
        }
        
        let titleLabel = createLabel(label, fontSize: 13, weight: .medium, color: .labelColor)
        titleLabel.alignment = .right
        labelStack.addArrangedSubview(titleLabel)
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labelStack.addArrangedSubview(spacer)
        
        row.addArrangedSubview(labelStack)
        
        if let w = viewWidth {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        row.addArrangedSubview(view)
        
        // 确保行不超出容器宽度
        row.translatesAutoresizingMaskIntoConstraints = false
        
        return row
    }

    private func setupBrushSection(in parentStack: NSStackView) {
        let container = createSectionContainer()
        let settings = BrushSettings.shared
        
        // 标题
        let headerRow = createRowStack()
        headerRow.addArrangedSubview(createSymbolImageView(symbolName: "paintbrush.fill", size: 18, color: .controlAccentColor))
        headerRow.addArrangedSubview(createLabel("画笔设置", fontSize: 14, weight: .semibold))
        container.addArrangedSubview(headerRow)
        
        // 预设
        let presetStack = NSStackView()
        presetStack.orientation = .horizontal
        presetStack.spacing = 8
        presetStack.alignment = .centerY
        presetStack.translatesAutoresizingMaskIntoConstraints = false
        
        for (index, preset) in settings.allPresets.enumerated() {
            let button = NSButton(title: preset.displayName, target: self, action: #selector(presetClicked(_:)))
            button.bezelStyle = .recessed
            button.tag = index
            presetStack.addArrangedSubview(button)
        }
        
        // 使用 createGridRow 包装预设
        container.addArrangedSubview(createGridRow(icon: "star", label: "预设", view: presetStack))
        container.addArrangedSubview(createSeparator())
        
        // 颜色
        colorWell = NSColorWell()
        colorWell.color = settings.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 40),
            colorWell.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let quickColors: [NSColor] = [
            .black,
            NSColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1),
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1),
            NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1),
            NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1),
            NSColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1),
            NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1),
            .white
        ]
        
        let swatchStack = NSStackView()
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 2
        for (index, color) in quickColors.enumerated() {
            let btn = ColorSwatchButton(color: color)
            btn.target = self
            btn.action = #selector(quickColorClicked(_:))
            btn.tag = index
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 24),
                btn.heightAnchor.constraint(equalToConstant: 24)
            ])
            swatchStack.addArrangedSubview(btn)
            colorSwatches.append(btn)
        }
        
        let colorContentStack = NSStackView()
        colorContentStack.orientation = .horizontal
        colorContentStack.spacing = 12
        colorContentStack.addArrangedSubview(colorWell)
        colorContentStack.addArrangedSubview(swatchStack)
        
        container.addArrangedSubview(createGridRow(icon: "paintpalette", label: "颜色", view: colorContentStack))
        container.addArrangedSubview(createSeparator())
        
        // 粗细
        sizeSlider = NSSlider(value: Double(settings.size), minValue: 1, maxValue: 50, target: self, action: #selector(sizeChanged(_:)))
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        
        sizeLabel = createLabel("\(Int(settings.size)) pt", fontSize: 12, weight: .medium)
        sizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        sizeLabel.alignment = .right
        
        let sizeContentStack = NSStackView()
        sizeContentStack.orientation = .horizontal
        sizeContentStack.spacing = 8
        sizeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sizeContentStack.addArrangedSubview(sizeSlider)
        sizeContentStack.addArrangedSubview(sizeLabel)
        
        container.addArrangedSubview(createGridRow(icon: "lineweight", label: "粗细", view: sizeContentStack))
        container.addArrangedSubview(createSeparator())
        
        // 压感
        sensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sensitivityPopup.addItems(withTitles: ["关闭", "低", "中", "高"])
        sensitivityPopup.target = self
        sensitivityPopup.action = #selector(sensitivityChanged(_:))
        
        container.addArrangedSubview(createGridRow(icon: "scribble.variable", label: "压感", view: sensitivityPopup, viewWidth: 100))
        container.addArrangedSubview(createSeparator())
        
        // 预览
        previewView = BrushPreviewView(frame: .zero)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        previewView.layer?.cornerRadius = 8
        previewView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        previewView.layer?.borderWidth = 1
        previewView.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        let previewContainer = NSStackView()
        previewContainer.alignment = .centerX
        previewContainer.orientation = .horizontal
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addArrangedSubview(previewView)
        container.addArrangedSubview(previewContainer)
        
        // 预览容器和预览视图宽度跟随 container
        previewContainer.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        previewView.widthAnchor.constraint(equalTo: previewContainer.widthAnchor).isActive = true
        
        parentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: parentStack.widthAnchor).isActive = true
    }
    
    private func setupPathSection(in parentStack: NSStackView) {
        let container = createSectionContainer()
        let settings = BrushSettings.shared
        
        let headerRow = createRowStack()
        headerRow.addArrangedSubview(createSymbolImageView(symbolName: "folder.fill", size: 18, color: .controlAccentColor))
        headerRow.addArrangedSubview(createLabel("保存路径", fontSize: 14, weight: .semibold))
        container.addArrangedSubview(headerRow)
        
        // 截图路径
        screenshotPathLabel = NSTextField(labelWithString: shortenPath(settings.screenshotSavePath))
        screenshotPathLabel.font = NSFont.systemFont(ofSize: 11)
        screenshotPathLabel.textColor = .labelColor
        screenshotPathLabel.lineBreakMode = .byTruncatingMiddle
        screenshotPathLabel.translatesAutoresizingMaskIntoConstraints = false
        screenshotPathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true
        screenshotPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        let screenshotBrowseBtn = NSButton(title: "更改...", target: self, action: #selector(browseScreenshotPath))
        screenshotBrowseBtn.bezelStyle = .rounded
        screenshotBrowseBtn.controlSize = .small
        
        let screenshotStack = NSStackView()
        screenshotStack.orientation = .horizontal
        screenshotStack.spacing = 8
        screenshotStack.addArrangedSubview(screenshotPathLabel)
        screenshotStack.addArrangedSubview(screenshotBrowseBtn)
        
        container.addArrangedSubview(createGridRow(icon: "photo", label: "截图保存", view: screenshotStack))
        container.addArrangedSubview(createSeparator())
        
        // 白底路径
        whiteBackgroundPathLabel = NSTextField(labelWithString: shortenPath(settings.whiteBackgroundSavePath))
        whiteBackgroundPathLabel.font = NSFont.systemFont(ofSize: 11)
        whiteBackgroundPathLabel.textColor = .labelColor
        whiteBackgroundPathLabel.lineBreakMode = .byTruncatingMiddle
        whiteBackgroundPathLabel.translatesAutoresizingMaskIntoConstraints = false
        whiteBackgroundPathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true
        whiteBackgroundPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        let whiteBgBrowseBtn = NSButton(title: "更改...", target: self, action: #selector(browseWhiteBackgroundPath))
        whiteBgBrowseBtn.bezelStyle = .rounded
        whiteBgBrowseBtn.controlSize = .small
        
        let whiteBgStack = NSStackView()
        whiteBgStack.orientation = .horizontal
        whiteBgStack.spacing = 8
        whiteBgStack.addArrangedSubview(whiteBackgroundPathLabel)
        whiteBgStack.addArrangedSubview(whiteBgBrowseBtn)
        
        container.addArrangedSubview(createGridRow(icon: "doc.richtext", label: "白底保存", view: whiteBgStack))
        
        parentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: parentStack.widthAnchor).isActive = true
    }
    
    private func setupShortcutSection(in parentStack: NSStackView) {
        let container = createSectionContainer()
        
        let headerRow = createRowStack()
        headerRow.addArrangedSubview(createSymbolImageView(symbolName: "keyboard.fill", size: 18, color: .controlAccentColor))
        headerRow.addArrangedSubview(createLabel("快捷键", fontSize: 14, weight: .semibold))
        
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(spacer)
        
        let resetAllBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetAllShortcuts))
        resetAllBtn.bezelStyle = .recessed
        resetAllBtn.controlSize = .small
        headerRow.addArrangedSubview(resetAllBtn)
        
        container.addArrangedSubview(headerRow)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let appDelegate = NSApp.delegate as? AppDelegate
        shortcutManager = appDelegate?.shortcutManager
        let currentConfig = shortcutManager?.config ?? ShortcutConfig()
        
        let shortcutItems: [(String, String, NSEvent.ModifierFlags, UInt16)] = [
            ("pencil.and.outline", "快捷启动", currentConfig.quickLaunchModifiers, currentConfig.quickLaunchKeyCode),
            ("trash", "清除画布", currentConfig.clearCanvasModifiers, currentConfig.clearCanvasKeyCode),
            ("camera", "保存截图", currentConfig.saveScreenshotModifiers, currentConfig.saveScreenshotKeyCode),
            ("eraser", "橡皮擦", currentConfig.toggleEraserModifiers, currentConfig.toggleEraserKeyCode),
            ("arrow.uturn.backward", "撤销", currentConfig.undoModifiers, currentConfig.undoKeyCode),
            ("arrow.uturn.forward", "重做", currentConfig.redoModifiers, currentConfig.redoKeyCode),
        ]
        
        for (index, (icon, name, modifiers, keyCode)) in shortcutItems.enumerated() {
            let recorder = ShortcutRecorderView(modifiers: modifiers, keyCode: keyCode)
            recorder.tag = index
            recorder.onShortcutChanged = { [weak self] newModifiers, newKeyCode in
                self?.shortcutChanged(index: index, modifiers: newModifiers, keyCode: newKeyCode)
            }
            recorder.onRecordingStarted = { [weak self] in
                self?.shortcutManager?.isEnabled = false
            }
            recorder.onRecordingStopped = { [weak self] in
                self?.shortcutManager?.isEnabled = true
            }
            recorder.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                recorder.widthAnchor.constraint(equalToConstant: 140),
                recorder.heightAnchor.constraint(equalToConstant: 26)
            ])
            shortcutRecorders.append(recorder)
            
            let resetBtn = NSButton(title: "重置", target: self, action: #selector(resetShortcut(_:)))
            resetBtn.bezelStyle = .recessed
            resetBtn.tag = index
            resetBtn.controlSize = .small
            
            let actionStack = NSStackView()
            actionStack.orientation = .horizontal
            actionStack.spacing = 8
            actionStack.addArrangedSubview(recorder)
            actionStack.addArrangedSubview(resetBtn)
            
            container.addArrangedSubview(createGridRow(icon: icon, label: name, view: actionStack))
            
            if index < shortcutItems.count - 1 {
                container.addArrangedSubview(createSeparator())
            }
        }
        
        parentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: parentStack.widthAnchor).isActive = true
    }

    // MARK: - 操作响应
    
    @objc private func presetClicked(_ sender: NSButton) {
        let presets = BrushSettings.shared.allPresets
        guard sender.tag < presets.count else { return }
        let preset = presets[sender.tag]
        BrushSettings.shared.applyPreset(preset)
        updateUI()
    }
    
    @objc private func colorChanged(_ sender: NSColorWell) {
        BrushSettings.shared.setCustomColor(sender.color)
        updateSwatches()
    }
    
    @objc private func quickColorClicked(_ sender: ColorSwatchButton) {
        let color = sender.swatchColor
        BrushSettings.shared.setCustomColor(color)
        colorWell.color = color
        updateSwatches()
    }
    
    private func updateSwatches() {
        let currentColor = BrushSettings.shared.color
        for swatch in colorSwatches {
            swatch.isSelectedColor = colorsMatch(swatch.swatchColor, currentColor)
        }
    }
    
    private func colorsMatch(_ c1: NSColor, _ c2: NSColor) -> Bool {
        guard let rgb1 = c1.usingColorSpace(.sRGB), let rgb2 = c2.usingColorSpace(.sRGB) else { return false }
        return abs(rgb1.redComponent - rgb2.redComponent) < 0.05 &&
               abs(rgb1.greenComponent - rgb2.greenComponent) < 0.05 &&
               abs(rgb1.blueComponent - rgb2.blueComponent) < 0.05
    }
    
    @objc private func sizeChanged(_ sender: NSSlider) {
        let size = CGFloat(sender.doubleValue)
        BrushSettings.shared.setCustomSize(size)
    }
    

    
    @objc private func sensitivityChanged(_ sender: NSPopUpButton) {
        let sensitivities: [PressureSensitivity] = [.off, .low, .medium, .high]
        let index = sender.indexOfSelectedItem
        if index >= 0 && index < sensitivities.count {
            BrushSettings.shared.pressureSensitivity = sensitivities[index]
        }
    }
    
    @objc private func browseScreenshotPath() {
        if let path = chooseSavePath(title: "选择截图保存路径") {
            BrushSettings.shared.screenshotSavePath = path
            screenshotPathLabel.stringValue = shortenPath(path)
        }
    }
    
    @objc private func browseWhiteBackgroundPath() {
        if let path = chooseSavePath(title: "选择白色背景保存路径") {
            BrushSettings.shared.whiteBackgroundSavePath = path
            whiteBackgroundPathLabel.stringValue = shortenPath(path)
        }
    }
    
    private func chooseSavePath(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.level = .floating
        
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }
    
    private func updateUI() {
        let settings = BrushSettings.shared
        sizeSlider.doubleValue = Double(settings.size)
        sizeLabel.stringValue = "\(Int(settings.size)) pt"

        colorWell.color = settings.color
        
        switch settings.pressureSensitivity {
        case .off: sensitivityPopup.selectItem(at: 0)
        case .low: sensitivityPopup.selectItem(at: 1)
        case .medium: sensitivityPopup.selectItem(at: 2)
        case .high: sensitivityPopup.selectItem(at: 3)
        }
        
        updateSwatches()
        previewView.needsDisplay = true
    }
    
    // MARK: - 快捷键操作
    
    private func shortcutChanged(index: Int, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        guard var config = shortcutManager?.config else { return }
        switch index {
        case 0: config.quickLaunchModifiers = modifiers; config.quickLaunchKeyCode = keyCode
        case 1: config.clearCanvasModifiers = modifiers; config.clearCanvasKeyCode = keyCode
        case 2: config.saveScreenshotModifiers = modifiers; config.saveScreenshotKeyCode = keyCode
        case 3: config.toggleEraserModifiers = modifiers; config.toggleEraserKeyCode = keyCode
        case 4: config.undoModifiers = modifiers; config.undoKeyCode = keyCode
        case 5: config.redoModifiers = modifiers; config.redoKeyCode = keyCode
        default: break
        }
        shortcutManager?.updateConfig(config)
    }
    
    @objc private func resetShortcut(_ sender: NSButton) {
        let index = sender.tag
        let defaultConfig = ShortcutConfig.defaultConfig()
        let defaultModifiers: NSEvent.ModifierFlags
        let defaultKeyCode: UInt16
        
        switch index {
        case 0: defaultModifiers = defaultConfig.quickLaunchModifiers; defaultKeyCode = defaultConfig.quickLaunchKeyCode
        case 1: defaultModifiers = defaultConfig.clearCanvasModifiers; defaultKeyCode = defaultConfig.clearCanvasKeyCode
        case 2: defaultModifiers = defaultConfig.saveScreenshotModifiers; defaultKeyCode = defaultConfig.saveScreenshotKeyCode
        case 3: defaultModifiers = defaultConfig.toggleEraserModifiers; defaultKeyCode = defaultConfig.toggleEraserKeyCode
        case 4: defaultModifiers = defaultConfig.undoModifiers; defaultKeyCode = defaultConfig.undoKeyCode
        case 5: defaultModifiers = defaultConfig.redoModifiers; defaultKeyCode = defaultConfig.redoKeyCode
        default: return
        }
        
        if index < shortcutRecorders.count {
            shortcutRecorders[index].setShortcut(modifiers: defaultModifiers, keyCode: defaultKeyCode)
        }
        shortcutChanged(index: index, modifiers: defaultModifiers, keyCode: defaultKeyCode)
    }
    
    @objc private func resetAllShortcuts() {
        let defaultConfig = ShortcutConfig.defaultConfig()
        let defaults: [(NSEvent.ModifierFlags, UInt16)] = [
            (defaultConfig.quickLaunchModifiers, defaultConfig.quickLaunchKeyCode),
            (defaultConfig.clearCanvasModifiers, defaultConfig.clearCanvasKeyCode),
            (defaultConfig.saveScreenshotModifiers, defaultConfig.saveScreenshotKeyCode),
            (defaultConfig.toggleEraserModifiers, defaultConfig.toggleEraserKeyCode),
            (defaultConfig.undoModifiers, defaultConfig.undoKeyCode),
            (defaultConfig.redoModifiers, defaultConfig.redoKeyCode),
        ]
        
        for (index, (modifiers, keyCode)) in defaults.enumerated() {
            if index < shortcutRecorders.count {
                shortcutRecorders[index].setShortcut(modifiers: modifiers, keyCode: keyCode)
            }
        }
        shortcutManager?.resetToDefault()
    }
}

// MARK: - 画笔预览视图及其他

/// 画笔预览视图
class BrushPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        
        let settings = BrushSettings.shared
        
        if settings.isEraser {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let text = "橡皮擦模式"
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2), withAttributes: attrs)
            return
        }
        
        let startX: CGFloat = 20
        let endX = bounds.width - 20
        let centerY = bounds.height / 2
        let steps = 50
        
        if settings.isHighlighter {
            let path = NSBezierPath()
            path.lineWidth = settings.size
            path.lineCapStyle = .square
            path.lineJoinStyle = .round
            settings.color.withAlphaComponent(settings.opacity).setStroke()
            
            path.move(to: NSPoint(x: startX, y: centerY))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = startX + (endX - startX) * t
                let wave = sin(t * .pi * 3) * 8
                path.line(to: NSPoint(x: x, y: centerY + wave))
            }
            path.stroke()
        } else {
            settings.color.withAlphaComponent(settings.opacity).setStroke()
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = startX + (endX - startX) * t
                let nextX = startX + (endX - startX) * CGFloat(i + 1) / CGFloat(steps)
                let pressure = t
                let lineWidth = settings.pressureAdjustedSize(pressure: pressure)
                let wave = sin(t * .pi * 3) * 10
                let nextWave = sin(CGFloat(i + 1) / CGFloat(steps) * .pi * 3) * 10
                
                let segment = NSBezierPath()
                segment.lineWidth = lineWidth
                segment.lineCapStyle = .round
                segment.move(to: NSPoint(x: x, y: centerY + wave))
                segment.line(to: NSPoint(x: nextX, y: centerY + nextWave))
                segment.stroke()
            }
        }
    }
}

/// 快捷键录制视图
class ShortcutRecorderView: NSView {
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var currentKeyCode: UInt16 = 0
    private var isRecording = false
    var onShortcutChanged: ((NSEvent.ModifierFlags, UInt16) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    private var localMonitor: Any?
    
    override var tag: Int { get { return _tag } set { _tag = newValue } }
    private var _tag: Int = 0
    
    init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.currentModifiers = modifiers
        self.currentKeyCode = keyCode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateAppearance()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }
    
    func setShortcut(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        currentModifiers = modifiers
        currentKeyCode = keyCode
        needsDisplay = true
        updateAppearance()
    }
    
    private func updateAppearance() {
        if isRecording {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
    
    override var acceptsFirstResponder: Bool { return true }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let text: String
        if isRecording {
            text = "录制中..."
        } else if currentKeyCode == 0 && currentModifiers.isEmpty {
            text = "点击设置"
        } else {
            text = ShortcutManager.shortcutDisplayText(modifiers: currentModifiers, keyCode: currentKeyCode)
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - textSize.width) / 2, y: (bounds.height - textSize.height) / 2), withAttributes: attrs)
    }
    
    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }
    
    private func startRecording() {
        isRecording = true
        updateAppearance()
        needsDisplay = true
        onRecordingStarted?()
        window?.makeFirstResponder(self)
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            if event.type == .keyDown {
                let keyCode = event.keyCode
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if keyCode == UInt16(kVK_Escape) { self.stopRecording(); return nil }
                if modifiers.isEmpty { return nil }
                self.currentModifiers = modifiers
                self.currentKeyCode = keyCode
                self.stopRecording()
                self.onShortcutChanged?(self.currentModifiers, self.currentKeyCode)
                return nil
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
        updateAppearance()
        needsDisplay = true
        onRecordingStopped?()
    }
    
    deinit { if let monitor = localMonitor { NSEvent.removeMonitor(monitor) } }
}

/// 翻转视图 - 确保 ScrollView 中内容从顶部开始排列
class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}
