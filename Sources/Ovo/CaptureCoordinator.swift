import Foundation

/// A replacement capture waits for the old task to finish restoring the clipboard
/// and closing its screenshot process before starting another capture.
@MainActor
final class CaptureCoordinator {
    private var task: Task<Void, Never>?

    func cancel() { task?.cancel() }

    @discardableResult
    func start(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = task
        previous?.cancel()
        let next = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        task = next
        return next
    }
}

/// Consecutive screenshot requests share the visibility from before the first
/// picker hid the windows. A superseded request cannot consume the new one's state.
@MainActor
final class ScreenshotPresentation {
    struct Visibility: Equatable {
        var translation: Bool
        var settings: Bool
    }

    struct Session {
        let id = UUID()
        let visibility: Visibility
    }

    private var active: Session?

    func begin(visible: Visibility) -> Session {
        let session = Session(visibility: Visibility(
            translation: visible.translation || active?.visibility.translation == true,
            settings: visible.settings || active?.visibility.settings == true
        ))
        active = session
        return session
    }

    func finish(_ session: Session) -> Visibility? {
        guard active?.id == session.id else { return nil }
        active = nil
        return session.visibility
    }

    func reset() { active = nil }
}
