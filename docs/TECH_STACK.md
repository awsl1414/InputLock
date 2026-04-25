# InputLock 技术栈文档

## 总览

本项目采用 macOS 原生技术栈，优先使用 Apple 最新推荐的 API 和 Swift 语言特性。

| 层级 | 技术选型 |
|------|---------|
| 语言 | Swift 6 (Strict Concurrency, MainActor 默认隔离) |
| UI 框架 | SwiftUI |
| 并发模型 | Swift Concurrency + @Observable |
| 事件检测 | CGEventTap (listenOnly, keyDown + flagsChanged) |
| 输入法 API | Carbon TIS (Text Input Source) |
| 输入法监听 | Darwin CFNotificationCenter |
| 持久化 | UserDefaults |
| 权限检测 | AXIsProcessTrusted() 轮询 |
| 登录项 | SMAppService (macOS 13+) |
| 最低部署 | macOS 14.0 |

---

## 1. 应用形态：菜单栏应用

### MenuBarExtra (SwiftUI)

使用 SwiftUI `MenuBarExtra` 创建菜单栏图标和菜单：

```swift
@main
struct InputLockApp: App {
    var body: some Scene {
        MenuBarExtra { ... } label: { ... }
    }
}
```

### 隐藏 Dock 图标

在 `InputLock-Info.plist`（项目根目录）中设置 `LSUIElement = true`，使应用不在 Dock 中显示图标。

---

## 2. 输入法控制

### TIS API (Text Input Source)

通过 Carbon 框架的 TIS API 枚举和管理输入法：

- `TISCreateInputSourceList(nil, false)` — 获取用户已启用的输入法（`includeAllInstalled = false`）
- `TISCopyCurrentKeyboardInputSource()` — 获取当前激活的输入法
- `TISGetInputSourceProperty(source, key)` — 获取输入法属性（ID、名称、启用状态等）
- `TISSelectInputSource(source)` — 切换到指定输入法

### CF 类型桥接

TIS API 返回 CFType，需要手动桥接：

```swift
let cfArray = rawResult.takeRetainedValue()
let count = CFArrayGetCount(cfArray)
let source = unsafeBitCast(CFArrayGetValueAtIndex(cfArray, i), to: TISInputSource.self)
```

不能使用 `as! [TISInputSource]` 强转。`MEMBER_IMPORT_VISIBILITY` 已关闭，因为 Carbon TIS 头文件不在 umbrella header 中。

### 输入法变化监听

通过 `CFNotificationCenterAddObserver` 监听 Darwin notification：

- `kTISNotifySelectedKeyboardInputSourceChanged` — 全局输入法切换通知
- 桥接到 `NotificationCenter.default` 用于 MainActor 处理
- observer 在 `deinit` 中清理

### 缓存策略

`sourceMap: [String: TISInputSource]` 缓存输入法引用。`selectSource(id:)` 未命中时自动调用 `refreshSources()` 刷新缓存。

---

## 3. 锁定机制：检测并回退

### 核心流程

对抗**系统自动切换输入法**（如窗口焦点变化时 macOS 自动恢复上次使用的输入法），放行用户主动切换。

```
输入法变化通知 → handleSourceChanged
  ├── isReverting → 跳过（防止递归）
  ├── 与锁定目标一致 → 跳过
  ├── 快捷键时间戳在 100ms 窗口内 → 用户切换，更新锁定目标
  └── 否则 → 系统切换，revert 切回（最多 5 次，间隔 50ms）
```

### 来源区分

- **用户主动切换** — `EventDetectorService` 检测 Ctrl+Space / Caps Lock 按键时间戳
- **系统自动切换** — 无对应快捷键事件，在时间窗口外触发

### 所需权限

- **Accessibility（辅助功能）权限** — CGEventTap 和 AXIsProcessTrusted 都需要
- 不需要 Input Monitoring 权限（listenOnly 模式）

---

## 4. 并发模型

项目已启用 Swift 6 并发特性：

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — 所有类型默认 MainActor 隔离
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — 渐进式并发迁移

### 模式

- `@Observable` 替代 `ObservableObject`（macOS 14+ Observation 框架）
- `MainActor.assumeIsolated` 用于 Timer 回调等已知在主线程的上下文
- `withObservationTracking` + 手动重连用于监听 @Observable 属性变化
- 服务回调使用 `[weak self]` 避免循环引用

---

## 5. 持久化

- UserDefaults 存储三组状态：`isLocked`、`lockedSourceID`、`launchAtLogin`
- 启动项实际状态由 `SMAppService.mainApp.status` 驱动，不依赖 UserDefaults 缓存
- `AppState` 在 `startup()` 中校准启动项状态为 SMAppService 真实值

---

## 6. App Sandbox 评估

**结论：不推荐开启 App Sandbox。**

| API | 沙盒兼容 | 用途 |
|-----|----------|------|
| `TISCreateInputSourceList` | ⚠️ 可能受限 | 枚举输入法 |
| `TISSelectInputSource()` | ❌ 被阻止 | 切换输入法 |
| `kTISNotifySelectedKeyboardInputSourceChanged` | ⚠️ 可能受限 | 全局输入法变化通知 |
| `CGEventTap` | ❌ 被阻止 | 键盘事件检测 |

分发方式：关闭 Sandbox，通过 Hardened Runtime + Developer ID 签名 + Notarization 直接分发。

---

## 7. 依赖策略

**零外部依赖**。仅使用 Apple 系统 SDK：

| 框架 | 用途 |
|------|------|
| SwiftUI | 菜单栏 UI、窗口管理 |
| Carbon (TIS) | 输入法枚举、切换、监听 |
| CoreGraphics (CGEvent) | 键盘事件检测（listen-only） |
| ApplicationServices | AXIsProcessTrusted 权限检测 |
| ServiceManagement | SMAppService 登录项管理 |
| Foundation | NotificationCenter、UserDefaults、Timer |
