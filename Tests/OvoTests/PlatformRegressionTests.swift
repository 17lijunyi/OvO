import AppKit
import Foundation
import Testing
@testable import Ovo

@MainActor
struct PlatformRegressionTests {
    @Test
    func staleHotKeyEventsCannotCallANewRegistration() {
        let delivery = HotKeyEventDelivery()
        var oldCount = 0
        var newCount = 0
        let old = delivery.begin { _ in oldCount += 1 }
        delivery.allow(.selection)
        let current = delivery.begin { _ in newCount += 1 }
        delivery.allow(.selection)
        delivery.deliver(identifier: 1, registrationID: old)
        delivery.deliver(identifier: 3, registrationID: current)
        #expect(oldCount == 0 && newCount == 0)
        delivery.deliver(identifier: 1, registrationID: current)
        #expect(newCount == 1)
        delivery.invalidate()
        delivery.deliver(identifier: 1, registrationID: current)
        #expect(newCount == 1)
    }

    @Test
    func replacementCaptureWaitsForPreviousCleanup() async {
        let coordinator = CaptureCoordinator()
        var events: [String] = []
        var finishCleanup: CheckedContinuation<Void, Never>?
        let first = coordinator.start {
            events.append("first started")
            await withCheckedContinuation { finishCleanup = $0 }
            events.append("first cleaned up")
        }
        while finishCleanup == nil { await Task.yield() }
        let second = coordinator.start { events.append("second started") }
        await Task.yield()
        #expect(events == ["first started"])
        finishCleanup?.resume()
        await first.value
        await second.value
        #expect(events == ["first started", "first cleaned up", "second started"])
    }

    @Test
    func latestCaptureSkipsAnAlreadySupersededQueuedRequest() async {
        let coordinator = CaptureCoordinator()
        var finishCleanup: CheckedContinuation<Void, Never>?
        var events: [Int] = []
        coordinator.start { await withCheckedContinuation { finishCleanup = $0 } }
        while finishCleanup == nil { await Task.yield() }
        coordinator.start { events.append(2) }
        let last = coordinator.start { events.append(3) }
        finishCleanup?.resume()
        await last.value
        #expect(events == [3])
    }

    @Test
    func cancellingAReplacementScreenshotRestoresTheOriginalWindows() {
        let presentation = ScreenshotPresentation()
        let first = presentation.begin(visible: .init(translation: true, settings: true))
        // The first picker has already hidden both windows when the shortcut repeats.
        let replacement = presentation.begin(visible: .init(translation: false, settings: false))
        #expect(presentation.finish(first) == nil)
        #expect(presentation.finish(replacement) == .init(translation: true, settings: true))

        // A later independent capture must not reuse the old window state.
        let next = presentation.begin(visible: .init(translation: false, settings: false))
        #expect(presentation.finish(next) == .init(translation: false, settings: false))
    }

    @Test
    func selectedTextIsReturnedAndEveryClipboardFormatRestored() async throws {
        let clipboard = FakeSelectionClipboard()
        let before = clipboard.contents
        let result = try await SelectionClipboardTransaction.capture(clipboard: clipboard,
            isSourceFrontmost: { true }, sendCopy: {
                clipboard.contents = [[.string: Data("Hello".utf8)]]
                clipboard.changeCount += 1
            }, waitForCopy: {})
        #expect(result == "Hello")
        #expect(clipboard.contents == before)
        #expect(clipboard.restoreCount == 1)
    }

    @Test
    func anIncompleteSnapshotNeverSendsCopyOrReplacesClipboard() async {
        let clipboard = FakeSelectionClipboard()
        clipboard.failSnapshot = true
        var didCopy = false
        do {
            _ = try await SelectionClipboardTransaction.capture(clipboard: clipboard,
                isSourceFrontmost: { true }, sendCopy: { didCopy = true }, waitForCopy: {})
            Issue.record("An incomplete snapshot must fail before touching the clipboard")
        } catch {
            #expect(error as? PlatformError == .clipboardUnavailable)
        }
        #expect(!didCopy && clipboard.restoreCount == 0)
    }

    @Test
    func clipboardChangedByALazyProviderIsNotOverwritten() async {
        let clipboard = FakeSelectionClipboard()
        clipboard.changeDuringRead = true
        do {
            _ = try await SelectionClipboardTransaction.capture(clipboard: clipboard,
                isSourceFrontmost: { true }, sendCopy: { clipboard.changeCount += 1 }, waitForCopy: {})
            Issue.record("A newer clipboard value must not be accepted as the selection")
        } catch {
            #expect(error as? PlatformError == .copyUnavailable)
        }
        #expect(clipboard.restoreCount == 0)
        #expect(clipboard.readText() == "new user clipboard")
    }
}

@MainActor
private final class FakeSelectionClipboard: SelectionClipboard {
    var changeCount = 1
    var contents: SelectionClipboardContents = [[.string: Data("original".utf8), .rtf: Data("rich text".utf8)]]
    var restoreCount = 0
    var failSnapshot = false
    var changeDuringRead = false
    func readContents() throws -> SelectionClipboardContents {
        if failSnapshot { throw PlatformError.clipboardUnavailable }
        return contents
    }
    func readText() -> String? {
        if changeDuringRead {
            changeDuringRead = false
            contents = [[.string: Data("new user clipboard".utf8)]]
            changeCount += 1
        }
        return contents.first?[.string].flatMap { String(data: $0, encoding: .utf8) }
    }
    func restore(_ value: SelectionClipboardContents) {
        contents = value
        changeCount += 1
        restoreCount += 1
    }
}

struct CaptureProcessTests {
    @Test
    func normalExitIsReturned() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        #expect(try await CancellableCaptureProcess(process: process).run() == 0)
    }

    @Test
    func cancellationBeforeLaunchDoesNotStartProcess() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CancellableCaptureProcess(process: process).run()
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(!process.isRunning)
    }

    @Test
    func cancellationTerminatesTheStartedProcess() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        let task = Task { try await CancellableCaptureProcess(process: process).run() }
        for _ in 0..<200 {
            if process.isRunning { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(process.isRunning)
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(!process.isRunning)
    }
}
