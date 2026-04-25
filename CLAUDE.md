# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**InputLock** — macOS 原生输入法锁定工具，防止系统自动切换输入法，放行用户主动切换。详细需求见 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)，技术栈规划见 [docs/TECH_STACK.md](docs/TECH_STACK.md)，版本变更记录见 [docs/CHANGELOG.md](docs/CHANGELOG.md)。

## Build & Run

```bash
# 构建 (Debug)
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build

# 构建 (Release)
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Release build
```

也可直接用 Xcode 打开 `InputLock.xcodeproj` 进行构建和调试。

## Project Configuration

- **语言**: Swift 5.0, SwiftUI
- **最低部署目标**: macOS 14.0
- **开发 SDK**: macOS 26.4
- **Bundle Identifier**: `awsl1414.InputLock`
- **Development Team**: WT93YXK94X
- **App Sandbox**: 已关闭（TIS API 和 CGEventTap 需要系统级权限）
- **Hardened Runtime**: 已启用
- **Swift 并发**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`SWIFT_APPROACHABLE_CONCURRENCY = YES`
- **MEMBER_IMPORT_VISIBILITY**: 已关闭（Carbon TIS 不在 umbrella header 中）

## Architecture

项目使用 Xcode 的 `PBXFileSystemSynchronizedRootGroup`，`InputLock/` 目录下的源文件会自动同步到 Xcode 项目中，无需手动在 pbxproj 中添加文件引用。

```
InputLock/
├── InputLockApp.swift          — @main 入口，MenuBarExtra + Window 定义
├── AppState.swift              — @Observable 中心状态，锁定逻辑
├── Models/
│   └── InputSource.swift       — 输入法值类型 (id, name)
├── Services/
│   ├── InputSourceService.swift    — TIS API：枚举/切换/监听输入法变化
│   ├── EventDetectorService.swift  — CGEventTap listen-only：检测快捷键时间戳
│   ├── AuthorizationService.swift  — AXIsProcessTrusted 权限轮询
│   └── LaunchAtLoginService.swift  — SMAppService 登录项管理
├── Views/
│   ├── MenuBarView.swift       — 菜单栏下拉菜单
│   ├── OnboardingView.swift    — 首次启动授权引导
│   └── AboutView.swift         — 关于窗口
└── Extensions/
    └── Notification+Names.swift — 全局 Notification.Name 统一定义
```

### 数据流

```
InputLockApp (@main)
  └── MenuBarExtra (SwiftUI)
        └── AppState (@Observable) — 视图唯一数据源
              ├── InputSourceService
              │     ├── TISCreateInputSourceList(nil, false) — 仅用户已启用的输入法
              │     ├── TISSelectInputSource() — 切换输入法（缓存未命中时自动刷新）
              │     └── Darwin notification → NotificationCenter → onSourceChanged 回调
              ├── EventDetectorService
              │     ├── CGEvent.tapCreate(.cgSessionEventTap, .listenOnly)
              │     ├── 监听 keyDown + flagsChanged 事件
              │     ├── 检测 Ctrl+Space (keycode 49) 和 Caps Lock (keycode 57)
              │     ├── tap 被系统禁用时自动重新启用
              │     └── isMonitoring 状态跟踪
              ├── AuthorizationService
              │     ├── AXIsProcessTrusted() 轮询 (1s 间隔)
              │     └── MainActor.assumeIsolated 调用
              └── LaunchAtLoginService
                    └── SMAppService.mainApp — 实际状态驱动，不依赖 UserDefaults 缓存
```

### 锁定机制

监听输入法变化 → 时间戳窗口区分来源 → 系统切换时自动回退（最多重试 5 次，间隔 50ms）

## Key Technical Decisions

- **零外部依赖** — 仅使用 Apple 系统 SDK
- **检测并回退** — 不拦截键盘事件，通过 Darwin notification 监听输入法变化，识别系统自动切换并立即切回
- **CGEventTap listen-only** — 仅用于记录快捷键时间戳，不阻断用户按键
- **关闭 App Sandbox** — `TISSelectInputSource()` 和 CGEventTap 在沙盒下不可用
- **关闭 MEMBER_IMPORT_VISIBILITY** — Carbon TIS 的 TextInputSources.h 不在 umbrella header 中
- **MainActor 默认隔离** — 全局 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，避免并发问题
- **@Observable** — 使用 Observation 框架 (macOS 14+) 替代 ObservableObject
- **服务协议 + Impl 实现** — 所有服务通过协议定义，便于测试和替换
- **服务属性 private(set)** — AppState 对外只暴露必要的公共方法，内部服务不可外部修改
- **UserDefaults 仅存 isLocked/lockedSourceID/launchAtLogin** — 启动项实际状态由 SMAppService 驱动

## Code Conventions

- 使用简体中文编写用户可见的 UI 文案
- 源文件采用标准 Swift 命名规范（大驼峰类型，小驼峰方法/属性）
- 协议定义与实现在同一文件中，实现类以 `Impl` 后缀命名
- 避免魔术数字，使用命名常量或枚举（如 `EventDetectorKeycode`）
- 禁止在全局散布 `Notification.Name` 扩展，统一放在 `Extensions/Notification+Names.swift`
- CFType 桥接使用 `CFArrayGetCount`/`CFArrayGetValueAtIndex`/`unsafeBitCast`，不依赖 `as!` 强转

## Development Principles

- **现代 macOS 开发准则** — 严格遵循 Apple 最新设计规范和开发最佳实践，以 macOS 26 SDK 为基准
- **一致性** — UI 风格、交互模式、代码结构、命名方式全局保持一致
- **合理设计** — 类型职责清晰，层次分明，避免过度抽象也不过度耦合；每个模块只做一件事
- **防御性编程** — 关键路径添加重试上限（如 revert 最多 5 次）、资源清理（如 deinit 移除 observer）、权限前置检查（如 AXIsProcessTrusted）
