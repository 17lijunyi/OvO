import AppKit
import ApplicationServices

@MainActor
final class SelectionService {
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var isCapturing = false

    init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApplication = frontmost
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor [weak self] in
                self?.lastExternalApplication = application
            }
        }
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func captureSelectedText() async throws -> String {
        try Task.checkCancellation()
        guard Self.hasAccessibilityPermission else { throw PlatformError.accessibilityPermissionRequired }
        guard !isCapturing else { throw PlatformError.copyUnavailable }
        isCapturing = true
        defer { isCapturing = false }

        let originalApplication = NSWorkspace.shared.frontmostApplication
        let sourceApplication: NSRunningApplication?
        if let originalApplication,
           originalApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            sourceApplication = originalApplication
        } else {
            sourceApplication = lastExternalApplication
        }
        guard let sourceApplication, !sourceApplication.isTerminated else {
            throw PlatformError.noSourceApplication
        }

        let applicationElement = AXUIElementCreateApplication(sourceApplication.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 1)
        let focusedElement = copyElementAttribute(kAXFocusedUIElementAttribute, from: applicationElement)

        if let focusedElement {
            if copyStringAttribute(kAXSubroleAttribute, from: focusedElement) == kAXSecureTextFieldSubrole as String {
                throw PlatformError.secureTextField
            }
            if let text = selectedText(from: focusedElement) {
                return text
            }
        }
        // Some apps (including custom web renderers) expose selection on the app itself.
        if let text = selectedText(from: applicationElement) {
            return text
        }

        let text = try await copySelection(from: sourceApplication, originalApplication: originalApplication)
        try Task.checkCancellation()
        return text
    }

    private func selectedText(from element: AXUIElement) -> String? {
        if let selected = copyStringAttribute(kAXSelectedTextAttribute, from: element),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(rangeValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.length > 0 else { return nil }

        var selectedValue: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            value,
            &selectedValue
        ) == .success,
           let selected = selectedValue as? String,
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        // AX ranges use UTF-16 indices, as does NSString.
        guard let fullText = copyStringAttribute(kAXValueAttribute, from: element) else { return nil }
        let string = fullText as NSString
        guard range.location >= 0, range.length > 0,
              range.location <= string.length,
              range.length <= string.length - range.location else { return nil }
        let selected = string.substring(with: NSRange(location: range.location, length: range.length))
        return selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selected
    }

    private func copySelection(
        from application: NSRunningApplication,
        originalApplication: NSRunningApplication?
    ) async throws -> String {
        let switchedApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier
        defer {
            if switchedApplication, let originalApplication,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                originalApplication.activate(options: [])
            }
        }
        if switchedApplication {
            if originalApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                NSApplication.shared.yieldActivation(to: application)
            }
            guard application.activate(options: []) else {
                throw PlatformError.noSourceApplication
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw PlatformError.copyUnavailable
        }

        guard let eventSource = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 8, keyDown: false) else {
            throw PlatformError.copyUnavailable
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        return try await SelectionClipboardTransaction.capture(
            clipboard: SystemSelectionClipboard(),
            isSourceFrontmost: {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
            },
            sendCopy: {
                keyDown.postToPid(application.processIdentifier)
                keyUp.postToPid(application.processIdentifier)
            },
            waitForCopy: {
                // Once Copy is sent, finish restoring the clipboard before honoring cancellation.
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        continuation.resume()
                    }
                }
            }
        )
    }

    private func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
}

typealias SelectionClipboardContents = [[NSPasteboard.PasteboardType: Data]]

@MainActor
protocol SelectionClipboard: AnyObject {
    var changeCount: Int { get }
    func readContents() throws -> SelectionClipboardContents
    func readText() -> String?
    func restore(_ contents: SelectionClipboardContents)
}

@MainActor
private final class SystemSelectionClipboard: SelectionClipboard {
    private let pasteboard = NSPasteboard.general
    var changeCount: Int { pasteboard.changeCount }

    func readContents() throws -> SelectionClipboardContents {
        try (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // Dropping an unavailable representation would corrupt the restored clipboard.
                guard let data = item.data(forType: type) else { throw PlatformError.clipboardUnavailable }
                representations[type] = data
            }
            return representations
        }
    }

    func readText() -> String? { pasteboard.string(forType: .string) }

    func restore(_ contents: SelectionClipboardContents) {
        pasteboard.clearContents()
        let restored = contents.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

/// A bounded copy transaction, independent of the real clipboard for regression tests.
@MainActor
enum SelectionClipboardTransaction {
    static func capture(
        clipboard: any SelectionClipboard,
        isSourceFrontmost: () -> Bool,
        sendCopy: () throws -> Void,
        waitForCopy: () async -> Void,
        maximumAttempts: Int = 20
    ) async throws -> String {
        try Task.checkCancellation()
        let originalCount = clipboard.changeCount
        let contents = try clipboard.readContents()
        guard clipboard.changeCount == originalCount else { throw PlatformError.clipboardUnavailable }
        guard isSourceFrontmost() else { throw PlatformError.copyUnavailable }
        try Task.checkCancellation()

        var copiedCount: Int?
        defer {
            // Never overwrite a clipboard change made after the text we actually accepted.
            if let copiedCount, clipboard.changeCount == copiedCount {
                clipboard.restore(contents)
            }
        }
        try sendCopy()
        for _ in 0..<max(0, maximumAttempts) {
            await waitForCopy()
            guard isSourceFrontmost() else { throw PlatformError.copyUnavailable }
            let observedCount = clipboard.changeCount
            guard observedCount != originalCount else { continue }
            let text = clipboard.readText()
            // A lazy data provider may replace the clipboard while readText is resolving.
            guard clipboard.changeCount == observedCount else { throw PlatformError.copyUnavailable }
            copiedCount = observedCount
            try Task.checkCancellation()
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlatformError.noSelectedText
            }
            return text
        }
        try Task.checkCancellation()
        throw PlatformError.noSelectedText
    }
}
