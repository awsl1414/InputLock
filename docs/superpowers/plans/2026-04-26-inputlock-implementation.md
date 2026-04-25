# InputLock 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 macOS 菜单栏应用，通过监听输入法变化并自动回退的方式锁定输入法，对抗系统自动切换。

**Architecture:** 协议导向 + 服务注入。AppState（@Observable）持有全部 UI 状态并协调四个服务。SwiftUI MenuBarExtra 提供 UI。

**Tech Stack:** Swift 6, SwiftUI, macOS 14+ 部署（macOS 26 SDK）, Observation 框架, Carbon TIS, CoreGraphics CGEvent, ServiceManagement

---

## File Structure

| 文件 | 职责 |
|------|------|
| `InputLock/InputLockApp.swift` | @main 入口，MenuBarExtra + 条件窗口 |
| `InputLock/AppState.swift` | @Observable 全局状态，锁定逻辑 |
| `InputLock/Info.plist` | LSUIElement 等自定义配置 |
| `InputLock/Models/InputSource.swift` | 输入法数据模型 |
| `InputLock/Services/AuthorizationService.swift` | Accessibility 权限检测 |
| `InputLock/Services/LaunchAtLoginService.swift` | 登录项管理 |
| `InputLock/Services/InputSourceService.swift` | TIS API 枚举/切换/监听 |
| `InputLock/Services/EventDetectorService.swift` | CGEventTap 被动监听快捷键 |
| `InputLock/Views/MenuBarView.swift` | 菜单栏下拉菜单 |
| `InputLock/Views/OnboardingView.swift` | 首次启动授权引导 |
| `InputLock/Views/AboutView.swift` | 关于窗口 |

---

### Task 1: 项目配置

**Files:**
- Modify: `InputLock.xcodeproj/project.pbxproj`
- Create: `InputLock/Info.plist`
- Delete: `InputLock/ContentView.swift`

- [ ] **Step 1: 更新部署目标**

将 `project.pbxproj` 中所有 `MACOSX_DEPLOYMENT_TARGET` 从 `26.4` 改为 `14.0`（共 2 处：Debug 和 Release）。

- [ ] **Step 2: 移除 Sandbox 残留配置**

在 `project.pbxproj` 中移除 Debug 和 Release target 配置中的 `ENABLE_USER_SELECTED_FILES = readonly;` 行（共 2 处）。

- [ ] **Step 3: 创建 Info.plist**

创建 `InputLock/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 4: 在 pbxproj 中设置 Info.plist 路径**

在 Debug 和 Release 的 target build configuration 中添加 `INFOPLIST_FILE = InputLock/Info.plist;`，同时保留 `GENERATE_INFOPLIST_FILE = YES;`。

- [ ] **Step 5: 删除 ContentView.swift**

删除 `InputLock/ContentView.swift`。

- [ ] **Step 6: 更新技术栈文档**

将 `docs/TECH_STACK.md` 中事件拦截行从 `~~CGEventTap~~ 不再需要` 改为 `CGEventTap (listenOnly)`。

- [ ] **Step 7: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: 提交**

```
feat: 配置项目基础设置 — macOS 14 部署目标、LSUIElement、清理模板
```

---

### Task 2: InputSource 数据模型

**Files:**
- Create: `InputLock/Models/InputSource.swift`

- [ ] **Step 1: 创建目录和模型文件**

创建 `InputLock/Models/` 目录，然后创建 `InputLock/Models/InputSource.swift`：

```swift
import Foundation

struct InputSource: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 InputSource 数据模型
```

---

### Task 3: AuthorizationService

**Files:**
- Create: `InputLock/Services/AuthorizationService.swift`

- [ ] **Step 1: 创建服务和实现**

创建 `InputLock/Services/` 目录，然后创建 `InputLock/Services/AuthorizationService.swift`：

```swift
import ApplicationServices
import Foundation

protocol AuthorizationService {
    var isAuthorized: Bool { get }
    func openSystemPreferences()
    func startMonitoring()
}

@Observable
final class AuthorizationServiceImpl: AuthorizationService {
    var isAuthorized = false

    private var timer: Timer?

    init() {
        isAuthorized = AXIsProcessTrusted()
    }

    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAuthorization()
            }
        }
    }

    private func checkAuthorization() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAuthorized {
            isAuthorized = trusted
        }
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 AuthorizationService — Accessibility 权限检测与轮询
```

---

### Task 4: LaunchAtLoginService

**Files:**
- Create: `InputLock/Services/LaunchAtLoginService.swift`

- [ ] **Step 1: 创建服务和实现**

创建 `InputLock/Services/LaunchAtLoginService.swift`：

```swift
import Foundation
import ServiceManagement

protocol LaunchAtLoginService {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

@Observable
final class LaunchAtLoginServiceImpl: LaunchAtLoginService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 LaunchAtLoginService — SMAppService 登录项管理
```

---

### Task 5: InputSourceService

**Files:**
- Create: `InputLock/Services/InputSourceService.swift`

- [ ] **Step 1: 创建服务和实现**

创建 `InputLock/Services/InputSourceService.swift`：

```swift
import Carbon
import Foundation

protocol InputSourceService {
    var availableSources: [InputSource] { get }
    var currentSourceID: String { get }
    var onSourceChanged: ((String) -> Void)? { get set }
    func selectSource(id: String)
    func refreshSources()
}

@Observable
final class InputSourceServiceImpl: InputSourceService {
    private(set) var availableSources: [InputSource] = []
    private var sourceMap: [String: TISInputSource] = [:]

    var onSourceChanged: ((String) -> Void)?

    var currentSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        return propertyString(source, kTISPropertyInputSourceID) ?? ""
    }

    init() {
        refreshSources()
        startObserving()
    }

    func refreshSources() {
        guard let sources = TISCopyAvailableKeyboardInputSources()?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        var newSources: [InputSource] = []
        var newMap: [String: TISInputSource] = [:]

        for source in sources {
            guard let category = propertyString(source, kTISPropertyInputSourceCategory),
                  category == kTISCategoryKeyboardInputSource as String else { continue }
            guard let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let isSelectable = Unmanaged<CFBoolean>.fromOpaque(selectable).takeUnretainedValue()
            guard CFBooleanGetValue(isSelectable) else { continue }

            guard let id = propertyString(source, kTISPropertyInputSourceID),
                  let name = propertyString(source, kTISPropertyLocalizedName) else { continue }

            newSources.append(InputSource(id: id, name: name))
            newMap[id] = source
        }

        sourceMap = newMap
        availableSources = newSources
    }

    func selectSource(id: String) {
        guard let source = sourceMap[id] else { return }
        TISSelectInputSource(source)
    }

    // MARK: - Private

    private func startObserving() {
        let callback: CFNotificationCallback = { _, _, _, _, _ in
            // 通知在子线程触发，需要调度到主线程读取当前输入法
            Task { @MainActor in
                // 这里通过 AppState 设置的 onSourceChanged 回调处理
                // callback 本身无法直接引用 self，在注册时通过 userInfo 传递
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { center, observer, name, _, _ in
                NotificationCenter.default.post(name: .inputSourceChanged, object: nil)
            },
            kTISNotifySelectedKeyboardInputSourceChanged as CFString,
            nil,
            .deliverImmediately
        )

        // 通过本地 NotificationCenter 桥接，方便在 MainActor 上处理
        NotificationCenter.default.addObserver(
            forName: .inputSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let currentID = self.currentSourceID
            self.onSourceChanged?(currentID)
        }
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

extension Notification.Name {
    static let inputSourceChanged = Notification.Name("InputSourceChanged")
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 InputSourceService — TIS API 输入法枚举、切换、变化监听
```

---

### Task 6: EventDetectorService

**Files:**
- Create: `InputLock/Services/EventDetectorService.swift`

- [ ] **Step 1: 创建服务和实现**

创建 `InputLock/Services/EventDetectorService.swift`：

```swift
import CoreGraphics
import Foundation

protocol EventDetectorService {
    var lastSwitchShortcutTime: Date? { get }
    func startMonitoring()
    func stopMonitoring()
}

@Observable
final class EventDetectorServiceImpl: EventDetectorService {
    var lastSwitchShortcutTime: Date?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func startMonitoring() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // 将 self 指针传给 C 回调
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .listenOnly,
            eventMask,
            eventTapCallback,
            selfPointer
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEventTapEnable(tap, true)
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEventTapEnable(tap, false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }
}

// MARK: - C Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }

    let service = Unmanaged<EventDetectorServiceImpl>.fromOpaque(refcon).takeUnboundedValue()

    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    // 检测输入法切换快捷键
    // Space (keycode 49) + Ctrl
    let isCtrlSpace = keycode == 49 && flags.contains(.maskControl)
    // Caps Lock (keycode 57)
    let isCapsLock = keycode == 57

    if isCtrlSpace || isCapsLock {
        Task { @MainActor in
            service.lastSwitchShortcutTime = Date()
        }
    }

    return Unmanaged.passUnretained(event)
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 EventDetectorService — CGEventTap listen-only 检测切换快捷键
```

---

### Task 7: AppState 核心协调器

**Files:**
- Create: `InputLock/AppState.swift`

- [ ] **Step 1: 创建 AppState**

创建 `InputLock/AppState.swift`：

```swift
import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - 持久化状态
    var isLocked = false
    var lockedSourceID: String?
    var launchAtLoginEnabled = false

    // MARK: - 运行时状态
    var isAuthorized = false
    var availableSources: [InputSource] = []

    // MARK: - 内部标记
    private var isReverting = false

    // MARK: - 服务
    let inputSourceService: InputSourceService
    let eventDetector: EventDetectorService
    let authorizationService: AuthorizationService
    let launchAtLoginService: LaunchAtLoginService

    // MARK: - UserDefaults
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    // MARK: - 常量
    private let switchTimeWindow: TimeInterval = 0.1   // 100ms
    private let revertCooldown: TimeInterval = 0.05     // 50ms

    init(
        inputSourceService: InputSourceService,
        eventDetector: EventDetectorService,
        authorizationService: AuthorizationService,
        launchAtLoginService: LaunchAtLoginService
    ) {
        self.inputSourceService = inputSourceService
        self.eventDetector = eventDetector
        self.authorizationService = authorizationService
        self.launchAtLoginService = launchAtLoginService

        loadPersistedState()
        bindServices()
    }

    // MARK: - 公共方法

    func toggleLock() {
        isLocked.toggle()
        persistState()

        if isLocked {
            // 如果还没选择锁定目标，使用当前输入法
            if lockedSourceID == nil {
                lockedSourceID = inputSourceService.currentSourceID
            }
            eventDetector.startMonitoring()
        } else {
            eventDetector.stopMonitoring()
        }
    }

    func selectSource(id: String) {
        lockedSourceID = id
        persistState()

        if isLocked {
            // 立即切换到选择的输入法
            inputSourceService.selectSource(id: id)
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try launchAtLoginService.disable()
            } else {
                try launchAtLoginService.enable()
            }
            launchAtLoginEnabled.toggle()
            persistState()
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    func startup() {
        // 刷新输入法列表
        inputSourceService.refreshSources()
        availableSources = inputSourceService.availableSources

        // 启动权限监测
        authorizationService.startMonitoring()

        // 如果锁定开启，启动事件检测
        if isLocked {
            eventDetector.startMonitoring()
        }
    }

    // MARK: - 私有方法

    private func bindServices() {
        // 监听权限状态变化
        withObservationTracking {
            _ = authorizationService.isAuthorized
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthorized = self.authorizationService.isAuthorized
            }
        }

        // 监听输入法变化
        inputSourceService.onSourceChanged = { [weak self] newSourceID in
            Task { @MainActor in
                self?.handleSourceChanged(newSourceID: newSourceID)
            }
        }
    }

    private func handleSourceChanged(newSourceID: String) {
        guard isLocked, let targetID = lockedSourceID else { return }

        // 回退中 → 忽略
        if isReverting { return }

        // 已经是目标输入法 → 忽略
        if newSourceID == targetID { return }

        // 检查是否为用户主动切换
        if let lastTime = eventDetector.lastSwitchShortcutTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < switchTimeWindow {
                // 用户主动切换 → 更新锁定目标
                lockedSourceID = newSourceID
                persistState()
                return
            }
        }

        // 系统自动切换 → 回退
        revert(to: targetID)
    }

    private func revert(to targetID: String) {
        isReverting = true
        inputSourceService.selectSource(id: targetID)

        // 冷却后二次检查
        DispatchQueue.main.asyncAfter(deadline: .now() + revertCooldown) { [weak self] in
            guard let self else { return }
            self.isReverting = false

            let currentID = self.inputSourceService.currentSourceID
            if currentID != targetID {
                // 仍然不是目标，再切一次
                self.revert(to: targetID)
            }
        }
    }

    // MARK: - 持久化

    private func loadPersistedState() {
        isLocked = defaults.bool(forKey: "isLocked")
        lockedSourceID = defaults.string(forKey: "lockedSourceID")
        launchAtLoginEnabled = defaults.bool(forKey: "launchAtLogin")
    }

    private func persistState() {
        defaults.set(isLocked, forKey: "isLocked")
        defaults.set(lockedSourceID, forKey: "lockedSourceID")
        defaults.set(launchAtLoginEnabled, forKey: "launchAtLogin")
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 AppState — 全局状态协调、锁定逻辑、竞争处理、持久化
```

---

### Task 8: MenuBarView

**Files:**
- Create: `InputLock/Views/MenuBarView.swift`

- [ ] **Step 1: 创建菜单视图**

创建 `InputLock/Views/` 目录，然后创建 `InputLock/Views/MenuBarView.swift`：

```swift
import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // 锁定开关
        Button {
            appState.toggleLock()
        } label: {
            if appState.isLocked {
                Label("输入法锁定: 开启", systemImage: "lock.fill")
            } else {
                Label("输入法锁定: 关闭", systemImage: "lock.open.fill")
            }
        }

        Divider()

        // 输入法选择子菜单
        Menu("选择锁定输入法") {
            ForEach(appState.availableSources) { source in
                Button {
                    appState.selectSource(id: source.id)
                } label: {
                    HStack {
                        if appState.lockedSourceID == source.id {
                            Image(systemName: "checkmark")
                        }
                        Text(source.name)
                    }
                }
            }
        }
        .disabled(appState.availableSources.isEmpty)

        Divider()

        // 登录启动
        Toggle("登录时自动启动", isOn: Binding(
            get: { appState.launchAtLoginEnabled },
            set: { _ in appState.toggleLaunchAtLogin() }
        ))

        Divider()

        // 关于
        Button("关于 InputLock") {
            openWindow(id: "about")
        }

        // 退出
        Button("退出 InputLock") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 MenuBarView — 菜单栏下拉菜单 UI
```

---

### Task 9: OnboardingView

**Files:**
- Create: `InputLock/Views/OnboardingView.swift`

- [ ] **Step 1: 创建授权引导视图**

创建 `InputLock/Views/OnboardingView.swift`：

```swift
import SwiftUI

struct OnboardingView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("欢迎使用 InputLock")
                .font(.title2.bold())

            Text("InputLock 需要辅助功能权限才能检测输入法变化。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("点击下方按钮打开系统设置", systemImage: "1.circle")
                Label("在辅助功能列表中找到 InputLock", systemImage: "2.circle")
                Label("勾选启用", systemImage: "3.circle")
            }
            .font(.callout)
            .padding()
            .background(.quaternary, in: .rect(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("打开系统设置") {
                    appState.authorizationService.openSystemPreferences()
                }
                .buttonStyle(.borderedProminent)

                Button("稍后设置") {
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 OnboardingView — 首次启动授权引导窗口
```

---

### Task 10: AboutView

**Files:**
- Create: `InputLock/Views/AboutView.swift`

- [ ] **Step 1: 创建关于窗口**

创建 `InputLock/Views/AboutView.swift`：

```swift
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("InputLock")
                .font(.title2.bold())

            Text("版本 \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Copyright © 2026 awsl1414")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("关闭") {
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 280)
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```
feat: 添加 AboutView — 关于窗口
```

---

### Task 11: InputLockApp 入口 — 组装

**Files:**
- Modify: `InputLock/InputLockApp.swift`

- [ ] **Step 1: 重写应用入口**

替换 `InputLock/InputLockApp.swift` 全部内容：

```swift
import SwiftUI

@main
struct InputLockApp: App {
    @State private var appState: AppState

    init() {
        let auth = AuthorizationServiceImpl()
        let launch = LaunchAtLoginServiceImpl()
        let inputSource = InputSourceServiceImpl()
        let eventDetector = EventDetectorServiceImpl()

        let state = AppState(
            inputSourceService: inputSource,
            eventDetector: eventDetector,
            authorizationService: auth,
            launchAtLoginService: launch
        )
        _appState = State(wrappedValue: state)
    }

    var body: some Scene {
        // 菜单栏
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label("InputLock", systemImage: appState.isAuthorized
                ? (appState.isLocked ? "lock.fill" : "lock.open.fill")
                : "lock.slash.fill")
        }

        // 授权引导窗口
        Window("InputLock 需要授权", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // 关于窗口
        Window("关于 InputLock", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
```

- [ ] **Step 2: 验证构建**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 手动测试**

1. 在 Xcode 中 Run 应用
2. 确认菜单栏出现图标（无 Dock 图标）
3. 确认首次启动弹出授权引导窗口
4. 点击菜单栏图标确认菜单结构正确
5. 确认"关于"和"退出"功能正常

- [ ] **Step 4: 提交**

```
feat: 组装应用入口 — MenuBarExtra + 授权引导 + 关于窗口
```

---

### Task 12: 集成验证与文档更新

**Files:**
- Modify: `docs/TECH_STACK.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: 更新 CLAUDE.md Architecture 部分**

将 Architecture 中的 `通过 WindowGroup 管理主窗口` 替换为实际的架构描述。

- [ ] **Step 2: 更新 TECH_STACK.md 架构图**

将 `EventTapManager` 替换为 `EventDetectorService`，确保与实际代码一致。

- [ ] **Step 3: 全量构建验证**

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Release build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```
docs: 更新技术栈和项目文档，反映实际实现
```
