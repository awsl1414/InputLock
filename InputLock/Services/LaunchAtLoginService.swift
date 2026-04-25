import Foundation
import ServiceManagement

protocol LaunchAtLoginService {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

@Observable
final class LaunchAtLoginServiceImpl: LaunchAtLoginService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
