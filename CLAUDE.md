# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**InputLock** — macOS 原生输入法锁定工具。详细需求见 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)，技术栈规划见 [docs/TECH_STACK.md](docs/TECH_STACK.md)。

## Build & Run

```bash
# 使用 xcodebuild 构建 (Debug)
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Debug build

# 使用 xcodebuild 构建 (Release)
xcodebuild -project InputLock.xcodeproj -scheme InputLock -configuration Release build

# 运行测试
xcodebuild -project InputLock.xcodeproj -scheme InputLock test
```

也可直接用 Xcode 打开 `InputLock.xcodeproj` 进行构建和调试。

## Project Configuration

- **语言**: Swift 5.0, SwiftUI
- **最低部署目标**: macOS 26.4
- **Bundle Identifier**: `awsl1414.InputLock`
- **Development Team**: WT93YXK94X
- **Xcode 版本**: 26.4.1 (objectVersion 77)
- **App Sandbox**: 已关闭（TIS API 和全局输入法监听需要系统级权限）
- **Hardened Runtime**: 已启用
- **Swift 并发**: `SWIFT_APPROACHABLE_CONCURRENCY` 和 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 已启用

## Architecture

项目使用 Xcode 的 `PBXFileSystemSynchronizedRootGroup`，`InputLock/` 目录下的源文件会自动同步到 Xcode 项目中，无需手动在 pbxproj 中添加文件引用。

当前为 SwiftUI App 生命周期模式（`@main` 标记的 `App` 结构体），通过 `WindowGroup` 管理主窗口。

## Key Technical Decisions

- **零外部依赖** — 仅使用 Apple 系统 SDK
- **锁定机制：检测并回退** — 监听输入法变化通知，识别系统自动切换并立即切回；用户主动切换则放行并更新锁定目标
- **不拦截键盘事件** — 不阻断用户快捷键，与 CGEventTap 拦截方案有本质区别
- **关闭 App Sandbox** — `TISSelectInputSource()` 和全局输入法变化监听在沙盒下不可用，必须关闭
- **Swift 6 Strict Concurrency** — 默认 MainActor 隔离，使用 @Observable 替代 ObservableObject
- **MenuBarExtra** — SwiftUI 原生菜单栏 API，无需主窗口

## Code Conventions

- 使用简体中文编写用户可见的注释
- 源文件采用标准 Swift 命名规范（大驼峰用于类型，小驼峰用于方法和属性）
- SwiftUI 视图放在 `InputLock/` 目录下，Xcode 会自动识别

## Development Principles

- **现代 macOS 开发准则** — 严格遵循 Apple 最新设计规范和开发最佳实践，以 macOS 26 SDK 为基准，不兼容旧版 API
- **一致性** — UI 风格、交互模式、代码结构、命名方式全局保持一致，与系统原生应用体验对齐
- **合理设计** — 类型职责清晰，层次分明，避免过度抽象也不过度耦合；每个模块只做一件事
