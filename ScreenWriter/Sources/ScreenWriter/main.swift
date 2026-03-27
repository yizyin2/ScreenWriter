import Cocoa

// 创建应用实例
let app = NSApplication.shared

// 设置为菜单栏应用模式（不在 Dock 显示图标，仅在菜单栏显示）
app.setActivationPolicy(.accessory)

// 创建并设置应用代理
let delegate = AppDelegate()
app.delegate = delegate

// 捕获未处理异常
NSSetUncaughtExceptionHandler { exception in
    NSLog("未捕获异常: %@ 原因: %@", exception.name.rawValue, exception.reason ?? "未知")
}

// 启动应用事件循环
app.run()
