import Foundation

struct UpdateInfo: Sendable {
    let version: String
    let releaseNotes: String
    let releaseURL: URL
}
