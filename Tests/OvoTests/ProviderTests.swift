import Foundation
import Testing
@testable import Ovo

@MainActor
struct ProviderTests {
    private func config() -> ServiceConfiguration {
        ServiceConfiguration(defaults: UserDefaults(suiteName: "OvO-Providers-\(UUID())")!)
    }

    @Test func defaultProviderAndLegacyMigration() {
        let defaults = UserDefaults(suiteName: "OvO-Migration-\(UUID())")!
        #expect(ServiceConfiguration(defaults: defaults).provider == (ServiceConfiguration.appleAvailable ? .apple : .deepseek))
        defaults.set("deepseek-flash", forKey: "service.deepseek.selectedModel")
        let old = ServiceConfiguration(defaults: defaults)
        #expect(old.provider == .deepseek)
        old.provider = .custom
        old.customEndpoint = "https://example.com/v1"
        old.customAPIModel = "my-model"
        let reloaded = ServiceConfiguration(defaults: defaults)
        #expect(reloaded.provider == .custom)
        #expect(reloaded.customEndpoint == "https://example.com/v1")
        #expect(reloaded.customAPIModel == "my-model")
        #expect(reloaded.effectiveModel == "deepseek-flash")
    }

    @Test func customRequestOmitsVendorThinkingAndKeepsIndependentEndpoint() throws {
        let request = try DeepSeekService().makeRequest(text: "Hello",
            languages: LanguagePair(source: .english, target: .chinese), apiKey: "custom-key",
            endpoint: "https://example.com/v1/", model: "my-model", compatibleAPI: true)
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer custom-key")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["thinking"] == nil)
        #expect(body["model"] as? String == "my-model")
        #expect(body["stream"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 1024)
    }

    @Test func localEndpointsCanOmitKeyButRemotePlaintextAndEmbeddedCredentialsAreRejected() throws {
        for endpoint in ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1"] {
            let request = try DeepSeekService().makeRequest(text: "你好",
                languages: LanguagePair(source: .chinese, target: .english), apiKey: "",
                endpoint: endpoint, model: "local", compatibleAPI: true)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        for endpoint in ["http://remote.example/v1", "http://localhost.evil.test", "file:///tmp/model", "https://user:key@example.com", "https://example.com?key=secret"] {
            #expect(throws: DeepSeekError.invalidEndpoint) {
                try DeepSeekService.completionsURL(endpoint: endpoint, allowLocalHTTP: true)
            }
        }
    }

    @Test func applePathNeverReadsKeysAndStaleResultCannotOverwriteNewInput() throws {
        guard ServiceConfiguration.appleAvailable else { return }
        let configuration = config(); configuration.provider = .apple
        let backend = ProviderKeychainSpy()
        let state = makeState(configuration, backend)
        state.input = "Hello"; state.translate()
        let job = try #require(state.appleJob)
        #expect(state.isWorking)
        #expect(backend.reads == 0)
        state.input = "Changed"
        #expect(state.appleJob == nil)
        state.completeTranslation(.init(text: "你好", sourceLanguage: .english, targetLanguage: .chinese),
            requestID: job.id, original: job.text, source: job.source, provider: .apple, providerName: "苹果系统翻译")
        #expect(state.output.isEmpty)
        #expect(state.history.records.isEmpty)
    }

    @Test func switchingProviderCancelsAppleJobAndKeepsDeepSeekPreferences() throws {
        guard ServiceConfiguration.appleAvailable else { return }
        let configuration = config(); configuration.provider = .apple
        configuration.customModel = "my-deepseek-model"
        let state = makeState(configuration, ProviderKeychainSpy())
        state.input = "Hello"; state.translate()
        #expect(state.appleJob != nil)
        configuration.provider = .custom
        #expect(state.appleJob == nil)
        #expect(!state.isWorking)
        #expect(state.canRetry)
        #expect(configuration.customModel == "my-deepseek-model")
    }

    @Test func providerMetadataSurvivesFavoriteToggleAndReloadAndClearAll() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("OvO-provider-history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HistoryStore(fileURL: file)
        let record = TranslationRecord(source: .input, original: "Hello", translation: "你好",
            sourceLanguage: .english, targetLanguage: .chinese, provider: .custom, providerName: "我的模型")
        #expect(store.add(record))
        #expect(store.setFavorite(true, id: record.id))
        let reloaded = HistoryStore(fileURL: file)
        let saved = try #require(reloaded.records.first)
        #expect(saved.provider == .custom && saved.providerName == "我的模型" && saved.isFavorite)
        #expect(reloaded.clear())
        #expect(HistoryStore(fileURL: file).records.isEmpty)
    }

    @Test func appleSuccessKeepsProviderAndACompletedJobIgnoresLateFailure() throws {
        guard ServiceConfiguration.appleAvailable else { return }
        let configuration = config(); configuration.provider = .apple
        let state = makeState(configuration, ProviderKeychainSpy())
        state.input = "Hello"; state.translate()
        let job = try #require(state.appleJob)
        state.completeTranslation(.init(text: "你好", sourceLanguage: .english, targetLanguage: .chinese),
            requestID: job.id, original: job.text, source: job.source, provider: .apple, providerName: "苹果系统翻译")
        #expect(state.output == "你好")
        #expect(state.currentRecord?.provider == .apple)
        #expect(!state.isWorking && state.appleJob == nil)
        state.failAppleTranslation("Late cancellation", jobID: job.id)
        #expect(state.errorMessage == nil)
        // Favoriting an unsaved result must also retain its original provider.
        _ = state.history.clear()
        state.toggleFavorite()
        #expect(state.history.records.first?.provider == .apple)
        #expect(state.history.records.first?.isFavorite == true)
    }

    @Test func malformedCustomDestinationDoesNotReadKey() {
        let configuration = config(); configuration.provider = .custom
        configuration.customEndpoint = "http://unsafe.example"
        configuration.customAPIModel = "model"
        let backend = ProviderKeychainSpy()
        let state = makeState(configuration, backend)
        state.input = "Hello"; state.translate()
        #expect(backend.reads == 0)
        #expect(!state.isWorking)
        #expect(state.errorMessage != nil)
    }

    private func makeState(_ configuration: ServiceConfiguration, _ backend: ProviderKeychainSpy) -> AppState {
        AppState(history: HistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("OvO-provider-\(UUID())/history.json")), checkKey: false,
            keychain: KeychainService(backend: backend), configuration: configuration,
            customKeychain: KeychainService(account: "custom-api-key", backend: backend))
    }
}

@MainActor
private final class ProviderKeychainSpy: KeychainBackend {
    var reads = 0
    func containsAPIKey() throws -> Bool { false }
    func getAPIKey() throws -> String? { reads += 1; return nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}
