import Foundation
import Testing
@testable import Ovo

@MainActor
struct KeychainServiceTests {
    @Test
    func successfulReadsUseTheSameSessionCache() throws {
        let backend = FakeKeychainBackend(key: "test-original-key")
        let service = KeychainService(backend: backend)

        #expect(try service.getAPIKey() == "test-original-key")
        backend.key = "test-external-replacement"
        #expect(try service.getAPIKey() == "test-original-key")
        #expect(try service.getAPIKey() == "test-original-key")
        #expect(backend.readCount == 1)
    }

    @Test
    func presenceChecksNeverLoadSecretData() throws {
        let backend = FakeKeychainBackend(key: "test-saved-key")
        let service = KeychainService(backend: backend)

        #expect(try service.containsAPIKey())
        backend.key = nil
        #expect(try !service.containsAPIKey())
        #expect(backend.presenceCount == 2)
        #expect(backend.readCount == 0)
    }

    @Test
    func applicationStartupAndStatusRefreshesNeverLoadSecretData() {
        let backend = FakeKeychainBackend(key: "test-saved-key")
        let state = makeState(keychain: KeychainService(backend: backend))

        #expect(state.hasAPIKey)
        #expect(backend.presenceCount == 1)
        #expect(backend.readCount == 0)

        state.refreshKeyStatus()
        state.refreshKeyStatus()

        #expect(state.hasAPIKey)
        #expect(backend.presenceCount == 3)
        #expect(backend.readCount == 0)
    }

    @Test
    func unavailableMetadataDoesNotEraseAKnownSavedState() {
        let backend = FakeKeychainBackend(key: "test-saved-key")
        let state = makeState(keychain: KeychainService(backend: backend))
        #expect(state.hasAPIKey)
        backend.presenceFailure = .metadataDenied
        backend.key = nil

        state.refreshKeyStatus()

        #expect(state.hasAPIKey)
        #expect(backend.readCount == 0)

        backend.presenceFailure = nil
        state.refreshKeyStatus()

        #expect(!state.hasAPIKey)
        #expect(backend.readCount == 0)
    }

    @Test
    func failedReadsCanBeRetriedAndDoNotPopulateCache() throws {
        let backend = FakeKeychainBackend(key: "test-saved-key")
        backend.readFailure = .readDenied
        let service = KeychainService(backend: backend)

        #expect(throws: FakeKeychainFailure.readDenied) { try service.getAPIKey() }
        #expect(backend.readCount == 1)

        backend.readFailure = nil
        #expect(try service.getAPIKey() == "test-saved-key")
        #expect(try service.getAPIKey() == "test-saved-key")
        #expect(backend.readCount == 2)
    }

    @Test
    func missingKeysAreNotNegativelyCached() throws {
        let backend = FakeKeychainBackend(key: nil)
        let service = KeychainService(backend: backend)

        #expect(try service.getAPIKey() == nil)
        backend.key = "test-added-key"
        #expect(try service.getAPIKey() == "test-added-key")
        #expect(backend.readCount == 2)
    }

    @Test
    func emptyKeysDoNotPreventALaterSuccessfulRead() throws {
        let backend = FakeKeychainBackend(key: "")
        let service = KeychainService(backend: backend)

        // Either rejecting or returning an empty value is acceptable; caching it is not.
        let initialValue = try? service.getAPIKey()
        #expect(initialValue?.isEmpty ?? true)
        backend.key = "test-valid-key"
        #expect(try service.getAPIKey() == "test-valid-key")
        #expect(backend.readCount == 2)
    }

    @Test(arguments: [false, true])
    func successfulSavePrimesOrReplacesSessionCache(hasCachedKey: Bool) throws {
        let backend = FakeKeychainBackend(key: "test-original-key")
        let service = KeychainService(backend: backend)
        if hasCachedKey { _ = try service.getAPIKey() }
        let previousReads = backend.readCount

        try service.saveAPIKey("test-replacement-key")

        #expect(backend.savedValues == ["test-replacement-key"])
        #expect(backend.key == "test-replacement-key")
        #expect(try service.getAPIKey() == "test-replacement-key")
        #expect(backend.readCount == previousReads)
    }

    @Test
    func successfulDeleteClearsSessionCache() throws {
        let backend = FakeKeychainBackend(key: "test-original-key")
        let service = KeychainService(backend: backend)
        #expect(try service.getAPIKey() == "test-original-key")

        try service.deleteAPIKey()

        #expect(backend.deleteCount == 1)
        #expect(backend.key == nil)
        #expect(try service.getAPIKey() == nil)
        #expect(backend.readCount == 2)
        #expect(try !service.containsAPIKey())
    }

    @Test
    func failedSavePreservesThePreviouslyAuthorizedKey() throws {
        let backend = FakeKeychainBackend(key: "test-original-key")
        let service = KeychainService(backend: backend)
        #expect(try service.getAPIKey() == "test-original-key")
        backend.saveFailure = .saveDenied

        #expect(throws: FakeKeychainFailure.saveDenied) {
            try service.saveAPIKey("test-rejected-key")
        }

        #expect(backend.key == "test-original-key")
        #expect(try service.getAPIKey() == "test-original-key")
        #expect(backend.readCount == 1)
    }

    @Test
    func failedDeletePreservesThePreviouslyAuthorizedKey() throws {
        let backend = FakeKeychainBackend(key: "test-original-key")
        let service = KeychainService(backend: backend)
        #expect(try service.getAPIKey() == "test-original-key")
        backend.deleteFailure = .deleteDenied

        #expect(throws: FakeKeychainFailure.deleteDenied) { try service.deleteAPIKey() }

        #expect(backend.deleteCount == 1)
        #expect(backend.key == "test-original-key")
        #expect(try service.getAPIKey() == "test-original-key")
        #expect(backend.readCount == 1)
    }

    private func makeState(keychain: KeychainService) -> AppState {
        let historyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ovo-KeychainTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
        return AppState(history: HistoryStore(fileURL: historyFile), keychain: keychain)
    }
}

private enum FakeKeychainFailure: Error, Equatable {
    case metadataDenied
    case readDenied
    case saveDenied
    case deleteDenied
}

/// Deliberately independent of Security.framework and the user's real Keychain.
@MainActor
private final class FakeKeychainBackend: KeychainBackend {
    var key: String?
    var presenceFailure: FakeKeychainFailure?
    var readFailure: FakeKeychainFailure?
    var saveFailure: FakeKeychainFailure?
    var deleteFailure: FakeKeychainFailure?
    private(set) var presenceCount = 0
    private(set) var readCount = 0
    private(set) var savedValues: [String] = []
    private(set) var deleteCount = 0

    init(key: String?) { self.key = key }

    func containsAPIKey() throws -> Bool {
        presenceCount += 1
        if let presenceFailure { throw presenceFailure }
        return key != nil
    }

    func getAPIKey() throws -> String? {
        readCount += 1
        if let readFailure { throw readFailure }
        return key
    }

    func saveAPIKey(_ value: String) throws {
        savedValues.append(value)
        if let saveFailure { throw saveFailure }
        key = value
    }

    func deleteAPIKey() throws {
        deleteCount += 1
        if let deleteFailure { throw deleteFailure }
        key = nil
    }
}
