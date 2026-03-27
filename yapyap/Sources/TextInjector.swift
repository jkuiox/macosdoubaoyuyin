import Cocoa
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "cn.skyrin.yapyap", category: "TextInjector")

enum TextInjector {
    private struct AXSession {
        let element: AXUIElement
        let insertionLocation: Int
        var replacementLength: Int
        var injectedText = ""
    }

    private static var axSession: AXSession?
    private static var fallbackText = ""
    private static let queue = DispatchQueue(label: "cn.skyrin.yapyap.textinjector")

    /// Use the system trust API. If not trusted, optionally prompt.
    static func checkAccessibility(promptIfNeeded: Bool = true) -> Bool {
        if AXIsProcessTrusted() {
            logger.info("Accessibility trusted: true")
            return true
        }

        logger.info("Accessibility trusted: false")
        if promptIfNeeded {
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
        }
        return false
    }

    /// Reset state at the beginning of a recording session.
    /// Capture the focused control once so streaming updates keep replacing the
    /// same insertion range instead of chasing focus while ASR revises text.
    static func reset() {
        queue.sync {
            fallbackText = ""
            axSession = captureAXSession()
        }
    }

    /// Delete all injected text and reset state.
    static func clear() {
        update(fullText: "")
    }

    /// Update the text at cursor to match the new full text from ASR.
    /// Prefer direct AX replacement. Fall back to keyboard events only when the
    /// focused control does not expose a writable text value/range.
    static func update(fullText: String) {
        queue.sync {
            if replaceViaAccessibility(fullText: fullText) {
                return
            }

            updateViaKeyboardFallback(fullText: fullText)
        }
    }

    private static func captureAXSession() -> AXSession? {
        guard checkAccessibility(promptIfNeeded: false) else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        guard let element = copyElementAttribute(systemWide, attribute: kAXFocusedUIElementAttribute) else {
            logger.info("Focused UI element not available; falling back to keyboard injection")
            return nil
        }

        guard let value = copyStringAttribute(element, attribute: kAXValueAttribute),
              let selectedRange = copySelectedRange(from: element) else {
            let role = copyStringAttribute(element, attribute: kAXRoleAttribute) ?? "unknown"
            logger.info("Focused element role=\(role, privacy: .public) does not expose writable value/range; falling back to keyboard injection")
            return nil
        }

        let stringLength = (value as NSString).length
        let insertionLocation = max(0, min(selectedRange.location, stringLength))
        let replacementLength = max(0, min(selectedRange.length, stringLength - insertionLocation))
        let role = copyStringAttribute(element, attribute: kAXRoleAttribute) ?? "unknown"
        logger.info("Captured AX text target role=\(role, privacy: .public), location=\(insertionLocation), selectionLength=\(replacementLength)")

        return AXSession(
            element: element,
            insertionLocation: insertionLocation,
            replacementLength: replacementLength
        )
    }

    private static func replaceViaAccessibility(fullText: String) -> Bool {
        guard var session = axSession else { return false }
        guard let currentValue = copyStringAttribute(session.element, attribute: kAXValueAttribute) else {
            logger.info("AX target no longer has readable value; switching to keyboard fallback")
            axSession = nil
            return false
        }

        let currentNSString = currentValue as NSString
        let safeLocation = max(0, min(session.insertionLocation, currentNSString.length))
        let safeLength = max(0, min(session.replacementLength, currentNSString.length - safeLocation))
        let replacementRange = NSRange(location: safeLocation, length: safeLength)

        let nextValue = currentNSString.replacingCharacters(in: replacementRange, with: fullText)
        let setValueResult = AXUIElementSetAttributeValue(
            session.element,
            kAXValueAttribute as CFString,
            nextValue as CFTypeRef
        )
        guard setValueResult == .success else {
            logger.info("AX value write failed with code \(setValueResult.rawValue); switching to keyboard fallback")
            axSession = nil
            return false
        }

        var caret = CFRange(location: safeLocation + (fullText as NSString).length, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &caret) {
            let selectionResult = AXUIElementSetAttributeValue(
                session.element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
            if selectionResult != .success {
                logger.debug("AX caret update failed with code \(selectionResult.rawValue)")
            }
        }

        session.replacementLength = (fullText as NSString).length
        session.injectedText = fullText
        axSession = session
        fallbackText = fullText
        logger.info("Inserted text via AX: \"\(fullText, privacy: .public)\"")
        return true
    }

    private static func updateViaKeyboardFallback(fullText: String) {
        let oldText = fallbackText
        let commonPrefix = String(zip(oldText, fullText).prefix(while: { $0 == $1 }).map(\.0))
        let charsToDelete = oldText.count - commonPrefix.count
        let newChars = String(fullText.dropFirst(commonPrefix.count))

        if charsToDelete == 0 && newChars.isEmpty { return }

        logger.info("Keyboard fallback: delete=\(charsToDelete), insert=\"\(newChars, privacy: .public)\" (old=\"\(oldText, privacy: .public)\" -> new=\"\(fullText, privacy: .public)\")")

        if charsToDelete > 0 {
            sendBackspaces(count: charsToDelete)
        }

        if charsToDelete > 0 && !newChars.isEmpty {
            usleep(10_000)
        }

        if !newChars.isEmpty {
            sendText(newChars)
        }

        fallbackText = fullText
    }

    private static func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func copySelectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = axValue as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func sendBackspaces(count: Int) {
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_LeftArrow), keyDown: true)
            keyDown?.flags = .maskShift
            keyDown?.post(tap: .cgSessionEventTap)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_LeftArrow), keyDown: false)
            keyUp?.flags = .maskShift
            keyUp?.post(tap: .cgSessionEventTap)
            usleep(1_000)
        }

        usleep(5_000)

        let delDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_Delete), keyDown: true)
        delDown?.post(tap: .cgSessionEventTap)
        let delUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_Delete), keyDown: false)
        delUp?.post(tap: .cgSessionEventTap)
    }

    private static func sendText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let backup = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let vDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cgSessionEventTap)
        let vUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cgSessionEventTap)

        usleep(50_000)

        pasteboard.clearContents()
        if let backup {
            pasteboard.setString(backup, forType: .string)
        }
    }
}
