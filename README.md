# InputLock

macOS 原生输入法锁定工具，防止系统自动切换输入法，放行用户主动切换。

## 为什么需要 InputLock

macOS 会根据窗口焦点自动切换输入法——当你从浏览器切到终端，输入法可能从中文自动变回英文。InputLock 锁定你选择的输入法，阻止这种自动切换，同时不影响你用快捷键主动切换。

## 功能

- **锁定输入法** — 阻止系统自动切换，用户主动切换时自动放行并更新锁定目标
- **选择锁定目标** — 从系统已启用的输入法中选择要锁定的输入法
- **登录时启动** — 使用 SMAppService 注册为登录项
- **菜单栏应用** — 无 Dock 图标，轻量常驻

## 截图

菜单栏图标实时反映状态：

| 未授权 | 已锁定 | 已解锁 |
|--------|--------|--------|
| 🔒 | 🔒 | 🔓 |

菜单结构：

```
┌─────────────────────────────┐
│ 🔒 输入法锁定: 开启/关闭     │
├─────────────────────────────┤
│ ▸ 选择锁定输入法              │
│   ● ABC                     │
│     微信输入法                │
├─────────────────────────────┤
│ ✓ 登录时自动启动              │
├─────────────────────────────┤
│ 关于                        │
│ 退出                        │
└─────────────────────────────┘
```

## 系统要求

- macOS 14.0 (Sonoma) 及以上
- 辅助功能权限（首次启动时引导授予）

## 构建

```bash
# Debug
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build

# Release
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Release build
```

或直接用 Xcode 打开 `InputLock.xcodeproj`。

## 工作原理

```
输入法变化通知 → 判断来源
  ├── 检测到快捷键 (Ctrl+Space / Caps Lock) → 用户切换 → 放行，更新锁定目标
  └── 无快捷键事件 → 系统自动切换 → 立即切回锁定的输入法
```

- 通过 Darwin notification 监听全局输入法变化
- CGEventTap listen-only 模式记录快捷键时间戳，不拦截用户按键
- 100ms 时间窗口区分用户操作与系统自动切换

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI (MenuBarExtra) |
| 输入法控制 | Carbon TIS API |
| 输入法监听 | Darwin CFNotificationCenter |
| 快捷键检测 | CGEventTap (listenOnly) |
| 权限检测 | AXIsProcessTrusted() |
| 登录项 | SMAppService |
| 并发 | Swift 6, MainActor 默认隔离, @Observable |
| 持久化 | UserDefaults |
| 外部依赖 | 无 |

## 项目结构

```
InputLock/
├── InputLockApp.swift              — @main 入口
├── AppState.swift                  — @Observable 中心状态与锁定逻辑
├── Models/
│   └── InputSource.swift           — 输入法值类型
├── Services/
│   ├── InputSourceService.swift    — TIS API 输入法枚举/切换/监听
│   ├── EventDetectorService.swift  — CGEventTap 快捷键检测
│   ├── AuthorizationService.swift  — 辅助功能权限管理
│   └── LaunchAtLoginService.swift  — 登录项管理
├── Views/
│   ├── MenuBarView.swift           — 菜单栏下拉菜单
│   ├── OnboardingView.swift        — 首次启动授权引导
│   └── AboutView.swift             — 关于窗口
└── Extensions/
    └── Notification+Names.swift    — 通知名统一定义
```

## 许可证

[MIT](LICENSE)
