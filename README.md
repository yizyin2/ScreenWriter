# ScreenWriter

macOS 屏幕批注工具，支持数位板压感。可以在屏幕上直接书写、标注，适合教学演示、会议讲解等场景。

## 功能

- 全屏透明画布覆盖，在任何应用上方书写
- 数位板压感支持（Wacom 等），笔迹粗细随压力变化
- 数位板专属模式：仅数位板能画，鼠标操作穿透到桌面
- 画笔 / 荧光笔 / 点擦除 / 整笔擦除
- 索套选择：框选笔迹后拖拽移动或删除
- 浮动工具栏，可拖拽
- 全局快捷键呼出/收起
- 多显示器支持
- 截图保存（带批注 / 白底批注）
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
