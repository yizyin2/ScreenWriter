# ScreenWriter ✏️

一款 macOS 屏幕批注工具，支持数位板压感绘制，可在屏幕上自由书写、标注和绘画。

## ✨ 功能特色

- **屏幕批注** — 在任意屏幕上覆盖透明画布，直接书写标注
- **数位板压感** — 完整支持 Wacom 等数位板的压力感应，笔迹粗细随压力变化
- **数位板专属模式** — 仅响应数位板输入，鼠标操作穿透到桌面，互不干扰
- **多种画笔工具** — 普通画笔、荧光笔、点擦除、整笔擦除
- **索套选择** — 框选笔迹后可自由拖拽移动或批量删除
- **浮动工具栏** — 可拖拽的工具栏，快速切换画笔颜色、粗细、工具
- **全局快捷键** — 随时呼出/收起，不打断工作流
- **多显示器支持** — 自动覆盖所有已连接屏幕
- **截图保存** — 一键保存当前屏幕截图（含批注）或白底批注
- **撤销/重做** — 完整的操作历史记录
- **光标自适应** — 画笔光标自动根据背景亮度切换颜色，始终清晰可见

## 📋 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+ / Swift 5.9+
- 需要授予**辅助功能权限**（用于全局快捷键）

## 🚀 编译与运行

```bash
# 克隆项目
git clone https://github.com/你的用户名/ScreenWriter.git
cd ScreenWriter/ScreenWriter

# 编译
swift build

# 运行
swift run
```

或者用 Xcode 打开：

```bash
open Package.swift
```

然后按 `⌘R` 运行。

## ⌨️ 默认快捷键

| 快捷键 | 功能 |
|--------|------|
| 自定义 | 呼出/收起批注画布 |
| `ESC` | 退出批注模式 |
| `⌘Z` | 撤销 |
| `⌘⇧Z` | 重做 |
| `E` | 切换橡皮擦 |
| 自定义 | 清除画布 |
| 自定义 | 保存截图 |

> 快捷键可在设置面板中自定义配置。

## 🏗️ 项目结构

```
ScreenWriter/
├── Package.swift              # Swift Package Manager 配置
└── Sources/ScreenWriter/
    ├── main.swift             # 应用入口
    ├── AppDelegate.swift      # 应用生命周期管理
    ├── DrawingView.swift      # 核心绘图引擎（压感、路径渲染、选区）
    ├── OverlayWindow.swift    # 透明覆盖窗口 + CGEvent Tap 数位板拦截
    ├── FloatingToolbar.swift  # 浮动工具栏 UI
    ├── BrushSettings.swift    # 画笔参数管理
    ├── ScreenCapture.swift    # 截图保存功能
    ├── SettingsWindow.swift   # 设置面板
    ├── ShortcutManager.swift  # 全局快捷键管理
    └── StatusBarController.swift  # 状态栏菜单控制
```

## 🔧 技术实现

- **绘图引擎**：基于 `NSBezierPath` 的可变宽度路径渲染，使用圆形印章 + 梯形连接实现平滑压感笔迹
- **数位板拦截**：通过 `CGEvent.tapCreate` 在系统级拦截数位板事件，实现鼠标穿透 + 数位板绘制并存
- **性能优化**：已完成笔划缓存为 `NSImage`，仅实时渲染当前笔划，避免重绘开销
- **光标自适应**：采样光标位置下方 11×11 像素区域的平均亮度，200ms 节流避免性能影响

## 📄 许可证

本项目采用 [GPL-3.0](LICENSE) 许可证开源。

## 🤝 参与贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建你的功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m '添加某个功能'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 发起 Pull Request
