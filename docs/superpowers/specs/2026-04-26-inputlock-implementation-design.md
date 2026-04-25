# InputLock 实现设计

## 概述

InputLock 是一个 macOS 原生菜单栏应用，通过监听系统输入法变化并自动回退的方式，对抗 macOS 的自动输入法切换行为。不拦截用户主动切换。

## 技术决策

| 决策项 | 选型 | 原因 |
|--------|------|------|
| 来源检测 | CGEventTap 被动监听（listenOnly） | 检测快捷键按下时间戳，准确区分用户/系统切换 |
| 架构模式 | 协议导向 + 服务注入 | 职责单一，可测试，适度抽象 |
| 并发模型 | Swift 6 MainActor 默认隔离 | 所有状态在主线程，无数据竞争 |
| 最低部署 | macOS 14 | 扩大兼容范围 |
| 开发基准 | macOS 26 SDK | 严格使用最新 API 标准 |

## 模块划分与文件结构

```
InputLock/
├── InputLockApp.swift              @main 入口，MenuBarExtra + 条件窗口
├── AppState.swift                  @Observable 全局状态，协调各服务
│
├── Services/
│   ├── InputSourceService.swift    输入法枚举、切换、变化监听（TIS API）
│   ├── EventDetectorService.swift  CGEventTap 被动监听切换快捷键
│   ├── AuthorizationService.swift  Accessibility 权限检测
│   └── LaunchAtLoginService.swift  登录项管理（SMAppService）
│
├── Views/
│   ├── MenuBarView.swift           MenuBarExtra 菜单内容
│   ├── OnboardingView.swift        首次启动授权引导窗口
│   └── AboutView.swift             关于窗口
│
├── Models/
│   └── InputSource.swift           输入法数据模型（id, name, source ref）
│
└── Assets.xcassets/                图标资源
```

## 核心数据模型

### AppState

```swift
@Observable
class AppState {
    // 锁定状态
    var isLocked: Bool
    var lockedSourceID: String?

    // 权限状态
    var isAuthorized: Bool

    // 内部标记
    var isReverting: Bool = false           // 正在主动切回
    var lastSwitchShortcutTime: Date?       // 上次检测到快捷键的时间

    // 输入法列表
    var availableSources: [InputSource]

    // 服务实例
    let inputSourceService: InputSourceService
    let eventDetector: EventDetectorService
    let authorizationService: AuthorizationService
    let launchAtLogin: LaunchAtLoginService
}
```

### InputSource

```swift
struct InputSource: Hashable, Identifiable {
    let id: String          // kTISPropertyInputSourceID
    let name: String        // kTISPropertyLocalizedName
    let tisSource: TISInputSource
}
```

## 服务协议

### InputSourceService

```swift
protocol InputSourceService {
    var availableSources: [InputSource] { get }
    var currentSourceID: String { get }
    func selectSource(id: String)
    func refreshSources()
}
```

- `refreshSources()` 调用 `TISCopyAvailableKeyboardInputSources()` 刷新列表
- 通过 Darwin notification `kTISNotifySelectedKeyboardInputSourceChanged` 监听全局输入法变化
- 收到变化通知时读取当前输入法 ID，交由 AppState 处理锁定逻辑

### EventDetectorService

```swift
protocol EventDetectorService {
    var lastSwitchShortcutTime: Date? { get }
    func startMonitoring()
    func stopMonitoring()
}
```

- `CGEventTapCreate` 使用 `.listenOnly` 模式
- 仅匹配输入法切换快捷键（Ctrl+Space、Caps Lock 等）
- 匹配时记录时间戳到 `lastSwitchShortcutTime`

### AuthorizationService

```swift
protocol AuthorizationService {
    var isAuthorized: Bool { get }
    func openSystemPreferences()
    func startMonitoring()
}
```

- `AXIsProcessTrusted()` 检查授权状态
- 定时轮询（~1s）检测授权变化
- `openSystemPreferences()` 跳转系统设置辅助功能页面

### LaunchAtLoginService

```swift
protocol LaunchAtLoginService {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}
```

- 使用 `SMAppService.mainApp` 的 `register()` / `unregister()`

## 锁定机制与竞争处理

### 判断流程

收到输入法变化通知时：

```
isReverting == true         → 忽略（自身切回触发）
新输入法 == lockedSourceID   → 忽略（已是目标）
快捷键在 100ms 内            → 用户切换：更新 lockedSourceID
其他                        → 系统自动切换：执行回退
```

### 回退流程

```
1. isReverting = true
2. TISSelectInputSource() 切回 lockedSourceID
3. 50ms 冷却期
4. isReverting = false
5. 再次检查当前输入法，如仍非目标则再次切回
```

### 竞争场景覆盖

| 场景 | 处理 |
|------|------|
| 回退触发无限循环 | `isReverting` 标记忽略自身触发的通知 |
| 回退期间系统再次切换 | 50ms 冷却后二次检查 |
| 快捷键与系统切换交错 | 时间戳窗口判定，非简单 bool |
| 线程安全 | MainActor 默认隔离，所有状态变更在主线程 |

## 视图设计

### MenuBarView 菜单结构

```
┌─────────────────────────────┐
│ 🔒 输入法锁定: 开启/关闭     │  Button，翻转 isLocked
├─────────────────────────────┤
│ ▸ 选择锁定输入法              │  Menu 子菜单
│   ● 简体中文拼音             │  ForEach + Button
│     美式英文                  │  选中项显示勾选标记
│     搜狗输入法                │
├─────────────────────────────┤
│ ✓ 登录时自动启动              │  Toggle
├─────────────────────────────┤
│ 关于 InputLock              │  Button，打开 AboutView
├─────────────────────────────┤
│ 退出 InputLock              │  Button，NSApplication.terminate()
└─────────────────────────────┘
```

图标状态：锁定 `lock.fill` / 未锁定 `lock.open.fill` / 未授权 `lock.slash.fill`

### OnboardingView

独立 Window，包含应用图标、欢迎文案、授权步骤说明、"打开系统设置"按钮、"稍后设置"按钮。`isAuthorized` 变为 `true` 时自动关闭。

### AboutView

标准 macOS 风格关于窗口，显示应用图标、名称、版本号（从 Bundle.main 读取）、版权信息、关闭按钮。

## 应用生命周期

```
启动
 → AuthorizationService.startMonitoring()
 → isAuthorized? No → 显示 OnboardingView，等待授权
 → InputSourceService.refreshSources()
 → 读取持久化状态（isLocked, lockedSourceID, launchAtLogin）
 → isLocked? → EventDetectorService.startMonitoring()
 → 菜单栏就绪
```

## 持久化

| 键 | 类型 | 默认值 |
|----|------|--------|
| `isLocked` | Bool | `false` |
| `lockedSourceID` | String? | `nil` |
| `launchAtLogin` | Bool | `false` |

通过 `@AppStorage` 绑定 UserDefaults。

## Info.plist 配置

| 键 | 值 | 说明 |
|----|---|------|
| `LSUIElement` | `YES` | 隐藏 Dock 图标 |
| `LSMinimumSystemVersion` | `14.0` | 最低系统版本 |

## 项目配置更新

- `MACOSX_DEPLOYMENT_TARGET` 改为 `14.0`
- 移除 `ENABLE_USER_SELECTED_FILES`（Sandbox 相关，已关闭）
- 移除 Debug 配置中多余的 Sandbox 相关设置
