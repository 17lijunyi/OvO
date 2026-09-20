import Carbon
import Foundation

enum HotKeyAction: String, CaseIterable, Identifiable, Hashable {
    case selection
    case input
    case screenshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: return "划词翻译"
        case .input: return "输入翻译"
        case .screenshot: return "截图翻译"
        }
    }

    fileprivate var carbonIdentifier: UInt32 {
        switch self {
        case .selection: return 1
        case .input: return 2
        case .screenshot: return 3
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .selection: return UInt32(kVK_ANSI_D)
        case .input: return UInt32(kVK_ANSI_A)
        case .screenshot: return UInt32(kVK_ANSI_S)
        }
    }

    fileprivate var letter: String {
        switch self {
        case .selection: return "D"
        case .input: return "A"
        case .screenshot: return "S"
        }
    }
}

struct HotKeyRegistrationFailure: Identifiable, LocalizedError {
    let action: HotKeyAction
    let shortcut: String
    let status: OSStatus

    var id: String { action.id }
    var errorDescription: String? {
        "\(action.title)快捷键 \(shortcut) 无法注册（错误 \(status)）。该组合可能已被其他应用占用，请释放占用后重新注册。"
    }
}

/// Carbon hot keys work across applications without monitoring every keystroke.
@MainActor
final class GlobalHotKeyManager {
    private static let signature: OSType = 0x4F564F31 // OVO1
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var eventContext: HotKeyEventContext?
    private let delivery = HotKeyEventDelivery()

    @discardableResult
    func register(
        handler: @escaping (HotKeyAction) -> Void
    ) -> [HotKeyRegistrationFailure] {
        unregisterAll()
        let registrationID = delivery.begin(handler: handler)
        let eventContext = HotKeyEventContext { [weak delivery] identifier in
            delivery?.deliver(identifier: identifier, registrationID: registrationID)
        }
        self.eventContext = eventContext

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == 0x4F564F31 else {
                    return OSStatus(eventNotHandledErr)
                }
                let eventContext = Unmanaged<HotKeyEventContext>.fromOpaque(context).takeUnretainedValue()
                let deliver = eventContext.deliver
                let actionID = identifier.id
                Task { @MainActor in deliver(actionID) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(eventContext).toOpaque(),
            &eventHandler
        )

        guard installStatus == noErr else {
            unregisterAll()
            return HotKeyAction.allCases.map {
                HotKeyRegistrationFailure(
                    action: $0,
                    shortcut: Self.shortcutLabel(for: $0),
                    status: installStatus
                )
            }
        }

        let modifiers = UInt32(controlKey)
        let failures = HotKeyAction.allCases.compactMap { action -> HotKeyRegistrationFailure? in
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                action.keyCode,
                modifiers,
                EventHotKeyID(signature: Self.signature, id: action.carbonIdentifier),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                references.append(reference)
                delivery.allow(action)
                return nil
            }
            return HotKeyRegistrationFailure(
                action: action,
                shortcut: Self.shortcutLabel(for: action),
                status: status
            )
        }
        if references.isEmpty { unregisterAll() }
        return failures
    }

    func unregisterAll() {
        delivery.invalidate()
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        eventContext = nil
    }

    static func shortcutLabel(for action: HotKeyAction) -> String {
        "⌃" + action.letter
    }

    deinit {
        references.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

private final class HotKeyEventContext {
    let deliver: @MainActor (UInt32) -> Void
    init(deliver: @escaping @MainActor (UInt32) -> Void) { self.deliver = deliver }
}

/// Carbon callbacks are dispatched asynchronously; only the current registration may act.
@MainActor
final class HotKeyEventDelivery {
    private var registrationID = UUID()
    private var registeredActions: Set<HotKeyAction> = []
    private var handler: ((HotKeyAction) -> Void)?

    func begin(handler: @escaping (HotKeyAction) -> Void) -> UUID {
        invalidate()
        self.handler = handler
        return registrationID
    }

    func allow(_ action: HotKeyAction) { registeredActions.insert(action) }

    func invalidate() {
        registrationID = UUID()
        registeredActions.removeAll()
        handler = nil
    }

    func deliver(identifier: UInt32, registrationID: UUID) {
        guard self.registrationID == registrationID,
              let action = HotKeyAction.allCases.first(where: { $0.carbonIdentifier == identifier }),
              registeredActions.contains(action) else { return }
        handler?(action)
    }
}
