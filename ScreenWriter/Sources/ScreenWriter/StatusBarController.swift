import Cocoa

// MARK: - 颜色选择菜单项视图

/// 颜色网格菜单项 - 在菜单中显示可选颜色
class ColorGridMenuItem: NSView {
    
    /// 所有可选颜色（存储为 RGB 值避免颜色空间转换问题）
    static let availableColors: [(String, NSColor)] = [
        ("黑色", NSColor(red: 0, green: 0, blue: 0, alpha: 1)),
        ("白色", NSColor(red: 1, green: 1, blue: 1, alpha: 1)),
        ("红色", NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)),
        ("橙色", NSColor(red: 1.0, green: 0.6, blue: 0.1, alpha: 1)),
        ("黄色", NSColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1)),
        ("绿色", NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)),
        ("蓝色", NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1)),
        ("紫色", NSColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1)),
        ("粉色", NSColor(red: 1.0, green: 0.4, blue: 0.6, alpha: 1)),
        ("灰色", NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
        ("青色", NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)),
        ("棕色", NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)),
    ]
    
    var onColorSelected: ((NSColor) -> Void)?
    
    init(onColorSelected: @escaping (NSColor) -> Void) {
        self.onColorSelected = onColorSelected
        // 2 行 x 6 列
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let cols = 6
        let cellSize: CGFloat = 26
        let padding: CGFloat = 4
        let margin: CGFloat = 16
        let currentColor = BrushSettings.shared.color
        
        for (index, (_, color)) in ColorGridMenuItem.availableColors.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = margin + CGFloat(col) * (cellSize + padding)
            let y = bounds.height - margin - CGFloat(row + 1) * (cellSize + padding) + padding
            let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
            
            // 绘制色块
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            color.setFill()
            path.fill()
            
            // 浅色需要边框
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            if brightness > 0.7 {
                NSColor(white: 0.75, alpha: 1).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            
            // 选中标记 - 简单比较 RGB
            if colorsMatch(color, currentColor) {
                let checkColor: NSColor = brightness > 0.5 ? .black : .white
                checkColor.setStroke()
                let checkPath = NSBezierPath()
                checkPath.lineWidth = 2.5
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.move(to: NSPoint(x: rect.minX + 6, y: rect.midY))
                checkPath.line(to: NSPoint(x: rect.midX - 1, y: rect.minY + 5))
                checkPath.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 5))
                checkPath.stroke()
            }
        }
    }
    
    /// 安全的颜色比较
    private func colorsMatch(_ c1: NSColor, _ c2: NSColor) -> Bool {
        // 尝试转换到 sRGB 比较
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        if let rgb1 = c1.usingColorSpace(.sRGB) {
            rgb1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        } else {
            return false
        }
        
        if let rgb2 = c2.usingColorSpace(.sRGB) {
            rgb2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        } else {
            return false
        }
        
        return abs(r1 - r2) < 0.05 && abs(g1 - g2) < 0.05 && abs(b1 - b2) < 0.05
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let cols = 6
        let cellSize: CGFloat = 26
        let padding: CGFloat = 4
        let margin: CGFloat = 16
        
        // 检查是否在色块上
        for (index, (_, color)) in ColorGridMenuItem.availableColors.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = margin + CGFloat(col) * (cellSize + padding)
            let y = bounds.height - margin - CGFloat(row + 1) * (cellSize + padding) + padding
            let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
            
            if rect.contains(location) {
                onColorSelected?(color)
                enclosingMenuItem?.menu?.cancelTracking()
                return
            }
        }
    }
}

// MARK: - 粗细控制菜单项视图

/// 粗细预设按钮菜单项（使用简单按钮代替 NSSlider 避免菜单中的兼容性问题）
class SizeControlMenuItem: NSView {
    
    var onSizeChanged: ((CGFloat) -> Void)?
    
    /// 画笔预设粗细值
    static let presetSizes: [CGFloat] = [1, 2, 3, 4, 5, 8, 10]
    /// 橡皮擦预设粗细值
    static let eraserPresetSizes: [CGFloat] = [10, 20, 30, 50, 80]
    
    /// 根据当前模式获取预设尺寸
    private var activeSizes: [CGFloat] {
        return BrushSettings.shared.isEraser ? SizeControlMenuItem.eraserPresetSizes : SizeControlMenuItem.presetSizes
    }
    
    init(currentSize: CGFloat, onSizeChanged: @escaping (CGFloat) -> Void) {
        self.onSizeChanged = onSizeChanged
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 52))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let margin: CGFloat = 16
        let currentSize = BrushSettings.shared.size
        let sizes = activeSizes
        let currentColor = BrushSettings.shared.color
        let isEraser = BrushSettings.shared.isEraser
        
        // 标题行
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let title = isEraser ? "  橡皮擦粗细" : "  粗细"
        title.draw(at: NSPoint(x: 4, y: bounds.height - 16), withAttributes: titleAttrs)
        
        // 当前值
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        "\(Int(currentSize))pt".draw(at: NSPoint(x: bounds.width - margin - 30, y: bounds.height - 16), withAttributes: valueAttrs)
        
        // 绘制粗细按钮（圆点表示）
        let startX: CGFloat = margin
        let y: CGFloat = 10
        let totalWidth = bounds.width - margin * 2
        let buttonWidth = totalWidth / CGFloat(sizes.count)
        
        for (index, size) in sizes.enumerated() {
            let x = startX + CGFloat(index) * buttonWidth
            let centerX = x + buttonWidth / 2
            
            // 圆点大小，最小 3pt 最大 18pt
            let dotSize: CGFloat
            if isEraser {
                dotSize = max(5, min(18, size * 0.25 + 2))
            } else {
                dotSize = max(3, min(18, size * 0.6 + 1))
            }
            
            let dotRect = NSRect(
                x: centerX - dotSize / 2,
                y: y + (20 - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            
            let isSelected = abs(currentSize - size) < 0.5
            
            if isSelected {
                // 选中圆圈背景
                let bgSize = max(dotSize + 6, 20)
                let bgRect = NSRect(
                    x: centerX - bgSize / 2,
                    y: y + (20 - bgSize) / 2,
                    width: bgSize,
                    height: bgSize
                )
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(ovalIn: bgRect).fill()
            }
            
            // 绘制圆点
            if isEraser {
                // 橡皮擦：空心圆
                NSColor.gray.withAlphaComponent(0.7).setStroke()
                let circlePath = NSBezierPath(ovalIn: dotRect)
                circlePath.lineWidth = 1.5
                circlePath.stroke()
            } else {
                currentColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let margin: CGFloat = 16
        let sizes = activeSizes
        let startX: CGFloat = margin
        let totalWidth = bounds.width - margin * 2
        let buttonWidth = totalWidth / CGFloat(sizes.count)
        
        for (index, size) in sizes.enumerated() {
            let x = startX + CGFloat(index) * buttonWidth
            let hitRect = NSRect(x: x, y: 0, width: buttonWidth, height: 35)
            
            if hitRect.contains(location) {
                onSizeChanged?(size)
                enclosingMenuItem?.menu?.cancelTracking()
                return
            }
        }
    }
}

// MARK: - 画笔预设菜单项视图

/// 画笔预设项（名称 + 颜色圆点 + 粗细预览线条）
class BrushPresetMenuItem: NSView {
    
    let preset: BrushPreset
    let isSelected: Bool
    var onSelect: (() -> Void)?
    private var isHighlighted = false
    
    init(preset: BrushPreset, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.preset = preset
        self.isSelected = isSelected
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let margin: CGFloat = 16
        
        // 高亮背景
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        
        let textColor = isHighlighted ? NSColor.white : NSColor.labelColor
        let secondaryColor = isHighlighted ? NSColor.white.withAlphaComponent(0.7) : NSColor.secondaryLabelColor
        
        // 选中标记
        if isSelected {
            let checkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: isHighlighted ? NSColor.white : NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
            ]
            "✓".draw(at: NSPoint(x: margin - 2, y: 5), withAttributes: checkAttrs)
        }
        
        // 颜色圆点
        if !preset.isEraser {
            let dotSize: CGFloat = 10
            let dotRect = NSRect(x: margin + 16, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
            preset.color.withAlphaComponent(preset.opacity).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
        
        // 名称
        let nameX: CGFloat = margin + 32
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
            .foregroundColor: textColor
        ]
        preset.displayName.draw(at: NSPoint(x: nameX, y: 6), withAttributes: nameAttrs)
        
        // 粗细值
        let sizeText = preset.isEraser ? "擦除" : "\(Int(preset.size))pt"
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        sizeText.draw(at: NSPoint(x: margin + 86, y: 7), withAttributes: sizeAttrs)
        
        // 预览线条
        let previewX: CGFloat = margin + 124
        let previewW: CGFloat = 100
        let centerY = bounds.height / 2
        
        if preset.isEraser {
            let dashPath = NSBezierPath()
            dashPath.move(to: NSPoint(x: previewX, y: centerY))
            dashPath.line(to: NSPoint(x: previewX + previewW, y: centerY))
            dashPath.lineWidth = 2
            let dashes: [CGFloat] = [5, 3]
            dashPath.setLineDash(dashes, count: 2, phase: 0)
            (isHighlighted ? NSColor.white.withAlphaComponent(0.5) : NSColor.gray.withAlphaComponent(0.5)).setStroke()
            dashPath.stroke()
        } else if preset.isHighlighter {
            // 荧光笔预览 - 半透明粗条带
            let lineColor = isHighlighted ? NSColor.white.withAlphaComponent(0.4) : preset.color.withAlphaComponent(preset.opacity)
            lineColor.setStroke()
            let hlPath = NSBezierPath()
            hlPath.lineWidth = min(12, preset.size * 0.6)
            hlPath.lineCapStyle = .square
            hlPath.move(to: NSPoint(x: previewX, y: centerY))
            hlPath.line(to: NSPoint(x: previewX + previewW, y: centerY))
            hlPath.stroke()
        } else {
            let displaySize = min(preset.size, 14)
            let lineColor = isHighlighted ? NSColor.white : preset.color.withAlphaComponent(preset.opacity)
            lineColor.setStroke()
            
            let steps = 12
            for i in 0..<steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = previewX + previewW * t
                let nextX = previewX + previewW * CGFloat(i + 1) / CGFloat(steps)
                let lineWidth = max(0.5, displaySize * t)
                
                let linePath = NSBezierPath()
                linePath.lineWidth = lineWidth
                linePath.lineCapStyle = .round
                linePath.move(to: NSPoint(x: x, y: centerY))
                linePath.line(to: NSPoint(x: nextX, y: centerY))
                linePath.stroke()
            }
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        onSelect?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
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
}

// MARK: - "上次使用" 菜单项视图

class LastUsedMenuItem: NSView {
    
    var onSelect: (() -> Void)?
    private var isHighlighted = false
    private var lastColor: NSColor
    private var lastSize: CGFloat
    
    init(lastColor: NSColor, lastSize: CGFloat, onSelect: @escaping () -> Void) {
        self.lastColor = lastColor
        self.lastSize = lastSize
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let margin: CGFloat = 16
        
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        
        let textColor = isHighlighted ? NSColor.white : NSColor.labelColor
        let secondaryColor = isHighlighted ? NSColor.white.withAlphaComponent(0.7) : NSColor.secondaryLabelColor
        
        // 图标
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: secondaryColor
        ]
        "↩".draw(at: NSPoint(x: margin, y: 6), withAttributes: iconAttrs)
        
        // 名称
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: textColor
        ]
        "上次使用".draw(at: NSPoint(x: margin + 18, y: 6), withAttributes: nameAttrs)
        
        // 颜色圆点
        let dotSize: CGFloat = 10
        let dotRect = NSRect(x: margin + 82, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
        lastColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        
        // 粗细值
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        "\(Int(lastSize))pt".draw(at: NSPoint(x: margin + 100, y: 7), withAttributes: sizeAttrs)
    }
    
    override func mouseUp(with event: NSEvent) {
        onSelect?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
    
    override func mouseEntered(with event: NSEvent) { isHighlighted = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false; needsDisplay = true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
}

// MARK: - 状态栏控制器

/// 状态栏控制器 - 管理菜单栏图标和下拉菜单
class StatusBarController: NSObject, NSMenuDelegate {
    
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var toggleMenuItem: NSMenuItem
    private var isDrawing = false
    
    // 回调
    var onToggleDrawing: () -> Void
    var onOpenSettings: () -> Void
    var onClearCanvas: () -> Void
    var onQuit: () -> Void
    
    init(onToggleDrawing: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onClearCanvas: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        
        self.onToggleDrawing = onToggleDrawing
        self.onOpenSettings = onOpenSettings
        self.onClearCanvas = onClearCanvas
        self.onQuit = onQuit
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        toggleMenuItem = NSMenuItem(title: "开始书写", action: nil, keyEquivalent: "")
        
        super.init()
        
        setupStatusButton()
        // rebuildMenu() 延迟到 menuWillOpen 时执行，避免初始化时 CA 渲染问题
        menu.delegate = self
    }
    
    /// 设置状态栏按钮
    private func setupStatusButton() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "ScreenWriter") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✏️"
            }
            button.toolTip = "ScreenWriter - 屏幕书写工具"
        }
        statusItem.menu = menu
    }
    
    /// 每次打开菜单前重建
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    /// 重建菜单
    private func rebuildMenu() {
        menu.removeAllItems()
        
        let settings = BrushSettings.shared
        
        // ===== 切换书写 =====
        let toggle = NSMenuItem(title: isDrawing ? "停止书写" : "开始书写", action: #selector(handleToggleDrawing), keyEquivalent: "")
        toggle.image = NSImage(systemSymbolName: isDrawing ? "stop.fill" : "pencil", accessibilityDescription: nil)
        toggle.target = self
        menu.addItem(toggle)
        
        // ===== 画笔预设标题 =====
        addSectionHeader("画笔预设")
        
        // 上次使用
        if let lastColor = settings.lastColor, let lastSize = settings.lastSize {
            let lastItem = NSMenuItem()
            lastItem.view = LastUsedMenuItem(lastColor: lastColor, lastSize: lastSize) {
                settings.restoreLastUsed()
            }
            menu.addItem(lastItem)
        }
        
        // 预设列表
        for preset in settings.allPresets {
            let item = NSMenuItem()
            let isSelected = settings.currentPreset == preset
            
            item.view = BrushPresetMenuItem(preset: preset, isSelected: isSelected) {
                settings.applyPreset(preset)
            }
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 颜色选择 =====
        addSectionHeader("颜色")
        
        let colorItem = NSMenuItem()
        colorItem.view = ColorGridMenuItem { color in
            settings.setCustomColor(color)
        }
        menu.addItem(colorItem)
        
        // 自定义颜色（使用普通菜单项）
        let customColorItem = NSMenuItem(title: "  自定义颜色...", action: #selector(handleCustomColor), keyEquivalent: "")
        customColorItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        customColorItem.target = self
        menu.addItem(customColorItem)
        
        // ===== 粗细控制 =====
        let sizeItem = NSMenuItem()
        sizeItem.view = SizeControlMenuItem(currentSize: settings.size) { size in
            if settings.isEraser {
                settings.setEraserSize(size)
            } else {
                settings.setCustomSize(size)
            }
        }
        menu.addItem(sizeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 橡皮擦区域 =====
        addSectionHeader("橡皮擦")
        
        // 普通橡皮擦
        let eraserSelected = settings.isEraser && !settings.isStrokeEraser
        let eraserItem = NSMenuItem(title: "  普通橡皮擦", action: #selector(handleNormalEraser), keyEquivalent: "")
        eraserItem.image = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil)
        eraserItem.state = eraserSelected ? .on : .off
        eraserItem.target = self
        menu.addItem(eraserItem)
        
        // 整笔擦除
        let strokeEraserSelected = settings.isStrokeEraser
        let strokeEraserItem = NSMenuItem(title: "  整笔擦除", action: #selector(handleStrokeEraser), keyEquivalent: "")
        strokeEraserItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        strokeEraserItem.state = strokeEraserSelected ? .on : .off
        strokeEraserItem.target = self
        menu.addItem(strokeEraserItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 索套工具 =====
        let lassoSelected = settings.isLassoMode
        let lassoItem = NSMenuItem(title: "  索套选择", action: #selector(handleLassoMode), keyEquivalent: "")
        lassoItem.image = NSImage(systemSymbolName: "lasso", accessibilityDescription: nil)
        lassoItem.state = lassoSelected ? .on : .off
        lassoItem.target = self
        menu.addItem(lassoItem)
        
        // ===== 数位板专属模式 =====
        let tabletOnlyItem = NSMenuItem(title: "  数位板专属模式", action: #selector(handleTabletOnlyMode), keyEquivalent: "")
        tabletOnlyItem.image = NSImage(systemSymbolName: "applepencil", accessibilityDescription: nil)
        tabletOnlyItem.state = settings.isTabletOnlyMode ? .on : .off
        tabletOnlyItem.target = self
        menu.addItem(tabletOnlyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 清除画布 =====
        let clearItem = NSMenuItem(title: "清除画布", action: #selector(handleClearCanvas), keyEquivalent: "")
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 设置 =====
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ===== 退出 =====
        let quitItem = NSMenuItem(title: "退出 ScreenWriter", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    /// 添加区域标题
    private func addSectionHeader(_ title: String) {
        let item = NSMenuItem()
        item.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        item.attributedTitle = NSAttributedString(string: "  \(title)", attributes: attrs)
        menu.addItem(item)
    }
    
    /// 更新状态
    func updateState(isDrawing: Bool) {
        self.isDrawing = isDrawing
        if let button = statusItem.button {
            let symbolName = isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip"
            let desc = isDrawing ? "ScreenWriter - 书写中" : "ScreenWriter"
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: desc) {
                image.isTemplate = true
                button.image = image
            }
        }
    }
    
    // MARK: - 菜单操作
    
    @objc private func handleToggleDrawing() { onToggleDrawing() }
    @objc private func handleClearCanvas() { onClearCanvas() }
    @objc private func handleOpenSettings() { onOpenSettings() }
    @objc private func handleQuit() { onQuit() }
    
    @objc private func handleCustomColor() {
        // 延迟打开颜色面板（菜单需要先关闭）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let colorPanel = NSColorPanel.shared
            colorPanel.color = BrushSettings.shared.color
            colorPanel.setTarget(self)
            colorPanel.setAction(#selector(self.colorPanelChanged(_:)))
            colorPanel.level = .floating
            colorPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        BrushSettings.shared.setCustomColor(sender.color)
    }
    
    @objc private func handleCustomSize() {
        // 延迟弹出输入对话框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let alert = NSAlert()
            alert.messageText = "输入画笔粗细"
            alert.informativeText = "请输入 1-50 之间的数值 (pt):"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
            input.stringValue = "\(Int(BrushSettings.shared.size))"
            input.alignment = .center
            alert.accessoryView = input
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                if let value = Double(input.stringValue) {
                    BrushSettings.shared.setCustomSize(CGFloat(value))
                }
            }
        }
    }
    
    // MARK: - 橡皮擦操作
    
    @objc private func handleNormalEraser() {
        BrushSettings.shared.setEraserMode()
    }
    
    @objc private func handleStrokeEraser() {
        BrushSettings.shared.setStrokeEraserMode()
    }
    
    @objc private func handleLassoMode() {
        BrushSettings.shared.setLassoMode()
    }
    
    @objc private func handleTabletOnlyMode() {
        BrushSettings.shared.isTabletOnlyMode.toggle()
    }

}
