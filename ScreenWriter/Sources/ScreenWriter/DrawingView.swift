import Cocoa

/// 笔划数据 - 存储一条完整的绘制路径
class StrokeData {
    /// 路径点集合 (包含位置和压力信息)
    var points: [(point: NSPoint, pressure: CGFloat)] = []
    /// 笔划颜色
    var color: NSColor
    /// 基础粗细
    var baseSize: CGFloat
    /// 不透明度
    var opacity: CGFloat
    /// 是否为橡皮擦
    var isEraser: Bool
    /// 是否为荧光笔
    var isHighlighter: Bool
    /// 压感灵敏度
    var pressureSensitivity: PressureSensitivity
    
    /// 缓存的贝塞尔路径
    var cachedPath: NSBezierPath?
    /// 缓存是否有效
    var cacheValid = false
    
    init(color: NSColor, baseSize: CGFloat, opacity: CGFloat, isEraser: Bool, isHighlighter: Bool = false, pressureSensitivity: PressureSensitivity) {
        self.color = color
        self.baseSize = baseSize
        self.opacity = opacity
        self.isEraser = isEraser
        self.isHighlighter = isHighlighter
        self.pressureSensitivity = pressureSensitivity
    }
    
    /// 添加点（带最小间距过滤，避免慢速绘制时点过密产生棱角）
    func addPoint(_ point: NSPoint, pressure: CGFloat) {
        let clampedPressure = max(0.01, min(1.0, pressure))
        
        // 最小间距过滤：距离上一个点不足 1.5 像素时跳过，但更新压力
        if let last = points.last {
            let dx = point.x - last.point.x
            let dy = point.y - last.point.y
            if dx * dx + dy * dy < 2.25 {  // 1.5² = 2.25
                // 距离太近，保留峰值压力（避免抬笔瞬间低压力覆盖）
                points[points.count - 1].pressure = max(points[points.count - 1].pressure, clampedPressure)
                return
            }
        }
        
        points.append((point: point, pressure: clampedPressure))
        cacheValid = false
    }
    
    /// 获取压感调整后的粗细（线性映射）
    func sizeForPressure(_ pressure: CGFloat) -> CGFloat {
        // 压感关闭时，返回固定粗细
        if pressureSensitivity == .off {
            return baseSize
        }
        let minSize = baseSize * 0.1
        let maxSize = baseSize * (1.0 + pressureSensitivity.multiplier)
        // 直接线性映射
        let p = max(0, min(1, pressure))
        return minSize + (maxSize - minSize) * p
    }
}

/// 绘图视图 - 核心绘图引擎，支持压感绘制
class DrawingView: NSView {
    
    /// 已完成的笔划
    private var strokes: [StrokeData] = []
    /// 当前正在绘制的笔划
    private var currentStroke: StrokeData?
    /// 撤销栈
    private var undoStack: [StrokeData] = []
    
    /// 是否正在绘制
    private var isDrawing = false
    
    /// 缓存已完成笔划的图层
    private var cachedImage: NSImage?
    private var cacheNeedsUpdate = true
    
    /// 数位板光标位置（数位板模式下自绘光标，因 ignoresMouseEvents=true 无法使用系统光标）
    private var tabletCursorPosition: NSPoint?
    /// 是否显示数位板光标
    private var showTabletCursor = false
    
    /// 光标（internal 供 OverlayPanel.sendEvent 使用）
    var brushCursor: NSCursor?
    
    /// 缓存当前光标背景是否为亮色（避免频繁重建光标）
    private var currentCursorOnLightBg: Bool = true
    /// 上次亮度采样时间戳（节流用，避免 CGWindowListCreateImage 阻塞主线程）
    private var lastBrightnessSampleTime: CFTimeInterval = 0
    
    // MARK: - 索套选择属性
    
    /// 索套路径点（视图坐标）
    private var lassoPath: [NSPoint] = []
    /// 是否正在绘制索套
    private var isLassoing = false
    /// 选中笔划的索引集合
    private var selectedStrokeIndices: Set<Int> = []
    /// 是否正在拖拽移动选中内容
    private var isDraggingSelection = false
    /// 拖拽起始坐标
    private var dragStartPoint: NSPoint = .zero
    /// 蚂蚁线动画相位
    private var marchingAntsPhase: CGFloat = 0
    /// 蚂蚁线动画定时器
    private var marchingAntsTimer: Timer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    /// 初始化视图
    private func setupView() {
        // 注册接受触控事件
        wantsRestingTouches = false
        
        // 监听画笔设置变更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(brushSettingsChanged),
            name: BrushSettings.settingsChangedNotification,
            object: nil
        )
        
        updateCursor()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    
    /// 拦截系统光标更新，防止闪烁回箭头
    override func cursorUpdate(with event: NSEvent) {
        if !BrushSettings.shared.isTabletOnlyMode {
            brushCursor?.set()
        }
        // 不调用 super，阻止系统重置光标
    }
    
    /// 鼠标移动时主动设置光标，并检测背景亮度切换光标颜色
    override func mouseMoved(with event: NSEvent) {
        if !BrushSettings.shared.isTabletOnlyMode {
            updateCursorColorIfNeeded(for: event)
            brushCursor?.set()
        }
    }
    
    /// 更新光标样式（描边颜色根据背景亮度自动切换）
    private func updateCursor(strokeColor: NSColor? = nil) {
        let settings = BrushSettings.shared
        
        // 索套模式使用十字准星光标
        if settings.isLassoMode {
            brushCursor = .crosshair
            window?.invalidateCursorRects(for: self)
            return
        }
        
        // 决定描边颜色：传入的颜色 > 根据缓存亮度状态决定
        let outlineColor = strokeColor ?? (currentCursorOnLightBg ? NSColor.black : NSColor.white)
        
        let isAnyEraser = settings.isEraser || settings.isStrokeEraser
        let cursorSize = max(4, min(64, isAnyEraser ? settings.eraserSize : settings.size))
        let padding: CGFloat = 8
        let cursorRect = NSRect(x: 0, y: 0, width: cursorSize + padding, height: cursorSize + padding)
        
        let cursorImage = NSImage(size: cursorRect.size)
        cursorImage.lockFocus()
        
        if isAnyEraser {
            // 橡皮擦光标 - 空心圆形
            let ovalRect = NSRect(x: padding / 2, y: padding / 2, width: cursorSize, height: cursorSize)
            let eraserPath = NSBezierPath(ovalIn: ovalRect)
            eraserPath.lineWidth = 1.5
            // 整笔擦除用虚线区分
            if settings.isStrokeEraser {
                let pattern: [CGFloat] = [4, 3]
                eraserPath.setLineDash(pattern, count: 2, phase: 0)
            }
            outlineColor.withAlphaComponent(0.9).setStroke()
            eraserPath.stroke()
        } else {
            // 画笔光标 - 圆点
            let dotRect = NSRect(
                x: (cursorRect.width - cursorSize) / 2,
                y: (cursorRect.height - cursorSize) / 2,
                width: cursorSize,
                height: cursorSize
            )
            let circlePath = NSBezierPath(ovalIn: dotRect)
            circlePath.lineWidth = 1.5
            
            // 自适应描边
            outlineColor.withAlphaComponent(0.9).setStroke()
            circlePath.stroke()
            
            // 内部填充
            settings.color.withAlphaComponent(0.6).setFill()
            circlePath.fill()
        }
        
        cursorImage.unlockFocus()
        
        brushCursor = NSCursor(
            image: cursorImage,
            hotSpot: NSPoint(x: cursorRect.width / 2, y: cursorRect.height / 2)
        )
    }
    
    // MARK: - 屏幕亮度采样（光标自适应颜色）
    
    /// 采样屏幕指定位置的亮度（0.0 = 全黑，1.0 = 全白）
    /// 使用 CGWindowListCreateImage 截取 11×11 像素区域并取平均亮度，避免文字等细节导致闪烁
    private func screenBrightnessAt(screenPoint: NSPoint) -> CGFloat {
        // 主屏幕高度（用于坐标系转换：NSPoint 是左下角原点，CGRect 是左上角原点）
        guard let mainScreen = NSScreen.main else { return 0.5 }
        let screenHeight = mainScreen.frame.height
        let cgPoint = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)
        
        // 截取 11×11 像素区域（以光标位置为中心），排除本应用窗口
        let sampleSize: CGFloat = 11
        let captureRect = CGRect(
            x: cgPoint.x - sampleSize / 2,
            y: cgPoint.y - sampleSize / 2,
            width: sampleSize,
            height: sampleSize
        )
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            CGWindowID(window?.windowNumber ?? 0),
            .bestResolution
        ) else {
            return 0.5  // 采样失败，返回中间值
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        guard totalPixels > 0 else { return 0.5 }
        
        // 从 CGImage 读取像素数据
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return 0.5
        }
        
        let ptr = CFDataGetBytePtr(data)!
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let dataLength = CFDataGetLength(data)
        let isLittleEndian = cgImage.bitmapInfo.contains(.byteOrder32Little)
        
        // 遍历所有像素，累加亮度
        var totalBrightness: CGFloat = 0
        for i in 0..<totalPixels {
            let offset = i * bytesPerPixel
            guard offset + 3 < dataLength else { break }
            
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            
            if isLittleEndian {
                // BGRA 格式（macOS 常见）
                b = CGFloat(ptr[offset]) / 255.0
                g = CGFloat(ptr[offset + 1]) / 255.0
                r = CGFloat(ptr[offset + 2]) / 255.0
            } else {
                // RGBA 格式
                r = CGFloat(ptr[offset]) / 255.0
                g = CGFloat(ptr[offset + 1]) / 255.0
                b = CGFloat(ptr[offset + 2]) / 255.0
            }
            
            // 感知亮度公式（ITU-R BT.601）
            totalBrightness += 0.299 * r + 0.587 * g + 0.114 * b
        }
        
        return totalBrightness / CGFloat(totalPixels)
    }
    
    /// 根据鼠标事件位置检测背景亮度，必要时更新光标颜色（200ms 节流）
    private func updateCursorColorIfNeeded(for event: NSEvent) {
        // 节流：距离上次采样不足 200ms 则跳过
        let now = CACurrentMediaTime()
        guard now - lastBrightnessSampleTime >= 0.2 else { return }
        lastBrightnessSampleTime = now
        
        guard let window = self.window else { return }
        let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        let brightness = screenBrightnessAt(screenPoint: screenPoint)
        let isLightBg = brightness > 0.5
        
        // 背景亮度状态变化时才重建光标
        if isLightBg != currentCursorOnLightBg {
            currentCursorOnLightBg = isLightBg
            updateCursor()
            window.invalidateCursorRects(for: self)
        }
    }
    
    override func resetCursorRects() {
        if let cursor = brushCursor {
            addCursorRect(bounds, cursor: cursor)
        }
    }
    
    @objc private func brushSettingsChanged() {
        updateCursor()
        window?.invalidateCursorRects(for: self)
    }
    
    // MARK: - 绘制
    
    override func draw(_ dirtyRect: NSRect) {
        // 清除背景（完全透明）
        NSColor.clear.set()
        dirtyRect.fill()
        
        // 绘制缓存的已完成笔划
        if cacheNeedsUpdate {
            updateCache()
        }
        cachedImage?.draw(in: bounds)
        
        // 绘制当前正在绘制的笔划
        if let stroke = currentStroke {
            drawStroke(stroke)
        }
        
        // 绘制选中笔划的高亮边框（在所有笔划之后）
        if !selectedStrokeIndices.isEmpty {
            for index in selectedStrokeIndices {
                guard index < strokes.count else { continue }
                drawSelectionHighlight(for: strokes[index])
            }
        }
        
        // 绘制索套路径
        if !lassoPath.isEmpty {
            drawLassoPath()
        }
        
        // 绘制数位板自定义光标（仅数位板专属模式）
        if showTabletCursor, let cursorPos = tabletCursorPosition {
            drawTabletCursor(at: cursorPos)
        }
    }
    
    /// 更新缓存
    private func updateCache() {
        cachedImage = NSImage(size: bounds.size)
        cachedImage?.lockFocus()
        
        for stroke in strokes {
            drawStroke(stroke)
        }
        
        cachedImage?.unlockFocus()
        cacheNeedsUpdate = false
    }
    
    /// 绘制单条笔划
    private func drawStroke(_ stroke: StrokeData) {
        // 荧光笔使用半透明矩形绘制
        if stroke.isHighlighter {
            drawHighlighterStroke(stroke)
            return
        }
        
        // 判断是否为"点"：点数少于4且总位移极小时，按圆点绘制
        let isPoint: Bool
        if stroke.points.count < 2 {
            isPoint = true
        } else if stroke.points.count < 4 {
            // 检查总位移距离，排除极短笔划
            let first = stroke.points.first!.point
            let last = stroke.points.last!.point
            let totalDist = sqrt(pow(last.x - first.x, 2) + pow(last.y - first.y, 2))
            isPoint = totalDist < 2.0
        } else {
            isPoint = false
        }
        
        if isPoint {
            // 绘制为圆点
            if let point = stroke.points.first {
                let size = stroke.sizeForPressure(point.pressure)
                let rect = NSRect(
                    x: point.point.x - size / 2,
                    y: point.point.y - size / 2,
                    width: size,
                    height: size
                )
                
                if stroke.isEraser {
                    NSGraphicsContext.current?.compositingOperation = .clear
                    NSColor.clear.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                } else {
                    stroke.color.withAlphaComponent(stroke.opacity).setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
            return
        }
        
        guard stroke.points.count >= 2 else { return }
        
        if stroke.isEraser {
            NSGraphicsContext.current?.compositingOperation = .clear
            drawVariableWidthPath(stroke)
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            drawVariableWidthPath(stroke)
        }
    }
    
    /// 绘制荧光笔笔划（半透明粗线条方块状）
    private func drawHighlighterStroke(_ stroke: StrokeData) {
        guard stroke.points.count >= 1 else { return }
        
        let height = stroke.baseSize
        stroke.color.withAlphaComponent(stroke.opacity).setStroke()
        
        if stroke.points.count == 1 {
            // 单点
            let point = stroke.points[0].point
            let rect = NSRect(
                x: point.x - height / 4,
                y: point.y - height / 2,
                width: height / 2,
                height: height
            )
            stroke.color.withAlphaComponent(stroke.opacity).setFill()
            NSBezierPath(rect: rect).fill()
            return
        }
        
        // 使用单一路径 + 粗线条 + square 线帽实现平滑荧光笔
        let path = NSBezierPath()
        path.lineWidth = height
        path.lineCapStyle = .square    // 方形端头 = 荧光笔效果
        path.lineJoinStyle = .round    // 圆角连接避免割断
        
        path.move(to: stroke.points[0].point)
        
        // 使用二次曲线平滑插值
        if stroke.points.count == 2 {
            path.line(to: stroke.points[1].point)
        } else {
            for i in 1..<stroke.points.count {
                let prev = stroke.points[i - 1].point
                let curr = stroke.points[i].point
                let midPoint = NSPoint(
                    x: (prev.x + curr.x) / 2,
                    y: (prev.y + curr.y) / 2
                )
                
                if i == 1 {
                    path.line(to: midPoint)
                } else {
                    path.curve(to: midPoint, controlPoint1: prev, controlPoint2: prev)
                }
                
                // 最后一个点直接连接
                if i == stroke.points.count - 1 {
                    path.line(to: curr)
                }
            }
        }
        
        path.stroke()
    }
    

    
    /// 绘制可变宽度路径（支持压感） - 圆形印章 + 梯形连接，分段独立绘制
    private func drawVariableWidthPath(_ stroke: StrokeData) {
        let points = stroke.points
        guard points.count >= 2 else { return }
        
        // 设置填充颜色
        if stroke.isEraser {
            NSColor.white.setFill()
        } else {
            stroke.color.setFill()
        }
        
        // 计算每个点的半径
        let radii: [CGFloat] = points.map { stroke.sizeForPressure($0.pressure) / 2.0 }
        
        // 在每个点画圆形（作为端帽和连接处的圆角）
        for i in 0..<points.count {
            let r = radii[i]
            let center = points[i].point
            let circle = NSBezierPath(ovalIn: NSRect(
                x: center.x - r, y: center.y - r,
                width: r * 2, height: r * 2
            ))
            circle.fill()
        }
        
        // 在相邻点之间画梯形连接
        for i in 0..<(points.count - 1) {
            let p0 = points[i].point
            let p1 = points[i + 1].point
            let r0 = radii[i]
            let r1 = radii[i + 1]
            
            // 计算连接方向的法线
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0.001 else { continue }
            
            let nx = -dy / len
            let ny = dx / len
            
            // 四个角构成梯形
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p0.x + nx * r0, y: p0.y + ny * r0))
            path.line(to: NSPoint(x: p1.x + nx * r1, y: p1.y + ny * r1))
            path.line(to: NSPoint(x: p1.x - nx * r1, y: p1.y - ny * r1))
            path.line(to: NSPoint(x: p0.x - nx * r0, y: p0.y - ny * r0))
            path.close()
            path.fill()
        }
    }
    
    // MARK: - 索套绘制与辅助方法
    
    /// 绘制索套路径（虚线）
    private func drawLassoPath() {
        guard lassoPath.count >= 2 else { return }
        
        let path = NSBezierPath()
        path.move(to: lassoPath[0])
        for i in 1..<lassoPath.count {
            path.line(to: lassoPath[i])
        }
        if !isLassoing { path.close() }
        
        path.lineWidth = 1.5
        NSColor.white.setStroke()
        path.stroke()
        
        let dashes: [CGFloat] = [6, 4]
        path.setLineDash(dashes, count: 2, phase: marchingAntsPhase)
        NSColor.systemBlue.setStroke()
        path.stroke()
    }
    
    /// 绘制选中笔划的高亮边框
    private func drawSelectionHighlight(for stroke: StrokeData) {
        guard !stroke.points.isEmpty else { return }
        
        var minX: CGFloat = .infinity, minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity, maxY: CGFloat = -.infinity
        
        for p in stroke.points {
            let r = stroke.sizeForPressure(p.pressure) / 2
            minX = min(minX, p.point.x - r)
            minY = min(minY, p.point.y - r)
            maxX = max(maxX, p.point.x + r)
            maxY = max(maxY, p.point.y + r)
        }
        
        let padding: CGFloat = 3.0
        let rect = NSRect(x: minX - padding, y: minY - padding,
                         width: maxX - minX + padding * 2,
                         height: maxY - minY + padding * 2)
        
        let borderPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        borderPath.lineWidth = 1.0
        let dashes: [CGFloat] = [4, 4]
        borderPath.setLineDash(dashes, count: 2, phase: marchingAntsPhase)
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        borderPath.stroke()
    }
    
    /// 启动蚂蚁线动画
    private func startMarchingAnts() {
        guard marchingAntsTimer == nil else { return }
        marchingAntsTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.marchingAntsPhase += 1
            if self.marchingAntsPhase > 100 { self.marchingAntsPhase = 0 }
            // 仅刷新选区包围盒区域，避免全视图 20fps 刷新
            self.setNeedsDisplay(self.selectionBoundsRect())
        }
    }
    
    /// 停止蚂蚁线动画
    private func stopMarchingAnts() {
        marchingAntsTimer?.invalidate()
        marchingAntsTimer = nil
        marchingAntsPhase = 0
    }
    
    /// 射线法判断点是否在索套路径内
    private func isPointInsideLasso(_ point: NSPoint) -> Bool {
        guard lassoPath.count >= 3 else { return false }
        var inside = false
        let n = lassoPath.count
        var j = n - 1
        for i in 0..<n {
            let pi = lassoPath[i], pj = lassoPath[j]
            if ((pi.y > point.y) != (pj.y > point.y)) &&
               (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        return inside
    }
    
    /// 计算笔划重心
    private func strokeCentroid(_ stroke: StrokeData) -> NSPoint {
        guard !stroke.points.isEmpty else { return .zero }
        var sx: CGFloat = 0, sy: CGFloat = 0
        for p in stroke.points { sx += p.point.x; sy += p.point.y }
        let c = CGFloat(stroke.points.count)
        return NSPoint(x: sx / c, y: sy / c)
    }
    
    /// 检测索套内的笔划
    private func detectSelectedStrokes() {
        selectedStrokeIndices.removeAll()
        guard lassoPath.count >= 3 else { return }
        for (index, stroke) in strokes.enumerated() {
            if isPointInsideLasso(strokeCentroid(stroke)) {
                selectedStrokeIndices.insert(index)
            }
        }
    }
    
    /// 判断点是否在选中笔划包围盒内
    private func isPointInSelectionBounds(_ pt: NSPoint) -> Bool {
        let rect = selectionBoundsRect()
        return rect != .zero && rect.contains(pt)
    }
    
    /// 计算选中笔划的包围盒（含 padding）
    private func selectionBoundsRect() -> NSRect {
        guard !selectedStrokeIndices.isEmpty else { return .zero }
        var minX: CGFloat = .infinity, minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity, maxY: CGFloat = -.infinity
        for index in selectedStrokeIndices {
            guard index < strokes.count else { continue }
            for p in strokes[index].points {
                let r = strokes[index].sizeForPressure(p.pressure) / 2
                minX = min(minX, p.point.x - r)
                minY = min(minY, p.point.y - r)
                maxX = max(maxX, p.point.x + r)
                maxY = max(maxY, p.point.y + r)
            }
        }
        // 包含索套路径的范围
        for pt in lassoPath {
            minX = min(minX, pt.x)
            minY = min(minY, pt.y)
            maxX = max(maxX, pt.x)
            maxY = max(maxY, pt.y)
        }
        let padding: CGFloat = 15.0
        return NSRect(x: minX - padding, y: minY - padding,
                     width: maxX - minX + padding * 2,
                     height: maxY - minY + padding * 2)
    }
    
    /// 清除选区
    func clearSelection() {
        selectedStrokeIndices.removeAll()
        lassoPath.removeAll()
        isLassoing = false
        isDraggingSelection = false
        stopMarchingAnts()
        needsDisplay = true
    }
    
    /// 删除选中笔划
    private func deleteSelectedStrokes() {
        guard !selectedStrokeIndices.isEmpty else { return }
        let sorted = selectedStrokeIndices.sorted(by: >)
        for index in sorted {
            guard index < strokes.count else { continue }
            let stroke = strokes.remove(at: index)
            undoStack.append(stroke)
        }
        clearSelection()
        cacheNeedsUpdate = true
        needsDisplay = true
    }
    
    // MARK: - 点擦除（真实分割笔划）
    
    /// 计算点到线段的最短距离
    private func distanceFromPoint(_ p: NSPoint, toSegmentFrom a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        
        // 线段退化为点
        if lenSq < 0.001 {
            let px = p.x - a.x
            let py = p.y - a.y
            return sqrt(px * px + py * py)
        }
        
        // 投影参数 t，限制在 [0, 1] 范围内
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        
        // 最近点
        let nearestX = a.x + t * dx
        let nearestY = a.y + t * dy
        let distX = p.x - nearestX
        let distY = p.y - nearestY
        return sqrt(distX * distX + distY * distY)
    }
    
    /// 在指定位置进行点擦除，将被擦除区域的笔划分割成独立的段
    /// 使用线段碰撞检测，能准确擦除快速绘制的笔画
    private func erasePointAt(_ point: NSPoint, radius: CGFloat) {
        var result: [StrokeData] = []
        var modified = false
        
        for stroke in strokes {
            // 保留旧的橡皮擦笔划不处理（兼容）
            if stroke.isEraser {
                result.append(stroke)
                continue
            }
            
            let pts = stroke.points
            if pts.isEmpty {
                result.append(stroke)
                continue
            }
            
            // 标记每个线段（点i到点i+1）是否被擦除
            // 同时标记独立的点是否被擦除
            var erasedSegments = [Bool](repeating: false, count: max(pts.count - 1, 0))
            var singlePointErased = false
            
            // 特殊情况：只有一个点
            if pts.count == 1 {
                let sp = pts[0]
                let dx = sp.point.x - point.x
                let dy = sp.point.y - point.y
                let dist = sqrt(dx * dx + dy * dy)
                let strokeRadius = stroke.sizeForPressure(sp.pressure) / 2
                singlePointErased = dist <= radius + strokeRadius
                
                if singlePointErased {
                    modified = true
                } else {
                    result.append(stroke)
                }
                continue
            }
            
            // 检查每个线段是否与橡皮擦圆相交
            for i in 0..<(pts.count - 1) {
                let a = pts[i]
                let b = pts[i + 1]
                let segDist = distanceFromPoint(point, toSegmentFrom: a.point, to: b.point)
                // 线段的平均笔画半径
                let avgStrokeRadius = (stroke.sizeForPressure(a.pressure) + stroke.sizeForPressure(b.pressure)) / 4
                if segDist <= radius + avgStrokeRadius {
                    erasedSegments[i] = true
                }
            }
            
            // 如果没有线段被擦除，保留原笔划
            if !erasedSegments.contains(true) {
                result.append(stroke)
                continue
            }
            
            modified = true
            
            // 根据被擦除的线段分割笔划
            // 一个点属于保留段，当且仅当它至少连接了一个未被擦除的线段
            var currentSegment: [(point: NSPoint, pressure: CGFloat)] = []
            
            for i in 0..<pts.count {
                // 检查该点是否属于某个未被擦除的线段
                let leftSegOK = i > 0 && !erasedSegments[i - 1]
                let rightSegOK = i < pts.count - 1 && !erasedSegments[i]
                
                if leftSegOK || rightSegOK {
                    currentSegment.append(pts[i])
                } else {
                    // 该点两侧的线段都被擦除了，断开
                    if !currentSegment.isEmpty {
                        let newStroke = StrokeData(
                            color: stroke.color,
                            baseSize: stroke.baseSize,
                            opacity: stroke.opacity,
                            isEraser: false,
                            isHighlighter: stroke.isHighlighter,
                            pressureSensitivity: stroke.pressureSensitivity
                        )
                        newStroke.points = currentSegment
                        result.append(newStroke)
                        currentSegment = []
                    }
                }
            }
            
            if !currentSegment.isEmpty {
                let newStroke = StrokeData(
                    color: stroke.color,
                    baseSize: stroke.baseSize,
                    opacity: stroke.opacity,
                    isEraser: false,
                    isHighlighter: stroke.isHighlighter,
                    pressureSensitivity: stroke.pressureSensitivity
                )
                newStroke.points = currentSegment
                result.append(newStroke)
            }
        }
        
        if modified {
            strokes = result
            cacheNeedsUpdate = true
            needsDisplay = true
        }
    }
    
    // MARK: - 鼠标/数位板事件处理
    
    override func mouseDown(with event: NSEvent) {
        // 非数位板模式下检测背景亮度并设置光标
        if !BrushSettings.shared.isTabletOnlyMode {
            updateCursorColorIfNeeded(for: event)
            brushCursor?.set()
        }
        // 数位板专属模式下，忽略非数位板输入
        if BrushSettings.shared.isTabletOnlyMode && event.subtype != .tabletPoint {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let pressure: CGFloat = event.subtype == .tabletPoint ? CGFloat(event.pressure) : 0.5
        handleDown(at: location, pressure: pressure)
    }
    
    override func mouseDragged(with event: NSEvent) {
        // 非数位板模式下主动设置光标
        if !BrushSettings.shared.isTabletOnlyMode {
            brushCursor?.set()
        }
        // 数位板专属模式下，忽略非数位板输入
        if BrushSettings.shared.isTabletOnlyMode && event.subtype != .tabletPoint {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let pressure: CGFloat = event.subtype == .tabletPoint ? CGFloat(event.pressure) : 0.5
        handleDragged(at: location, pressure: pressure)
    }

    
    override func mouseUp(with event: NSEvent) {
        // 非数位板模式下主动设置光标
        if !BrushSettings.shared.isTabletOnlyMode {
            brushCursor?.set()
        }
        // 数位板专属模式下，忽略非数位板输入
        if BrushSettings.shared.isTabletOnlyMode && event.subtype != .tabletPoint {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let pressure: CGFloat = event.subtype == .tabletPoint ? CGFloat(event.pressure) : 0.5
        handleUp(at: location, pressure: pressure)
    }
    
    // MARK: - 外部调用入口（CGEvent tap 路径，接受屏幕坐标）
    
    /// CGEvent tap 拦截的数位板按下事件
    func externalDown(screenPoint: NSPoint, pressure: CGFloat) {
        guard let window = self.window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let location = convert(windowPoint, from: nil)
        handleDown(at: location, pressure: pressure)
    }
    
    /// CGEvent tap 拦截的数位板拖拽事件
    func externalDragged(screenPoint: NSPoint, pressure: CGFloat) {
        guard let window = self.window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let location = convert(windowPoint, from: nil)
        handleDragged(at: location, pressure: pressure)
    }
    
    /// CGEvent tap 拦截的数位板抬起事件
    func externalUp(screenPoint: NSPoint, pressure: CGFloat) {
        guard let window = self.window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let location = convert(windowPoint, from: nil)
        handleUp(at: location, pressure: pressure)
    }
    
    // MARK: - 数位板自绘光标
    
    /// 更新数位板光标位置（笔悬停时调用）
    func updateTabletCursor(screenPoint: NSPoint) {
        guard let window = self.window else { return }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let location = convert(windowPoint, from: nil)
        
        let oldPos = tabletCursorPosition
        tabletCursorPosition = location
        showTabletCursor = true
        
        // 局部刷新：刷新旧位置和新位置周围区域
        let refreshSize: CGFloat = 80
        if let old = oldPos {
            setNeedsDisplay(NSRect(x: old.x - refreshSize/2, y: old.y - refreshSize/2, width: refreshSize, height: refreshSize))
        }
        setNeedsDisplay(NSRect(x: location.x - refreshSize/2, y: location.y - refreshSize/2, width: refreshSize, height: refreshSize))
    }
    
    /// 清除数位板光标（笔离开时调用）
    func clearTabletCursor() {
        if let pos = tabletCursorPosition {
            let refreshSize: CGFloat = 80
            setNeedsDisplay(NSRect(x: pos.x - refreshSize/2, y: pos.y - refreshSize/2, width: refreshSize, height: refreshSize))
        }
        tabletCursorPosition = nil
        showTabletCursor = false
    }
    
    /// 绘制数位板光标（根据背景亮度自动切换描边颜色）
    private func drawTabletCursor(at point: NSPoint) {
        let settings = BrushSettings.shared
        let isAnyEraser = settings.isEraser || settings.isStrokeEraser
        let cursorSize = max(4, min(64, isAnyEraser ? settings.eraserSize : settings.size))
        
        // 采样光标位置的屏幕亮度，决定描边颜色
        var outlineColor = NSColor.black
        if let window = self.window {
            let windowPoint = convert(point, to: nil)
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            let brightness = screenBrightnessAt(screenPoint: screenPoint)
            outlineColor = brightness > 0.5 ? NSColor.black : NSColor.white
        }
        
        let circleRect = NSRect(
            x: point.x - cursorSize / 2,
            y: point.y - cursorSize / 2,
            width: cursorSize,
            height: cursorSize
        )
        let path = NSBezierPath(ovalIn: circleRect)
        path.lineWidth = 1.5
        
        if isAnyEraser {
            // 整笔擦除用虚线区分
            if settings.isStrokeEraser {
                let pattern: [CGFloat] = [4, 3]
                path.setLineDash(pattern, count: 2, phase: 0)
            }
            outlineColor.withAlphaComponent(0.9).setStroke()
            path.stroke()
        } else {
            // 自适应描边
            outlineColor.withAlphaComponent(0.9).setStroke()
            path.stroke()
            // 内部填充
            settings.color.withAlphaComponent(0.6).setFill()
            path.fill()
        }
    }
    
    // MARK: - 核心绘图逻辑（NSEvent 和 CGEvent tap 共用）
    
    /// 按下处理
    private func handleDown(at location: NSPoint, pressure: CGFloat) {
        let settings = BrushSettings.shared
        
        // ===== 索套模式 =====
        if settings.isLassoMode {
            if !selectedStrokeIndices.isEmpty && isPointInSelectionBounds(location) {
                isDraggingSelection = true
                dragStartPoint = location
                return
            }
            clearSelection()
            isLassoing = true
            lassoPath = [location]
            startMarchingAnts()
            needsDisplay = true
            return
        }
        
        // 切换到其他模式时清除选区
        if !selectedStrokeIndices.isEmpty { clearSelection() }
        
        // 橡皮擦模式
        if settings.isEraser {
            isDrawing = true
            erasePointAt(location, radius: settings.eraserSize / 2)
            return
        }
        
        // 整笔擦除模式
        if settings.isStrokeEraser {
            isDrawing = true
            undoStack.removeAll()
            eraseStrokeAt(location)
            return
        }
        
        isDrawing = true
        undoStack.removeAll()
        
        currentStroke = StrokeData(
            color: settings.color,
            baseSize: settings.size,
            opacity: settings.opacity,
            isEraser: false,
            isHighlighter: settings.isHighlighter,
            pressureSensitivity: settings.pressureSensitivity
        )
        
        currentStroke?.addPoint(location, pressure: pressure)
        needsDisplay = true
    }
    
    /// 拖拽处理
    private func handleDragged(at location: NSPoint, pressure: CGFloat) {
        // 索套绘制
        if isLassoing {
            lassoPath.append(location)
            needsDisplay = true
            return
        }
        
        // 拖拽移动选中笔划
        if isDraggingSelection {
            let dx = location.x - dragStartPoint.x
            let dy = location.y - dragStartPoint.y
            for index in selectedStrokeIndices {
                guard index < strokes.count else { continue }
                for i in 0..<strokes[index].points.count {
                    strokes[index].points[i].point.x += dx
                    strokes[index].points[i].point.y += dy
                }
            }
            for i in 0..<lassoPath.count {
                lassoPath[i].x += dx
                lassoPath[i].y += dy
            }
            dragStartPoint = location
            cacheNeedsUpdate = true
            needsDisplay = true
            return
        }
        
        guard isDrawing else { return }
        let settings = BrushSettings.shared
        
        // 橡皮擦模式：继续擦除
        if settings.isEraser {
            erasePointAt(location, radius: settings.eraserSize / 2)
            return
        }
        
        if settings.isStrokeEraser {
            eraseStrokeAt(location)
            return
        }
        
        guard let stroke = currentStroke else { return }
        
        stroke.addPoint(location, pressure: pressure)
        
        let lastPoints = stroke.points.suffix(3)
        if let first = lastPoints.first, let last = lastPoints.last {
            let maxSize = stroke.baseSize * 3
            let minX = min(first.point.x, last.point.x) - maxSize
            let minY = min(first.point.y, last.point.y) - maxSize
            let maxX = max(first.point.x, last.point.x) + maxSize
            let maxY = max(first.point.y, last.point.y) + maxSize
            setNeedsDisplay(NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
    }
    
    /// 抬起处理
    private func handleUp(at location: NSPoint, pressure: CGFloat) {
        // 索套闭合
        if isLassoing {
            isLassoing = false
            if lassoPath.count >= 3 {
                detectSelectedStrokes()
                if selectedStrokeIndices.isEmpty { clearSelection() }
            } else {
                clearSelection()
            }
            needsDisplay = true
            return
        }
        
        // 结束拖拽
        if isDraggingSelection {
            isDraggingSelection = false
            return
        }
        
        guard isDrawing else { return }
        isDrawing = false
        
        // 橡皮擦模式无需添加笔划
        if BrushSettings.shared.isEraser || BrushSettings.shared.isStrokeEraser { return }
        
        guard let stroke = currentStroke else { return }
        
        strokes.append(stroke)
        currentStroke = nil
        cacheNeedsUpdate = true
        needsDisplay = true
    }
    
    // MARK: - 数位板事件
    
    override func tabletPoint(with event: NSEvent) {
        if isDrawing {
            mouseDragged(with: event)
        }
    }
    
    override func pressureChange(with event: NSEvent) {
        if isDrawing && !BrushSettings.shared.isStrokeEraser && event.subtype == .tabletPoint {
            mouseDragged(with: event)
        }
    }
    
    // MARK: - 整笔擦除
    
    /// 检测并擦除触碰到的整条笔划
    private func eraseStrokeAt(_ point: NSPoint) {
        let hitRadius: CGFloat = 10.0  // 触碰检测半径
        var didErase = false
        
        // 从后向前检测（最新的笔划优先擦除）
        for i in stride(from: strokes.count - 1, through: 0, by: -1) {
            let stroke = strokes[i]
            if stroke.isEraser { continue }
            
            if isPointNearStroke(point, stroke: stroke, radius: hitRadius) {
                let removed = strokes.remove(at: i)
                undoStack.append(removed)  // 保存到撤销栈，使擦除可撤销
                didErase = true
                break  // 每次只擦除一条
            }
        }
        
        if didErase {
            cacheNeedsUpdate = true
            needsDisplay = true
        }
    }
    
    /// 判断点是否距离笔划足够近
    private func isPointNearStroke(_ point: NSPoint, stroke: StrokeData, radius: CGFloat) -> Bool {
        for strokePoint in stroke.points {
            let dx = point.x - strokePoint.point.x
            let dy = point.y - strokePoint.point.y
            let distance = sqrt(dx * dx + dy * dy)
            // 考虑笔划粗细，加大检测范围
            let effectiveRadius = radius + stroke.sizeForPressure(strokePoint.pressure) / 2
            if distance <= effectiveRadius {
                return true
            }
        }
        return false
    }
    
    // MARK: - 键盘事件
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // Delete/Backspace 删除选中笔划
        if (event.keyCode == 51 || event.keyCode == 117) && !selectedStrokeIndices.isEmpty {
            deleteSelectedStrokes()
            return
        }
        // Escape 取消选区
        if event.keyCode == 53 && !selectedStrokeIndices.isEmpty {
            clearSelection()
            return
        }
        super.keyDown(with: event)
    }
    
    // MARK: - 操作
    
    /// 撤销最后一笔
    func undo() {
        if let lastStroke = strokes.popLast() {
            undoStack.append(lastStroke)
            cacheNeedsUpdate = true
            needsDisplay = true
        }
    }
    
    /// 重做
    func redo() {
        if let stroke = undoStack.popLast() {
            strokes.append(stroke)
            cacheNeedsUpdate = true
            needsDisplay = true
        }
    }
    
    /// 清除所有笔划
    func clearAll() {
        strokes.removeAll()
        undoStack.removeAll()
        currentStroke = nil
        cacheNeedsUpdate = true
        needsDisplay = true
    }
    
    /// 获取绘图内容为图片（用于截图合成）
    func getDrawingImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        
        for stroke in strokes {
            drawStroke(stroke)
        }
        
        image.unlockFocus()
        return image
    }
}
