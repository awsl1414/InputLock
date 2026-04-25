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
