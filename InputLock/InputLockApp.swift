import SwiftUI

@main
struct InputLockApp: App {
    @State private var appState: AppState
    @Environment(\.openWindow) private var openWindow

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
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label("InputLock", systemImage: appState.isAuthorized
                ? (appState.isLocked ? "lock.fill" : "lock.open.fill")
                : "lock.slash.fill")
        }

        Window("InputLock 需要授权", id: "onboarding") {
            OnboardingView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("关于 InputLock", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
