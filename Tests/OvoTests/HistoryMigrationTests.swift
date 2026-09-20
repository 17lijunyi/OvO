import Foundation
import Testing
@testable import Ovo

@Suite(.serialized)
struct HistoryMigrationTests {
    @Test @MainActor
    func legacyHistoryLoadsAndFavoritePersistsWithoutChangingTranslation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OvoMigrationTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let identifier = UUID()
        let legacyRecord: [String: Any] = [
            "id": identifier.uuidString,
            "date": "2026-01-01T12:00:00Z",
            "source": "input",
            "original": "A new beginning.",
            "translation": "新的开始。",
            "sourceLanguage": "en",
            "targetLanguage": "zh"
        ]
        try JSONSerialization.data(withJSONObject: [legacyRecord]).write(to: file)

        let history = HistoryStore(fileURL: file)
        let original = try #require(history.records.first)
        #expect(history.errorMessage == nil)
        #expect(original.id == identifier)
        #expect(!original.isFavorite)
        #expect(history.toggleFavorite(id: identifier))

        let reopened = HistoryStore(fileURL: file)
        let favorite = try #require(reopened.records.first)
        #expect(favorite.isFavorite)
        #expect(favorite.id == original.id)
        #expect(favorite.date == original.date)
        #expect(favorite.source == original.source)
        #expect(favorite.original == original.original)
        #expect(favorite.translation == original.translation)
        #expect(favorite.sourceLanguage == original.sourceLanguage)
        #expect(favorite.targetLanguage == original.targetLanguage)

        #expect(reopened.setFavorite(false, id: identifier))
        #expect(HistoryStore(fileURL: file).records == [original])
    }
}
