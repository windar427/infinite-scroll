import AppKit
import WebKit

class ExcalidrawViewRegistry {
    static let shared = ExcalidrawViewRegistry()
    private var views: [UUID: WKWebView] = [:]
    private let lock = NSLock()

    private init() {}

    func register(id: UUID, view: WKWebView) {
        lock.lock()
        views[id] = view
        lock.unlock()
    }

    func unregister(id: UUID) {
        lock.lock()
        views.removeValue(forKey: id)
        lock.unlock()
    }

    func view(for id: UUID) -> WKWebView? {
        lock.lock()
        defer { lock.unlock() }
        return views[id]
    }

    func focus(id: UUID) {
        lock.lock()
        let view = views[id]
        lock.unlock()
        if let view = view {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                scrollRowToVisible(view)
            }
        }
    }
}
