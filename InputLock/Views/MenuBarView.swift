import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
            set: { _ in appState.toggleLaunchAtLogin() }
        ))

        Divider()

        Button("关于 InputLock") {
            openWindow(id: "about")
        }

        Button("退出 InputLock") {
            NSApplication.shared.terminate(nil)
        }
    }
}
