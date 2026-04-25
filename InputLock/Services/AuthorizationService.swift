import AppKit
import ApplicationServices

protocol AuthorizationService {
    var isAuthorized: Bool { get }
    func openSystemPreferences()
    func startMonitoring()
}

@Observable
final class AuthorizationServiceImpl: AuthorizationService {
    var isAuthorized = false

    private let pollInterval: TimeInterval = 1.0
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
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
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
