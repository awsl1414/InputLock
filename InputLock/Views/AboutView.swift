import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    @State private var updateState: UpdateState = .idle
    @State private var updateInfo: UpdateInfo?
    @State private var showReleaseNotes = false
    @State private var updateService: UpdateService = UpdateServiceImpl()
    @Environment(\.dismiss) private var dismiss

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

            updateSection

            Text("Copyright © 2026 awsl1414")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 280)
        .sheet(isPresented: $showReleaseNotes) {
            if let info = updateInfo {
                ReleaseNotesView(notes: info.releaseNotes, version: info.version)
            }
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updateState {
        case .idle:
            Button("检查更新") {
                checkForUpdates()
            }
            .buttonStyle(.bordered)

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            Text("已是最新版本")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .available:
            VStack(spacing: 8) {
                Text("发现新版本 \(updateInfo?.version ?? "")")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Button("查看更新日志") {
                        showReleaseNotes = true
                    }
                    .buttonStyle(.bordered)

                    Button("前往更新") {
                        if let url = updateInfo?.releaseURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .failed:
            Button("检查失败，点击重试") {
                checkForUpdates()
            }
            .buttonStyle(.bordered)
        }
    }

    private func checkForUpdates() {
        updateState = .checking
        Task {
            guard let info = await updateService.fetchLatestRelease() else {
                updateState = .failed
                return
            }
            updateInfo = info
            updateState = updateService.isNewer(info.version) ? .available : .upToDate
        }
    }
}
