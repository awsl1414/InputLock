import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var onboardingObserver: NSObjectProtocol?

    var body: some View {
        Button {
            if appState.isAuthorized {
                appState.toggleLock()
            } else {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            if !appState.isAuthorized {
                Label("输入法锁定: 未授权", systemImage: "lock.slash.fill")
            } else if appState.isLocked {
                Label("输入法锁定: 开启", systemImage: "lock.fill")
            } else {
                Label("输入法锁定: 关闭", systemImage: "lock.open.fill")
            }
        }
        .onAppear {
            guard onboardingObserver == nil else { return }
            onboardingObserver = NotificationCenter.default.addObserver(
                forName: .showOnboarding,
                object: nil,
                queue: .main
            ) { _ in
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

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

        Toggle("登录时自动启动", isOn: Binding(
            get: { appState.launchAtLoginEnabled },
            set: { newValue in
                guard newValue != appState.launchAtLoginEnabled else { return }
                appState.toggleLaunchAtLogin()
            }
        ))

        Divider()

        Button("关于") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}
