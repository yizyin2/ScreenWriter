import Cocoa

// MARK: - 工具栏按钮

class ToolbarButton: NSButton {
    var isSelectedTool: Bool = false {
        didSet { needsDisplay = true }
    }
    
    init(symbolName: String, size: CGFloat = 16, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        self.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        self.isBordered = false
        self.setButtonType(.momentaryChange)
        self.target = target
        self.action = action
        // 禁用焦点环，避免异常边框
        self.focusRingType = .none
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        if isSelectedTool {
            let bgPath = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
            NSColor.controlAccentColor.setFill()
            bgPath.fill()
            self.contentTintColor = .white
        } else {
            self.contentTintColor = .labelColor
        }
        super.draw(dirtyRect)
    }
}

// MARK: - 圆角颜色按钮（纯 Core Graphics 绘制，无任何系统控件）

class RoundColorButton: NSView {
    
    var color: NSColor = .black {
        didSet { setNeedsDisplay(bounds) }
    }
    var onColorClicked: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 完全透明背景
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        // 禁用焦点环
        focusRingType = .none
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override var focusRingType: NSFocusRingType {
        get { return .none }
        set { super.focusRingType = .none }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // 清除所有之前的绘制内容
        ctx.clear(bounds)
        
        // 圆形区域
        let circleRect = bounds.insetBy(dx: 3, dy: 3)
        let circlePath = CGPath(ellipseIn: circleRect, transform: nil)
        
        // 填充颜色
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if let rgb = color.usingColorSpace(.sRGB) {
            r = rgb.redComponent; g = rgb.greenComponent; b = rgb.blueComponent; a = rgb.alphaComponent
        }
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: a))
        ctx.addPath(circlePath)
        ctx.fillPath()
        
        // 细边框
        let brightness = (r + g + b) / 3
        if brightness > 0.7 {
            ctx.setStrokeColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.8))
        } else {
            ctx.setStrokeColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.35))
        }
        ctx.setLineWidth(1.5)
        ctx.addPath(circlePath)
        ctx.strokePath()
    }
    
    override func mouseDown(with event: NSEvent) {
        onColorClicked?()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }
}

// MARK: - 颜色气泡弹窗（最近使用颜色网格）

class ColorBubblePanel: NSPanel {
    
    /// 默认颜色（初始填充，按顺序被最近使用颜色覆盖）
    static let defaultColors: [NSColor] = [
        NSColor(red: 0, green: 0, blue: 0, alpha: 1),          // 黑色
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1),    // 红色
        NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1),    // 蓝色
        NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1),    // 绿色
        NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1),    // 橙色
        NSColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1),    // 紫色
        NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1),   // 黄色
        NSColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1),    // 粉色
        NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1),    // 青色
        NSColor(red: 1, green: 1, blue: 1, alpha: 1),          // 白色
        NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),    // 灰色
        NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1),    // 棕色
    ]
    
    /// 最近使用颜色的 UserDefaults key
    private static let recentColorsKey = "recentToolbarColors"
    
    /// 加载最近使用的颜色
    static func loadRecentColors() -> [NSColor] {
        guard let data = UserDefaults.standard.data(forKey: recentColorsKey),
              let rgbList = try? JSONDecoder().decode([[CGFloat]].self, from: data) else {
            return defaultColors
        }
        var colors = rgbList.map { NSColor(red: $0[0], green: $0[1], blue: $0[2], alpha: 1) }
        // 不足 12 个时用默认色补齐
        while colors.count < 12 {
            let fillIndex = colors.count
            if fillIndex < defaultColors.count {
                colors.append(defaultColors[fillIndex])
            } else {
                break
            }
        }
        return colors
    }
    
    /// 保存最近使用的颜色
    static func saveRecentColors(_ colors: [NSColor]) {
        let rgbList: [[CGFloat]] = colors.prefix(12).map { c in
            if let rgb = c.usingColorSpace(.sRGB) {
                return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
            }
            return [0, 0, 0]
        }
        if let data = try? JSONEncoder().encode(rgbList) {
            UserDefaults.standard.set(data, forKey: recentColorsKey)
        }
    }
    
    /// 将颜色添加到最近使用列表最前面
    static func pushRecentColor(_ color: NSColor) {
        var colors = loadRecentColors()
        // 移除已有的相同颜色
        colors.removeAll { colorsMatch($0, color) }
        // 插入到最前
        colors.insert(color, at: 0)
        // 最多保留 12 个，溢出的自动丢弃
        if colors.count > 12 { colors = Array(colors.prefix(12)) }
        saveRecentColors(colors)
    }
    
    /// 颜色匹配（容差比较）
    static func colorsMatch(_ c1: NSColor, _ c2: NSColor) -> Bool {
        guard let rgb1 = c1.usingColorSpace(.sRGB),
              let rgb2 = c2.usingColorSpace(.sRGB) else { return false }
        return abs(rgb1.redComponent - rgb2.redComponent) < 0.03 &&
               abs(rgb1.greenComponent - rgb2.greenComponent) < 0.03 &&
               abs(rgb1.blueComponent - rgb2.blueComponent) < 0.03
    }
    
    var onColorSelected: ((NSColor) -> Void)?
    
    init(relativeTo anchorView: NSView) {
        // 3 列 x 4 行布局
        let cols = 3
        let rows = 4
        let cellSize: CGFloat = 28
        let spacing: CGFloat = 6
        let padding: CGFloat = 12
        let cornerRadius: CGFloat = 12
        
        let contentW = padding * 2 + CGFloat(cols) * cellSize + CGFloat(cols - 1) * spacing
        let contentH = padding * 2 + CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
        let panelSize = NSSize(width: contentW, height: contentH)
        
        super.init(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar + 3
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false  // 禁用系统阴影，避免矩形边框
        
        let roundedPath = CGPath(roundedRect: NSRect(origin: .zero, size: panelSize),
                                 cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // 透明容器 + 圆角 layer 阴影
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.35
        container.layer?.shadowRadius = 8
        container.layer?.shadowOffset = NSSize(width: 0, height: -2)
        container.layer?.shadowPath = roundedPath
        
        // 毛玻璃效果背景（与工具栏一致）
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        // CAShapeLayer mask 裁剪为圆角矩形
        let effectMask = CAShapeLayer()
        effectMask.path = roundedPath
        effectView.layer?.mask = effectMask
        
        // 加载颜色并创建颜色格子
        let colors = ColorBubblePanel.loadRecentColors()
        for (index, color) in colors.prefix(12).enumerated() {
            let row = index / cols
            let col = index % cols
            let x = padding + CGFloat(col) * (cellSize + spacing)
            let y = contentH - padding - CGFloat(row + 1) * cellSize - CGFloat(row) * spacing
            
            let cell = ColorCell(frame: NSRect(x: x, y: y, width: cellSize, height: cellSize))
            cell.color = color
            cell.isCurrentColor = ColorBubblePanel.colorsMatch(color, BrushSettings.shared.color)
            cell.onSelect = { [weak self] selectedColor in
                self?.onColorSelected?(selectedColor)
                ColorBubblePanel.pushRecentColor(selectedColor)
                self?.orderOut(nil)
            }
            effectView.addSubview(cell)
        }
        
        container.addSubview(effectView)
        self.contentView = container
        
        // 对 NSThemeFrame 也应用圆角 mask（消除矩形边框）
        if let themeFrame = self.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
            let frameMask = CAShapeLayer()
            frameMask.path = CGPath(roundedRect: themeFrame.bounds,
                                    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            themeFrame.layer?.mask = frameMask
        }
        
        // 计算弹出位置（智能避开屏幕边缘）
        positionRelativeTo(anchorView: anchorView, panelSize: panelSize)
    }
    
    /// 智能定位：优先右侧弹出，空间不足时改为左侧
    private func positionRelativeTo(anchorView: NSView, panelSize: NSSize) {
        guard let window = anchorView.window else { return }
        
        let anchorFrame = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenFrame = window.convertToScreen(NSRect(
            x: anchorFrame.origin.x,
            y: anchorFrame.origin.y,
            width: anchorFrame.width,
            height: anchorFrame.height
        ))
        
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: anchorScreenFrame.midX, y: anchorScreenFrame.midY))
        }) ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        
        let gap: CGFloat = 8
        var originX: CGFloat
        var originY: CGFloat = anchorScreenFrame.midY - panelSize.height / 2
        
        let rightX = anchorScreenFrame.maxX + gap
        if rightX + panelSize.width <= screenFrame.maxX {
            originX = rightX
        } else {
            let leftX = anchorScreenFrame.minX - gap - panelSize.width
            if leftX >= screenFrame.minX {
                originX = leftX
            } else {
                originX = screenFrame.maxX - panelSize.width - 4
            }
        }
        
        if originY < screenFrame.minY { originY = screenFrame.minY + 4 }
        if originY + panelSize.height > screenFrame.maxY { originY = screenFrame.maxY - panelSize.height - 4 }
        
        self.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
    
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

// MARK: - 颜色格子

class ColorCell: NSView {
    
    var color: NSColor = .black {
        didSet { needsDisplay = true }
    }
    var isCurrentColor: Bool = false {
        didSet { needsDisplay = true }
    }
    var onSelect: ((NSColor) -> Void)?
    private var isHovered = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        
        let inset: CGFloat = isHovered ? 1 : 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        
        // 填充颜色
        color.setFill()
        path.fill()
        
        // 边框
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        if let rgb = color.usingColorSpace(.sRGB) {
            r = rgb.redComponent; g = rgb.greenComponent; b = rgb.blueComponent
        }
        let brightness = (r + g + b) / 3
        if brightness > 0.7 {
            NSColor(white: 0.5, alpha: 0.8).setStroke()
        } else {
            NSColor(white: 0.7, alpha: 0.3).setStroke()
        }
        path.lineWidth = isHovered ? 2.0 : 1.0
        path.stroke()
        
        // 选中勾号
        if isCurrentColor {
            let checkColor: NSColor = brightness > 0.5 ? .black : .white
            checkColor.setStroke()
            let checkPath = NSBezierPath()
            checkPath.lineWidth = 2.5
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            let cx = bounds.midX, cy = bounds.midY
            checkPath.move(to: NSPoint(x: cx - 5, y: cy))
            checkPath.line(to: NSPoint(x: cx - 1, y: cy - 4))
            checkPath.line(to: NSPoint(x: cx + 5, y: cy + 4))
            checkPath.stroke()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        onSelect?(color)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}

// MARK: - 粗细显示标签（可点击输入）

class SizeLabel: NSView {
    
    var sizeValue: CGFloat = 3 {
        didSet { needsDisplay = true }
    }
    
    /// 点击回调
    var onClicked: (() -> Void)?
    
    private var isHovered = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // 悬停时绘制高亮背景
        if isHovered {
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
            let bgPath = CGPath(roundedRect: bounds.insetBy(dx: 2, dy: 1),
                                cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(bgPath)
            ctx.fillPath()
        }
        
        let text = "\(Int(sizeValue))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: isHovered
                ? NSColor(white: 1.0, alpha: 0.95)
                : NSColor(white: 0.85, alpha: 0.8)
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        let point = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        )
        attrStr.draw(at: point)
    }
    
    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        needsDisplay = true
    }
}

// MARK: - 粗细输入弹出面板

class SizeInputPanel: NSPanel, NSTextFieldDelegate {
    
    /// 输入确认回调
    var onSizeConfirmed: ((CGFloat) -> Void)?
    
    private let textField: NSTextField
    private let isEraserMode: Bool
    
    init(currentSize: CGFloat, isEraser: Bool, relativeTo anchorView: NSView) {
        self.isEraserMode = isEraser
        
        let panelW: CGFloat = 72
        let panelH: CGFloat = 40
        let cornerRadius: CGFloat = 10
        
        // 创建输入框
        textField = NSTextField(frame: NSRect(x: 10, y: 8, width: panelW - 20, height: 24))
        
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelW, height: panelH)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar + 4
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        
        let size = NSSize(width: panelW, height: panelH)
        let roundedPath = CGPath(roundedRect: NSRect(origin: .zero, size: size),
                                 cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // 透明容器 + 阴影
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.4
        container.layer?.shadowRadius = 8
        container.layer?.shadowOffset = NSSize(width: 0, height: -2)
        container.layer?.shadowPath = roundedPath
        
        // 毛玻璃背景
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        let mask = CAShapeLayer()
        mask.path = roundedPath
        effectView.layer?.mask = mask
        
        // 配置输入框
        textField.stringValue = "\(Int(currentSize))"
        textField.alignment = .center
        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        textField.textColor = .white
        textField.backgroundColor = NSColor(white: 1.0, alpha: 0.1)
        textField.isBordered = false
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .none
        textField.delegate = self
        // 选中所有文本方便直接输入
        textField.selectText(nil)
        
        effectView.addSubview(textField)
        container.addSubview(effectView)
        self.contentView = container
        
        // 对 NSThemeFrame 也应用圆角
        if let themeFrame = self.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
            let frameMask = CAShapeLayer()
            frameMask.path = CGPath(roundedRect: themeFrame.bounds,
                                    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            themeFrame.layer?.mask = frameMask
        }
        
        // 定位到锚点视图右侧
        positionRelativeTo(anchorView: anchorView, panelSize: size)
    }
    
    /// 智能定位
    private func positionRelativeTo(anchorView: NSView, panelSize: NSSize) {
        guard let window = anchorView.window else { return }
        
        let anchorFrame = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenFrame = window.convertToScreen(NSRect(
            x: anchorFrame.origin.x,
            y: anchorFrame.origin.y,
            width: anchorFrame.width,
            height: anchorFrame.height
        ))
        
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: anchorScreenFrame.midX, y: anchorScreenFrame.midY))
        }) ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        
        let gap: CGFloat = 8
        var originX: CGFloat
        let originY: CGFloat = anchorScreenFrame.midY - panelSize.height / 2
        
        // 优先右侧弹出
        let rightX = anchorScreenFrame.maxX + gap
        if rightX + panelSize.width <= screenFrame.maxX {
            originX = rightX
        } else {
            let leftX = anchorScreenFrame.minX - gap - panelSize.width
            if leftX >= screenFrame.minX {
                originX = leftX
            } else {
                originX = screenFrame.maxX - panelSize.width - 4
            }
        }
        
        self.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
    
    // MARK: - NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // 回车确认
            confirmInput()
            return true
        } else if commandSelector == #selector(cancelOperation(_:)) {
            // ESC 取消
            orderOut(nil)
            return true
        }
        return false
    }
    
    private func confirmInput() {
        let text = textField.stringValue.trimmingCharacters(in: .whitespaces)
        if let value = Double(text), value > 0 {
            let size = CGFloat(value)
            onSizeConfirmed?(size)
        }
        orderOut(nil)
    }
    
    override func resignKey() {
        super.resignKey()
        confirmInput()
    }
    
    /// 面板显示后自动聚焦输入框
    func activateTextField() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(textField)
        // 选中所有文本
        if let editor = textField.currentEditor() {
            editor.selectAll(nil)
        }
    }
}

// MARK: - 悬浮工具栏面板

class FloatingToolbarPanel: NSPanel {
    
    var onClose: (() -> Void)?
    var onUndo: (() -> Void)?
    var onClear: (() -> Void)?
    var onSaveScreenshot: (() -> Void)?
    var onSaveWhiteBackground: (() -> Void)?
    
    init() {
        let size = NSSize(width: 56, height: 580)
        let cornerRadius: CGFloat = 28
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)
        
        self.isFloatingPanel = true
        self.level = .statusBar + 2
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        let roundedPath = CGPath(roundedRect: NSRect(origin: .zero, size: size),
                                 cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        // 透明容器
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = false
        // 圆角阴影
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.35
        container.layer?.shadowRadius = 10
        container.layer?.shadowOffset = NSSize(width: 0, height: -3)
        container.layer?.shadowPath = roundedPath
        
        // 毛玻璃效果视图
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        // CAShapeLayer mask 裁剪 effectView 为圆角矩形
        let effectMask = CAShapeLayer()
        effectMask.path = roundedPath
        effectView.layer?.mask = effectMask
        
        let toolbarView = FloatingToolbarView(frame: effectView.bounds)
        toolbarView.onClose = { [weak self] in self?.onClose?() }
        toolbarView.onUndo = { [weak self] in self?.onUndo?() }
        toolbarView.onClear = { [weak self] in self?.onClear?() }
        toolbarView.onSaveScreenshot = { [weak self] in self?.onSaveScreenshot?() }
        toolbarView.onSaveWhiteBackground = { [weak self] in self?.onSaveWhiteBackground?() }
        
        effectView.addSubview(toolbarView)
        container.addSubview(effectView)
        self.contentView = container
        
        // 关键：对 NSThemeFrame（contentView 的 superview）也应用圆角 mask
        // NSThemeFrame 是 macOS 窗口主题框架，会绘制矩形边框
        if let themeFrame = self.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.backgroundColor = NSColor.clear.cgColor
            let frameMask = CAShapeLayer()
            frameMask.path = CGPath(roundedRect: themeFrame.bounds,
                                    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            themeFrame.layer?.mask = frameMask
        }
        
        toolbarView.updateState()
    }
    
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

// MARK: - 悬浮工具栏内容视图

class FloatingToolbarView: NSView {
    
    var onClose: (() -> Void)?
    var onUndo: (() -> Void)?
    var onClear: (() -> Void)?
    var onSaveScreenshot: (() -> Void)?
    var onSaveWhiteBackground: (() -> Void)?
    
    private let stackView = NSStackView()
    private var toolButtons: [ToolbarButton] = []
    
    // 工具按钮
    private var penButton: ToolbarButton!
    private var eraserButton: ToolbarButton!
    private var lassoButton: ToolbarButton!
    private var tabletOnlyButton: ToolbarButton!
    
    // 颜色按钮（纯自定义圆形）
    private var colorButton: RoundColorButton!
    
    // 粗细控件
    private var sizeLabel: SizeLabel!
    private var sizeUpButton: ToolbarButton!
    private var sizeDownButton: ToolbarButton!
    
    // 颜色气泡弹窗引用
    private weak var colorBubble: ColorBubblePanel?
    // 粗细输入面板引用
    private weak var sizeInputPanel: SizeInputPanel?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateState), name: BrushSettings.settingsChangedNotification, object: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        stackView.frame = bounds
        stackView.autoresizingMask = [.width, .height]
        addSubview(stackView)
        
        // 1. 画笔工具按钮（长按弹出预设菜单）
        penButton = ToolbarButton(symbolName: "pencil.tip", target: self, action: #selector(toolClicked(_:)))
        penButton.tag = 0
        addLongPressGesture(to: penButton)
        
        eraserButton = ToolbarButton(symbolName: "eraser", target: self, action: #selector(toolClicked(_:)))
        eraserButton.tag = 1
        addLongPressGesture(to: eraserButton)
        
        lassoButton = ToolbarButton(symbolName: "lasso", target: self, action: #selector(toolClicked(_:)))
        lassoButton.tag = 3
        
        tabletOnlyButton = ToolbarButton(symbolName: "applepencil", target: self, action: #selector(toolClicked(_:)))
        tabletOnlyButton.tag = 4
        
        stackView.addArrangedSubview(penButton)
        stackView.addArrangedSubview(eraserButton)
        stackView.addArrangedSubview(lassoButton)
        stackView.addArrangedSubview(tabletOnlyButton)
        
        toolButtons = [penButton, eraserButton, lassoButton, tabletOnlyButton]
        
        stackView.addArrangedSubview(createSeparator())
        
        // 2. 颜色选择（纯 Core Graphics 绘制的圆形按钮）
        colorButton = RoundColorButton(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        colorButton.color = BrushSettings.shared.color
        colorButton.onColorClicked = { [weak self] in
            self?.showColorBubble()
        }
        colorButton.translatesAutoresizingMaskIntoConstraints = false
        colorButton.widthAnchor.constraint(equalToConstant: 30).isActive = true
        colorButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        stackView.addArrangedSubview(colorButton)
        
        stackView.addArrangedSubview(createSeparator())
        
        // 3. 粗细控制
        sizeUpButton = ToolbarButton(symbolName: "plus.circle", size: 14, target: self, action: #selector(sizeUpClicked))
        stackView.addArrangedSubview(sizeUpButton)
        
        sizeLabel = SizeLabel(frame: NSRect(x: 0, y: 0, width: 36, height: 20))
        sizeLabel.sizeValue = BrushSettings.shared.size
        sizeLabel.onClicked = { [weak self] in self?.showSizeInput() }
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        sizeLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
        stackView.addArrangedSubview(sizeLabel)
        
        sizeDownButton = ToolbarButton(symbolName: "minus.circle", size: 14, target: self, action: #selector(sizeDownClicked))
        stackView.addArrangedSubview(sizeDownButton)
        
        stackView.addArrangedSubview(createSeparator())
        
        // 4. 操作按钮
        let undoButton = ToolbarButton(symbolName: "arrow.uturn.backward", size: 14, target: self, action: #selector(undoClicked))
        stackView.addArrangedSubview(undoButton)
        
        let clearButton = ToolbarButton(symbolName: "trash", size: 14, target: self, action: #selector(clearClicked))
        stackView.addArrangedSubview(clearButton)
        
        stackView.addArrangedSubview(createSeparator())
        
        // 5. 保存按钮
        let saveScreenshotButton = ToolbarButton(symbolName: "camera.viewfinder", size: 14, target: self, action: #selector(saveScreenshotClicked))
        stackView.addArrangedSubview(saveScreenshotButton)
        
        let saveWhiteBgButton = ToolbarButton(symbolName: "doc.on.doc", size: 14, target: self, action: #selector(saveWhiteBgClicked))
        stackView.addArrangedSubview(saveWhiteBgButton)
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
        
        // 6. 关闭按钮（退出书写模式）
        let closeButton = ToolbarButton(symbolName: "xmark.circle.fill", size: 20, target: self, action: #selector(closeClicked))
        closeButton.contentTintColor = .systemRed
        stackView.addArrangedSubview(closeButton)
    }
    
    private func createSeparator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 30),
            view.heightAnchor.constraint(equalToConstant: 1)
        ])
        return view
    }
    
    // MARK: - 长按手势（笔按钮弹出预设菜单）
    
    private func addLongPressGesture(to button: ToolbarButton) {
        let gesture = NSPressGestureRecognizer(target: self, action: #selector(buttonLongPressed(_:)))
        gesture.minimumPressDuration = 0.5
        button.addGestureRecognizer(gesture)
    }
    
    @objc private func buttonLongPressed(_ gesture: NSPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        if let button = gesture.view as? ToolbarButton {
            if button === penButton { showPresetMenu() }
            else if button === eraserButton { showEraserMenu() }
        }
    }
    
    private func showPresetMenu() {
        let menu = NSMenu()
        let settings = BrushSettings.shared
        
        let titleItem = NSMenuItem()
        titleItem.isEnabled = false
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        titleItem.attributedTitle = NSAttributedString(string: "  画笔预设", attributes: titleAttrs)
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        for preset in settings.allPresets {
            let item = NSMenuItem()
            let isSelected = settings.currentPreset == preset
            
            let namePrefix = isSelected ? "✓ " : "   "
            item.title = "\(namePrefix)\(preset.displayName) — \(Int(preset.size))pt"
            item.target = self
            item.action = #selector(presetSelected(_:))
            item.representedObject = preset
            
            if isSelected {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                ]
                item.attributedTitle = NSAttributedString(string: item.title, attributes: attrs)
            }
            
            menu.addItem(item)
        }
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: penButton.bounds.height), in: penButton)
    }
    
    @objc private func presetSelected(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? BrushPreset else { return }
        BrushSettings.shared.applyPreset(preset)
    }
    
    // MARK: - 颜色气泡弹窗
    
    private func showColorBubble() {
        // 已打开则关闭
        if let existing = colorBubble {
            existing.orderOut(nil)
            colorBubble = nil
            return
        }
        
        let bubble = ColorBubblePanel(relativeTo: colorButton)
        bubble.onColorSelected = { [weak self] color in
            let settings = BrushSettings.shared
            // 直接修改颜色属性，保留压感和其他设置
            settings.color = color
            if !settings.pressureSensitivity.isEnabled {
                settings.pressureSensitivity = .medium
            }
            settings.isEraser = false
            settings.isStrokeEraser = false
            settings.isLassoMode = false
            NotificationCenter.default.post(
                name: BrushSettings.settingsChangedNotification,
                object: settings
            )
            self?.colorBubble = nil
        }
        
        bubble.makeKeyAndOrderFront(nil)
        colorBubble = bubble
    }
    
    // MARK: - 粗细控制
    
    private var currentSizePresets: [CGFloat] {
        let settings = BrushSettings.shared
        if settings.isEraser || settings.isStrokeEraser {
            return [5, 10, 15, 20, 30, 50, 80]
        } else {
            return [1, 2, 3, 4, 5, 8, 10]
        }
    }
    
    @objc private func sizeUpClicked() {
        let settings = BrushSettings.shared
        let sizes = currentSizePresets
        let isAnyEraser = settings.isEraser || settings.isStrokeEraser
        let currentSize = isAnyEraser ? settings.eraserSize : settings.size
        if let nextSize = sizes.first(where: { $0 > currentSize + 0.1 }) {
            applySize(nextSize)
        }
    }
    
    @objc private func sizeDownClicked() {
        let settings = BrushSettings.shared
        let sizes = currentSizePresets
        let isAnyEraser = settings.isEraser || settings.isStrokeEraser
        let currentSize = isAnyEraser ? settings.eraserSize : settings.size
        if let prevSize = sizes.last(where: { $0 < currentSize - 0.1 }) {
            applySize(prevSize)
        }
    }
    
    /// 显示粗细输入面板
    private func showSizeInput() {
        if let existing = sizeInputPanel {
            existing.orderOut(nil)
            sizeInputPanel = nil
            return
        }
        
        let settings = BrushSettings.shared
        let isAnyEraser = settings.isEraser || settings.isStrokeEraser
        let currentSize = isAnyEraser ? settings.eraserSize : settings.size
        
        let panel = SizeInputPanel(
            currentSize: currentSize,
            isEraser: isAnyEraser,
            relativeTo: sizeLabel
        )
        panel.onSizeConfirmed = { [weak self] newSize in
            self?.applySize(newSize)
            self?.sizeInputPanel = nil
        }
        panel.activateTextField()
        sizeInputPanel = panel
    }
    
    private func applySize(_ size: CGFloat) {
        let settings = BrushSettings.shared
        if settings.isEraser || settings.isStrokeEraser {
            settings.setEraserSize(size)
        } else {
            settings.setCustomSize(size)
        }
    }
    
    // MARK: - 状态更新
    
    @objc func updateState() {
        let settings = BrushSettings.shared
        colorButton.color = settings.color
        sizeLabel.sizeValue = (settings.isEraser || settings.isStrokeEraser) ? settings.eraserSize : settings.size
        
        penButton.isSelectedTool = !settings.isEraser && !settings.isStrokeEraser && !settings.isLassoMode
        eraserButton.isSelectedTool = (settings.isEraser || settings.isStrokeEraser) && !settings.isLassoMode
        lassoButton.isSelectedTool = settings.isLassoMode
        tabletOnlyButton.isSelectedTool = settings.isTabletOnlyMode
    }
    
    // MARK: - 工具切换
    
    @objc private func toolClicked(_ sender: NSButton) {
        let settings = BrushSettings.shared
        switch sender.tag {
        case 0: settings.forcePenMode()
        case 1:
            // 点击橡皮擦：使用上次记忆的橡皮擦模式
            if settings.lastEraserWasStroke {
                settings.setStrokeEraserMode()
            } else {
                settings.setEraserMode()
            }
        case 3: settings.setLassoMode()
        case 4: settings.isTabletOnlyMode.toggle()
        default: break
        }
    }
    
    /// 橡皮擦长按菜单
    private func showEraserMenu() {
        let menu = NSMenu()
        let settings = BrushSettings.shared
        
        let titleItem = NSMenuItem()
        titleItem.isEnabled = false
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        titleItem.attributedTitle = NSAttributedString(string: "  橡皮擦模式", attributes: titleAttrs)
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // 普通橡皮擦
        let normalItem = NSMenuItem(title: "", action: #selector(eraserModeSelected(_:)), keyEquivalent: "")
        normalItem.target = self
        normalItem.tag = 0
        let normalPrefix = (settings.isEraser && !settings.isStrokeEraser) ? "✓ " : "   "
        normalItem.title = "\(normalPrefix)普通橡皮擦"
        if settings.isEraser && !settings.isStrokeEraser {
            normalItem.attributedTitle = NSAttributedString(string: normalItem.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ])
        }
        menu.addItem(normalItem)
        
        // 整笔擦除
        let strokeItem = NSMenuItem(title: "", action: #selector(eraserModeSelected(_:)), keyEquivalent: "")
        strokeItem.target = self
        strokeItem.tag = 1
        let strokePrefix = settings.isStrokeEraser ? "✓ " : "   "
        strokeItem.title = "\(strokePrefix)整笔擦除"
        if settings.isStrokeEraser {
            strokeItem.attributedTitle = NSAttributedString(string: strokeItem.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ])
        }
        menu.addItem(strokeItem)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: eraserButton.bounds.height), in: eraserButton)
    }
    
    @objc private func eraserModeSelected(_ sender: NSMenuItem) {
        if sender.tag == 0 {
            BrushSettings.shared.setEraserMode()
        } else {
            BrushSettings.shared.setStrokeEraserMode()
        }
    }
    
    @objc private func undoClicked() { onUndo?() }
    @objc private func clearClicked() { onClear?() }
    @objc private func saveScreenshotClicked() { onSaveScreenshot?() }
    @objc private func saveWhiteBgClicked() { onSaveWhiteBackground?() }
    @objc private func closeClicked() { onClose?() }
}
