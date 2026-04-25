# InputLock 技术栈文档

## 总览

本项目采用 macOS 原生技术栈，优先使用 Apple 最新推荐的 API 和 Swift 语言特性。

| 层级 | 技术选型 |
|------|---------|
| 语言 | Swift 6 (Strict Concurrency) |
| UI 框架 | SwiftUI + AppKit |
| 并发模型 | Swift Concurrency (async/await, Actor) |
| 事件拦截 | ~~CGEvent Tap~~ 不再需要 |
| 输入法 API | Carbon TIS (Text Input Source) |
| 持久化 | UserDefaults + @AppStorage |
| 最低部署 | macOS 26 |

---

## 1. 应用形态：菜单栏应用

### MenuBarExtra (SwiftUI)

使用 SwiftUI `MenuBarExtra` 创建菜单栏图标和菜单，这是 macOS 13+ 引入的原生 API：

```swift
@main
struct InputLockApp: App {
    var body: some Scene {
        MenuBarExtra("InputLock", systemImage: "lock.fill") {
            // 菜单内容
        }
    }
}
```

### 隐藏 Dock 图标

在 `Info.plist` 中设置 `LSUIElement = YES`，使应用不在 Dock 中显示图标。

---

## 2. 输入法控制

### TIS API (Text Input Source)

通过 Carbon 框架的 TIS API 枚举和管理输入法：

- `TISCopyAvailableKeyboardInputSources()` — 获取所有可用输入法
- `TISCopyCurrentKeyboardInputSource()` — 获取当前激活的输入法
- `TISGetInputSourceProperty(source, kTISPropertyInputSourceID)` — 获取输入法唯一标识
- `TISGetInputSourceProperty(source, kTISPropertyLocalizedName)` — 获取输入法显示名称
- `TISSelectInputSource(source)` — 切换到指定输入法

### 输入法变化监听

通过 `NotificationCenter` 监听系统输入法变化通知：

- `NSTextInputContextKeyboardSelectionDidChangeNotification` — 输入法切换时触发

---

## 3. 锁定机制：检测并回退

### 核心思路

目标是对抗**系统自动切换输入法**（如窗口焦点变化时 macOS 自动恢复上次使用的输入法），而非拦截用户主动切换。

因此不需要 `CGEventTap` 拦截键盘事件，而是采用**监听 → 判断 → 回退**的模式：

```
系统自动切换输入法 → 监听到变化 → 判断来源
  ├── 系统自动切换 → 调用 TISSelectInputSource 切回锁定的输入法
  └── 用户主动切换 → 放行，更新锁定目标为用户选择的输入法
```

### 来源区分策略

需要区分输入法切换的来源：

1. **用户主动切换** — 用户按下快捷键（Caps Lock、Ctrl+Space 等）切换输入法
   - 处理：放行，并将锁定目标更新为新输入法
2. **系统自动切换** — 窗口焦点变化、系统策略等触发的自动切换
   - 处理：立即调用 `TISSelectInputSource()` 切回锁定的输入法

区分方法：通过短时间窗口内是否检测到输入法切换快捷键的键盘事件来判断。可能需要轻量级的 `CGEventTap` 仅用于检测（不拦截）快捷键按下，或通过对比前后状态变化模式来推断来源。

### 所需权限

由于不再拦截键盘事件，权限需求降低：
- **Accessibility 权限** — 可能仍需，取决于来源检测方案
- 不再需要 Input Monitoring 权限（若不使用 CGEventTap）

---

## 4. 并发模型

项目已启用 Swift 6 并发特性：

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — 默认 MainActor 隔离
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — 启用渐进式并发迁移

### 架构模式

```
InputLockApp (@main)
  └── MenuBarExtra (SwiftUI 视图)
        └── InputLockManager (ObservableObject / @Observable)
              ├── InputSourceMonitor — 监听输入法变化 (TIS API + NotificationCenter)
              ├── EventTapManager — 管理事件拦截 (CGEvent Tap)
              └── LockState — 锁定状态持久化 (UserDefaults)
```

关键类型使用 `@Observable`（macOS 14+ Observation 框架）替代 `ObservableObject`，这是 Apple 推荐的新标准。

---

## 5. 持久化

- `@AppStorage` (SwiftUI) — 直接绑定 UserDefaults 到 SwiftUI 视图
- 存储内容：用户锁定的输入法 ID、锁定开关状态

---

## 6. App Sandbox 评估

**结论：不推荐开启 App Sandbox。**

本项目核心依赖的 API 沙盒兼容性：

| API | 沙盒内 | 用途 |
|-----|--------|------|
| `TISCopyAvailableKeyboardInputSources()` | ✅ 可用 | 枚举输入法（只读） |
| `TISSelectInputSource()` | ❌ 被阻止 | 切换输入法（修改全局状态） |
| `NSTextInputContextKeyboardSelectionDidChangeNotification` | ⚠️ 仅本应用 | 无法监听系统全局变化 |
| `kTISNotifySelectedKeyboardInputSourceChanged` (Darwin) | ⚠️ 可能受限 | 系统全局输入法变化通知 |
| `CGEventTap` | ❌ 被阻止 | 键盘事件检测 |

InputLock 的两个核心操作——**全局监听输入法变化**和**调用 `TISSelectInputSource()` 切回输入法**——在沙盒下均无法完成。没有对应的沙盒 entitlement 可以授权这些操作。

分发方式：关闭 Sandbox，通过 Hardened Runtime + Developer ID 签名，在 App Store 外分发（或 Notarization 后直接分发）。

---

## 7. 依赖策略

**零外部依赖**。本项目仅使用 Apple 系统 SDK 内置框架：

| 框架 | 用途 |
|------|------|
| SwiftUI | 菜单栏 UI |
| AppKit | NSStatusBar 辅助（如需要） |
| Carbon (TIS) | 输入法枚举、切换、监听 |
| CoreGraphics (CGEvent) | 键盘事件检测（仅检测来源，非拦截） |
| Foundation | 基础类型、NotificationCenter、UserDefaults |
