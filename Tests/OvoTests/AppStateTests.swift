import Foundation
import Testing
@testable import Ovo

@MainActor
struct AppStateTests {
    @Test
    func pinningUpdatesWindowPolicyAndSurvivesANewTranslation() {
        let state = makeState()
        var pinChanges: [Bool] = []
        state.onPin = { pinChanges.append($0) }
        state.isPinned = true
        state.prepare(source: .input, text: "Hello")
        #expect(state.isPinned)
        state.isPinned = true
        state.isPinned = false
        #expect(pinChanges == [true, false])
    }

    @Test(arguments: [TranslationSource.selection, .screenshot])
    func retryAfterCaptureFailureRepeatsCaptureWithoutNeedingAKey(_ source: TranslationSource) {
        let state = makeState()
        state.prepare(source: source)
        state.captureRetrySource = source
        state.errorMessage = "Capture was unavailable"
        var capturedSource: TranslationSource?
        state.onRetryCapture = { capturedSource = $0 }
        #expect(state.canRetry)
        state.retry()
        #expect(capturedSource == source)
        state.input = "New manual text"
        #expect(state.captureRetrySource == nil)
    }

    @Test
    func deletingAnOpenFavoriteUpdatesTheFloatingWindowState() {
        let state = makeState()
        let record = englishRecord()
        #expect(state.history.add(record))
        #expect(state.history.setFavorite(true, id: record.id))
        state.show(state.history.records[0])
        #expect(state.currentIsFavorite)
        #expect(state.history.remove(record))
        #expect(!state.currentIsFavorite)
    }

    @Test
    func overlongInputDoesNotAttemptToReadCredentials() {
        let backend = NoReadKeychain()
        let state = makeState(keychain: KeychainService(backend: backend))
        state.input = String(repeating: "a", count: DeepSeekService.maximumInputLength + 1)
        state.translate()
        #expect(backend.reads == 0)
        #expect(state.errorMessage == DeepSeekError.inputTooLong.localizedDescription)
        #expect(!state.isWorking)
    }
    @Test
    func editingSourceInvalidatesPendingTranslation() {
        let state = makeState()
        state.prepare(source: .input, text: "First sentence")
        state.output = "旧译文"
        state.pair = LanguagePair(source: .english, target: .chinese)
        state.errorMessage = "An earlier failure"
        state.isWorking = true

        state.input = "Second sentence"

        #expect(state.input == "Second sentence")
        #expect(!state.isWorking)
        #expect(state.output.isEmpty)
        #expect(state.pair == nil)
        #expect(state.errorMessage == nil)
        #expect(state.history.records.isEmpty)
    }

    @Test
    func changingDirectionInvalidatesPendingTranslation() {
        let state = makeState()
        state.prepare(source: .input, text: "Hello")
        state.output = "你好"
        state.pair = LanguagePair(source: .english, target: .chinese)
        state.errorMessage = "An earlier failure"
        state.isWorking = true

        state.direction = .chineseToEnglish

        #expect(state.direction == .chineseToEnglish)
        #expect(state.input == "Hello")
        #expect(!state.isWorking)
        #expect(state.output.isEmpty)
        #expect(state.pair == nil)
        #expect(state.errorMessage == nil)
    }

    @Test
    func swappingLanguagesPreservesPreviousTranslationAsNewInput() {
        let state = makeState()
        state.show(englishRecord())
        state.isWorking = true

        state.swapLanguages()

        #expect(state.input == "你好")
        #expect(state.direction == .chineseToEnglish)
        #expect(state.output.isEmpty)
        #expect(state.pair == nil)
        #expect(!state.isWorking)
    }

    @Test(arguments: TranslationDirection.allCases)
    func viewingHistoryRetainsPreferredDirection(_ preferredDirection: TranslationDirection) {
        let state = makeState()
        state.direction = preferredDirection
        state.isWorking = true

        state.show(englishRecord())

        #expect(state.input == "Hello")
        #expect(state.output == "你好")
        #expect(state.source == .selection)
        #expect(state.pair == LanguagePair(source: .english, target: .chinese))
        #expect(state.direction == preferredDirection)
        #expect(!state.isWorking)

        state.prepare(source: .selection, text: "再见")

        #expect(state.direction == preferredDirection)
        #expect(state.pair == nil)
        #expect(state.output.isEmpty)
        if preferredDirection == .automatic {
            #expect(state.direction.resolved(for: state.input) == LanguagePair(source: .chinese, target: .english))
        }
    }

    private func makeState(keychain: KeychainService? = nil) -> AppState {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ovo-AppStateTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
        return AppState(history: HistoryStore(fileURL: file), checkKey: false, keychain: keychain)
    }

    private func englishRecord() -> TranslationRecord {
        TranslationRecord(source: .selection, original: "Hello", translation: "你好",
                          sourceLanguage: .english, targetLanguage: .chinese)
    }
}

@MainActor
private final class NoReadKeychain: KeychainBackend {
    var reads = 0
    func containsAPIKey() throws -> Bool { false }
    func getAPIKey() throws -> String? { reads += 1; return nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}
