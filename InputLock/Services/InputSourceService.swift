import Carbon
import Foundation

protocol InputSourceService {
    var availableSources: [InputSource] { get }
    var currentSourceID: String { get }
    var onSourceChanged: ((String) -> Void)? { get set }
    func selectSource(id: String)
    func refreshSources()
}

@Observable
final class InputSourceServiceImpl: InputSourceService {
    private(set) var availableSources: [InputSource] = []
    private var sourceMap: [String: TISInputSource] = [:]
    private var localObserver: NSObjectProtocol?

    var onSourceChanged: ((String) -> Void)?

    var currentSourceID: String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        return propertyString(source, kTISPropertyInputSourceID) ?? ""
    }

    init() {
        refreshSources()
        startObserving()
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged as CFString),
            nil
        )
        if let localObserver {
            NotificationCenter.default.removeObserver(localObserver)
        }
    }

    func refreshSources() {
        guard let rawResult = TISCreateInputSourceList(nil, false) else {
            return
        }
        let cfArray = rawResult.takeRetainedValue()
        let count = CFArrayGetCount(cfArray)

        var newSources: [InputSource] = []
        var newMap: [String: TISInputSource] = [:]

        for i in 0..<count {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(cfArray, i), to: TISInputSource.self)

            guard let category = propertyString(source, kTISPropertyInputSourceCategory),
                  category == kTISCategoryKeyboardInputSource as String else { continue }
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { continue }
            let isEnabled = CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
            guard isEnabled else { continue }

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
        if let source = sourceMap[id] {
            TISSelectInputSource(source)
            return
        }
        refreshSources()
        if let source = sourceMap[id] {
            TISSelectInputSource(source)
        }
    }

    // MARK: - Private

    private func startObserving() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                NotificationCenter.default.post(name: .inputSourceChanged, object: nil)
            },
            kTISNotifySelectedKeyboardInputSourceChanged as CFString,
            nil,
            .deliverImmediately
        )

        localObserver = NotificationCenter.default.addObserver(
            forName: .inputSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let currentID = self.currentSourceID
            self.onSourceChanged?(currentID)
        }
    }

    private func propertyString(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
