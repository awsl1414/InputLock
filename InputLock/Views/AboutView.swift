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
