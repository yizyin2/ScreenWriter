import Cocoa
import Quartz

/// 屏幕截图工具
class ScreenCapture {
    
    /// 保存模式
    enum SaveMode {
        case askUser            // 弹窗询问用户
        case screenshotOnly     // 仅保存截图
        case whiteBackgroundOnly // 仅保存白色背景
    }
    
    /// 捕获屏幕并保存（异步流程，不阻塞主线程）
    /// 策略：先获取笔迹 → 隐藏覆盖窗口 → 异步等待窗口系统刷新 → 截屏 → 合成笔迹 → 恢复窗口
    static func captureAndSave(overlayWindows: [NSWindow], drawingViews: [DrawingView], saveMode: SaveMode = .askUser) {
        guard let mainScreen = NSScreen.main else { return }
        
        // 第一步：从绘图视图获取笔迹图像（在隐藏前获取）
        let drawingImages = drawingViews.map { view -> (NSImage, NSRect) in
            let image = view.getDrawingImage()
            let frame = view.window?.frame ?? view.frame
            return (image, frame)
        }
        
        // 第二步：隐藏所有覆盖窗口
        for window in overlayWindows {
            window.orderOut(nil)
        }
        NSApp.hide(nil)
        
        // 第三步：异步等待窗口系统刷新后再截图（避免阻塞主线程）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let screenImage = performScreenCapture(mainScreen: mainScreen)
            
            // 恢复应用可见
            NSApp.unhide(nil)
            
            guard let screenImage = screenImage else {
                restoreWindows(overlayWindows)
                showErrorAlert(message: "无法捕获屏幕图像。请确保已授予 ScreenWriter 屏幕录制权限。\n系统设置 → 隐私与安全性 → 屏幕录制")
                return
            }
            
            // 继续合成和保存流程
            finishCapture(
                screenImage: screenImage,
                mainScreen: mainScreen,
                drawingImages: drawingImages,
                overlayWindows: overlayWindows,
                saveMode: saveMode
            )
        }
    }
    
    /// 执行屏幕截图（screencapture 命令 + CGWindowListCreateImage 回退）
    private static func performScreenCapture(mainScreen: NSScreen) -> NSImage? {
        let tempPath = NSTemporaryDirectory() + "screenwriter_\(ProcessInfo.processInfo.processIdentifier).png"
        
        // 先删除可能存在的旧文件
        try? FileManager.default.removeItem(atPath: tempPath)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", tempPath]
        
        var capturedScreenImage: NSImage? = nil
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
               let img = NSImage(data: data) {
                capturedScreenImage = img
            }
        } catch {
            // screencapture 失败，使用回退方案
        }
        
        // 清理临时文件
        try? FileManager.default.removeItem(atPath: tempPath)
        
        // 如果 screencapture 失败，使用 CGWindowListCreateImage 回退
        if capturedScreenImage == nil {
            let screenRect = mainScreen.frame
            let cgRect = CGRect(x: 0, y: 0, width: screenRect.width, height: screenRect.height)
            
            if let cgImage = CGWindowListCreateImage(
                cgRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) {
                capturedScreenImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                )
            }
        }
        
        return capturedScreenImage
    }
    
    /// 完成截图合成和保存
    private static func finishCapture(
        screenImage: NSImage,
        mainScreen: NSScreen,
        drawingImages: [(NSImage, NSRect)],
        overlayWindows: [NSWindow],
        saveMode: SaveMode
    ) {
        
        let screenRect = mainScreen.frame
        let imageSize = screenImage.size
        
        // 第四步：合成截图 + 笔迹
        let compositeImage = NSImage(size: imageSize)
        compositeImage.lockFocus()
        screenImage.draw(in: NSRect(origin: .zero, size: imageSize))
        
        let scaleX = imageSize.width / screenRect.width
        let scaleY = imageSize.height / screenRect.height
        
        for (drawingImage, frame) in drawingImages {
            let destRect = NSRect(
                x: (frame.origin.x - screenRect.origin.x) * scaleX,
                y: (frame.origin.y - screenRect.origin.y) * scaleY,
                width: frame.width * scaleX,
                height: frame.height * scaleY
            )
            drawingImage.draw(in: destRect)
        }
        compositeImage.unlockFocus()
        
        // 第五步：创建白色背景版本
        let whiteBackgroundImage = NSImage(size: imageSize)
        whiteBackgroundImage.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        for (drawingImage, frame) in drawingImages {
            let destRect = NSRect(
                x: (frame.origin.x - screenRect.origin.x) * scaleX,
                y: (frame.origin.y - screenRect.origin.y) * scaleY,
                width: frame.width * scaleX,
                height: frame.height * scaleY
            )
            drawingImage.draw(in: destRect)
        }
        whiteBackgroundImage.unlockFocus()
        
        // 第六步：恢复覆盖窗口
        restoreWindows(overlayWindows)
        
        // 第七步：根据保存模式处理
        switch saveMode {
        case .askUser:
            showSaveOptionsDialog(compositeImage: compositeImage, whiteBackgroundImage: whiteBackgroundImage)
        case .screenshotOnly:
            directSave(compositeImage: compositeImage, whiteBackgroundImage: nil)
        case .whiteBackgroundOnly:
            directSave(compositeImage: nil, whiteBackgroundImage: whiteBackgroundImage)
        }
    }
    
    /// 恢复覆盖窗口
    private static func restoreWindows(_ windows: [NSWindow]) {
        for window in windows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 将图像保存到指定路径，返回是否成功
    @discardableResult
    private static func saveImageToPath(_ image: NSImage, path: String) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }
        
        // 确保目录存在
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
    
    /// 生成文件名
    private static func generateFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateStr = formatter.string(from: Date())
        return "ScreenWriter_\(dateStr).png"
    }
    
    /// 显示错误提示
    private static func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "截图保存失败"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 弹出保存选择对话框
    private static func showSaveOptionsDialog(compositeImage: NSImage, whiteBackgroundImage: NSImage) {
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "保存截图"
        alert.informativeText = "请选择保存方式："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "截图 + 白底")       // 第一个按钮：两者都保存
        alert.addButton(withTitle: "仅截图")            // 第二个按钮：仅截图
        alert.addButton(withTitle: "仅白底")            // 第三个按钮：仅白底
        
        let response = alert.runModal()
        
        let settings = BrushSettings.shared
        let fileName = generateFileName()
        var savedPaths: [String] = []
        
        // 根据用户选择保存
        let saveScreenshot = (response == .alertFirstButtonReturn || response == .alertSecondButtonReturn)
        let saveWhiteBg = (response == .alertFirstButtonReturn || response == .alertThirdButtonReturn)
        
        if saveScreenshot {
            let screenshotPath = (settings.screenshotSavePath as NSString).appendingPathComponent(fileName)
            saveImageToPath(compositeImage, path: screenshotPath)
            savedPaths.append("截图: \(screenshotPath)")
        }
        
        if saveWhiteBg {
            let whiteBgFileName = fileName.replacingOccurrences(of: ".png", with: "_白底.png")
            let whiteBgPath = (settings.whiteBackgroundSavePath as NSString).appendingPathComponent(whiteBgFileName)
            saveImageToPath(whiteBackgroundImage, path: whiteBgPath)
            savedPaths.append("白底: \(whiteBgPath)")
        }
        
        // 显示保存结果
        if !savedPaths.isEmpty {
            let resultAlert = NSAlert()
            resultAlert.messageText = "保存成功"
            resultAlert.informativeText = savedPaths.joined(separator: "\n")
            resultAlert.alertStyle = .informational
            resultAlert.addButton(withTitle: "在 Finder 中显示")
            resultAlert.addButton(withTitle: "确定")
            
            let resultResponse = resultAlert.runModal()
            if resultResponse == .alertFirstButtonReturn {
                // 打开第一个保存路径所在文件夹
                let firstPath = saveScreenshot
                    ? (settings.screenshotSavePath as NSString).appendingPathComponent(fileName)
                    : (settings.whiteBackgroundSavePath as NSString).appendingPathComponent(
                        fileName.replacingOccurrences(of: ".png", with: "_白底.png"))
                NSWorkspace.shared.selectFile(firstPath, inFileViewerRootedAtPath: "")
            }
        }
    }
    
    /// 直接保存（不弹对话框）
    private static func directSave(compositeImage: NSImage?, whiteBackgroundImage: NSImage?) {
        let settings = BrushSettings.shared
        let fileName = generateFileName()
        var displayTexts: [String] = []  // 用于显示的文本
        var filePaths: [String] = []     // 实际保存的文件路径
        
        if let img = compositeImage {
            let path = (settings.screenshotSavePath as NSString).appendingPathComponent(fileName)
            saveImageToPath(img, path: path)
            displayTexts.append("截图: \(path)")
            filePaths.append(path)
        }
        
        if let img = whiteBackgroundImage {
            let whiteBgFileName = fileName.replacingOccurrences(of: ".png", with: "_白底.png")
            let path = (settings.whiteBackgroundSavePath as NSString).appendingPathComponent(whiteBgFileName)
            saveImageToPath(img, path: path)
            displayTexts.append("白底: \(path)")
            filePaths.append(path)
        }
        
        if !displayTexts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "保存成功"
            alert.informativeText = displayTexts.joined(separator: "\n")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "在 Finder 中显示")
            alert.addButton(withTitle: "确定")
            
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // 直接使用保存的文件路径，不从显示文本中解析
                if let firstPath = filePaths.first {
                    NSWorkspace.shared.selectFile(firstPath, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
}
