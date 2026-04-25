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
    var inputSourceService: InputSourceService
    let eventDetector: EventDetectorService
    let authorizationService: AuthorizationService
    let launchAtLoginService: LaunchAtLoginService

    // MARK: - UserDefaults
    @ObservationIgnored
    private let defaults = UserDefaults.standard

    // MARK: - 常量
    private let switchTimeWindow: TimeInterval = 0.1
    private let revertCooldown: TimeInterval = 0.05

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
        if !isLocked && !isAuthorized {
            return
        }

        isLocked.toggle()
        persistState()

        if isLocked {
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
        inputSourceService.refreshSources()
        availableSources = inputSourceService.availableSources
        isAuthorized = authorizationService.isAuthorized
        authorizationService.startMonitoring()

        if !isAuthorized {
            NotificationCenter.default.post(name: .showOnboarding, object: nil)
        }

        if isLocked && isAuthorized {
            eventDetector.startMonitoring()
        }
    }

    // MARK: - 私有方法

    private func bindServices() {
        // 监听权限状态变化
        // withObservationTracking fires once then stops, so we re-establish
        // tracking in the onChange handler to keep observing continuously.
        observeAuthorization()

        // 监听输入法变化
        inputSourceService.onSourceChanged = { [weak self] newSourceID in
            Task { @MainActor in
                self?.handleSourceChanged(newSourceID: newSourceID)
            }
        }
    }

    private func observeAuthorization() {
        withObservationTracking {
            _ = authorizationService.isAuthorized
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthorized = self.authorizationService.isAuthorized
                // Re-establish observation tracking for the next change
                self.observeAuthorization()
            }
        }
    }

    private func handleSourceChanged(newSourceID: String) {
        guard isLocked, let targetID = lockedSourceID else { return }

        if isReverting { return }
        if newSourceID == targetID { return }

        if let lastTime = eventDetector.lastSwitchShortcutTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < switchTimeWindow {
                lockedSourceID = newSourceID
                persistState()
                return
            }
        }

        revert(to: targetID)
    }

    private func revert(to targetID: String) {
        isReverting = true
        inputSourceService.selectSource(id: targetID)

        DispatchQueue.main.asyncAfter(deadline: .now() + revertCooldown) { [weak self] in
            guard let self else { return }
            self.isReverting = false

            let currentID = self.inputSourceService.currentSourceID
            if currentID != targetID {
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

extension Notification.Name {
    static let showOnboarding = Notification.Name("ShowOnboarding")
}
