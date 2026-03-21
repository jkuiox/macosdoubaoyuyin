import Cocoa

class KeyMonitor {
    var onRecordingStateChanged: ((Bool) -> Void)?
    private var flagsMonitor: Any?
    private var isFnPressed = false

    func start() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor local events (when our own windows are focused)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)

        if fnPressed && !isFnPressed {
            isFnPressed = true
            onRecordingStateChanged?(true)
        } else if !fnPressed && isFnPressed {
            isFnPressed = false
            onRecordingStateChanged?(false)
        }
    }

    func stop() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    deinit {
        stop()
    }
}
