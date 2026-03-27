# ScreenWriter

macOS 屏幕批注工具，支持数位板压感。可以在屏幕上直接书写、标注，适合教学演示、会议讲解等场景。

## 数位板专属模式

这是 ScreenWriter 的核心功能。开启后，画布对鼠标完全透明——你可以正常点击桌面、操作其他应用，只有数位板的笔才能在画布上绘制。

工作原理：

- 画布窗口设置 `ignoresMouseEvents = true`，所有鼠标事件自然穿透
- 通过 `CGEvent.tapCreate` 在系统级拦截数位板事件，阻止其到达桌面，直接分发给绘图引擎
- 笔进入感应区时自动隐藏系统光标、激活应用、显示自绘画笔光标
- 笔离开感应区时恢复系统光标，并自动切回之前的前台应用
- 支持绘画/穿透模式切换，穿透时数位板事件也放行

这意味着你可以一边用鼠标操作 PPT / 浏览器，一边随时用笔在屏幕上画标注，两者互不干扰。

## 其他功能

- 全屏透明画布覆盖，在任何应用上方书写
- 压感支持，笔迹粗细随压力变化
- 画笔 / 荧光笔 / 点擦除 / 整笔擦除
- 索套选择：框选笔迹后拖拽移动或删除
- 浮动工具栏
- 全局快捷键呼出/收起
- 多显示器
- 截图保存（带批注 / 白底）
- 撤销 / 重做

## 系统要求

- macOS 13.0+
- Swift 5.9+ / Xcode 15+
- 需要辅助功能权限（全局快捷键）

## 编译运行

```bash
git clone https://github.com/yizyin2/ScreenWriter.git
cd ScreenWriter/ScreenWriter
swift build
swift run
```

也可以用 Xcode 打开 `Package.swift` 直接运行。

## 项目结构

```
Sources/ScreenWriter/
├── main.swift              # 入口
├── AppDelegate.swift       # 生命周期
├── DrawingView.swift       # 绘图引擎
├── OverlayWindow.swift     # 透明窗口 + 数位板事件拦截
├── FloatingToolbar.swift   # 工具栏
├── BrushSettings.swift     # 画笔设置
├── ScreenCapture.swift     # 截图
├── SettingsWindow.swift    # 设置面板
├── ShortcutManager.swift   # 快捷键
└── StatusBarController.swift  # 状态栏
```

## 许可证

GPL-3.0
