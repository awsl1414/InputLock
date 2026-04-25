import Carbon
import Foundation

protocol InputSourceService {
    var availableSources: [InputSource] { get }
    var currentSourceID: String { get }
    var onSourceChanged: (@MainActor (String) -> Void)? { get set }
    func selectSource(id: String)
    func refreshSources()
}

@Observable
final class InputSourceServiceImpl: InputSourceService {
    private(set) var availableSources: [InputSource] = []
    private var sourceMap: [String: TISInputSource] = [:]

    var onSourceChanged: (@MainActor (String) -> Void)?

    var currentSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        return propertyString(source, kTISPropertyInputSourceID) ?? ""
    }

    init() {
        refreshSources()
        startObserving()
    }

    func refreshSources() {
        guard let sources = TISCopyAvailableKeyboardInputSources()?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        var newSources: [InputSource] = []
        var newMap: [String: TISInputSource] = [:]

        for source in sources {
            guard let category = propertyString(source, kTISPropertyInputSourceCategory),
                  category == kTISCategoryKeyboardInputSource as String else { continue }
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let isSelectable = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
            guard isSelectable else { continue }

            guard let id = propertyString(source, kTISPropertyInputSourceID),
                  let name = propertyString(source, kTISPropertyLocalizedName) else { continue }

            newSources.append(InputSource(id: id, name: name))
            newMap[id] = source
        }

        sourceMap = newMap
        availableSources = newSources
    }

    func selectSource(id: String) {
        guard let source = sourceMap[id] else { return }
        TISSelectInputSource(source)
    }

    // MARK: - Private

    private func startObserving() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { center, observer, name, _, _ in
                NotificationCenter.default.post(name: .inputSourceChanged, object: nil)
            },
            kTISNotifySelectedKeyboardInputSourceChanged as CFString,
            nil,
            .deliverImmediately
        )

        NotificationCenter.default.addObserver(
            forName: .inputSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let currentID = self.currentSourceID
            Task { @MainActor in
                self.onSourceChanged?(currentID)
            }
        }
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

extension Notification.Name {
    static let inputSourceChanged = Notification.Name("InputSourceChanged")
}
