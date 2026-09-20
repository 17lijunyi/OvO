import Foundation
import Testing
@testable import Ovo

@MainActor
struct HistoryRegressionTests {
    @Test
    func olderRecordsKeepTheSameOrderBeforeAndAfterReload() throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            let newer = record(index: 2)
            let older = record(index: 1)
            #expect(history.add(newer))
            #expect(history.add(older))

            #expect(history.records == [newer, older])
            #expect(HistoryStore(fileURL: file).records == history.records)
        }
    }

    @Test
    func replacingAnIDDoesNotCreateDuplicatesOrChangeOtherRecords() throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            let first = record(index: 1)
            let second = record(index: 2)
            #expect(history.add(first))
            #expect(history.add(second))
            let replacement = TranslationRecord(id: first.id, date: first.date, source: first.source,
                original: first.original, translation: "更新后的译文", sourceLanguage: first.sourceLanguage,
                targetLanguage: first.targetLanguage, isFavorite: true)

            #expect(history.add(replacement))

            #expect(history.records == [second, replacement])
            #expect(HistoryStore(fileURL: file).records == [second, replacement])
        }
    }

    @Test
    func largerHistoryDoesNotLoseOldEntriesOrFavorites() throws {
        try withHistoryFile { file in
            let original = (0..<1_024).map { record(index: $0, isFavorite: $0 == 0) }
            try writeFixture(original, to: file)
            let history = HistoryStore(fileURL: file)
            let newest = record(index: 1_024)

            #expect(history.add(newest))
            #expect(history.setFavorite(true, id: original[512].id))
            #expect(history.remove(id: original[700].id))

            let reopened = HistoryStore(fileURL: file)
            #expect(reopened.records.count == 1_024)
            #expect(reopened.records.first == newest)
            #expect(reopened.records.last == original[0])
            #expect(reopened.records.first(where: { $0.id == original[512].id })?.isFavorite == true)
            #expect(!reopened.records.contains(where: { $0.id == original[700].id }))
            #expect(Set(reopened.records.map(\.id)).count == reopened.records.count)
        }
    }

    @Test
    func favoritesAndDeletionPreserveMultilineUnicodeText() throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            let original = TranslationRecord(date: Date(timeIntervalSince1970: 1_000), source: .screenshot,
                original: "你好 👋\n\"Keep this line\"\nhttps://example.com/?a=1&b=2", translation: "Hello 👋\n下一行\n```swift\nlet x = 1\n```",
                sourceLanguage: .chinese, targetLanguage: .english)
            let other = record(index: 2)
            #expect(history.add(original))
            #expect(history.add(other))
            #expect(history.toggleFavorite(id: original.id))
            #expect(history.remove(other))

            let saved = try #require(HistoryStore(fileURL: file).records.first)
            #expect(saved.id == original.id)
            #expect(saved.date == original.date)
            #expect(saved.source == original.source)
            #expect(saved.original == original.original)
            #expect(saved.translation == original.translation)
            #expect(saved.sourceLanguage == original.sourceLanguage)
            #expect(saved.targetLanguage == original.targetLanguage)
            #expect(saved.isFavorite)
            #expect(history.filteredRecords(query: " KEEP THIS LINE ").count == 1)
            #expect(history.filteredRecords(query: "下一行").count == 1)
        }
    }

    @Test
    func clearCommitsEmptyHistoryWithPrivateFilePermissions() throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            #expect(history.add(record(index: 1, isFavorite: true)))
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)

            #expect(history.clear())

            #expect(history.records.isEmpty)
            #expect(HistoryStore(fileURL: file).records.isEmpty)
            #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [Any] != nil)
            let clearedPermissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(clearedPermissions?.intValue == 0o600)
            #expect(try !FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
                .contains(where: { $0.hasSuffix(".tmp") }))
        }
    }

    @Test
    func corruptHistoryCannotBeOverwrittenByDeleteOrClear() throws {
        try withHistoryFile { file in
            let damaged = Data("[{\"original\":\"keep the damaged file for recovery\"}".utf8)
            try damaged.write(to: file)
            let history = HistoryStore(fileURL: file)

            #expect(!history.clear())
            #expect(!history.clearUnfavorited())
            #expect(!history.remove(id: UUID()))
            #expect(!history.add(record(index: 1)))

            #expect(history.records.isEmpty)
            #expect(history.errorMessage != nil)
            #expect(try Data(contentsOf: file) == damaged)
        }
    }

    @Test(arguments: HistoryMutation.allCases)
    func failedCommitPreservesMemoryAndPreviousFileAndCanBeRetried(_ mutation: HistoryMutation) throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            let first = record(index: 1)
            let second = record(index: 2)
            #expect(history.add(first))
            #expect(history.add(second))
            let snapshot = history.records
            let originalData = try Data(contentsOf: file)
            let preservedFile = file.appendingPathExtension("preserved")
            try FileManager.default.moveItem(at: file, to: preservedFile)
            // A nonempty directory forces the final rename to fail after staging succeeds.
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            let sentinel = file.appendingPathComponent("sentinel")
            try Data("untouched".utf8).write(to: sentinel)
            let extra = record(index: 3)

            #expect(!apply(mutation, to: history, target: first, extra: extra))

            #expect(history.records == snapshot)
            #expect(history.errorMessage != nil)
            #expect(try Data(contentsOf: preservedFile) == originalData)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "untouched")
            #expect(try !FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
                .contains(where: { $0.hasSuffix(".tmp") }))

            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: preservedFile, to: file)
            #expect(apply(mutation, to: history, target: first, extra: extra))
            #expect(history.errorMessage == nil)
            #expect(HistoryStore(fileURL: file).records == history.records)
        }
    }

    @Test
    func cleanupKeepsFavoritesAndPersistsThemAcrossRestart() throws {
        try withHistoryFile { file in
            let original = (0..<100).map { record(index: $0, isFavorite: $0 % 10 == 0) }
            try writeFixture(original, to: file)
            let history = HistoryStore(fileURL: file)
            #expect(history.favoriteCount == 10)
            #expect(history.unfavoritedCount == 90)
            #expect(history.shouldSuggestCleanup(at: 100))
            #expect(history.clearUnfavorited())
            #expect(history.records == original.filter(\.isFavorite).reversed())
            #expect(!history.shouldSuggestCleanup(at: 100))
            #expect(HistoryStore(fileURL: file).records == history.records)
        }
    }

    @Test
    func reminderStartsAtThresholdAndDoesNotDeleteAutomatically() throws {
        try withHistoryFile { file in
            try writeFixture((0..<99).map { record(index: $0) }, to: file)
            let history = HistoryStore(fileURL: file)
            #expect(!history.shouldSuggestCleanup(at: 100))
            #expect(history.add(record(index: 99)))
            #expect(history.shouldSuggestCleanup(at: 100))
            #expect(!history.shouldSuggestCleanup(at: 500))
            #expect(history.records.count == 100)
            #expect(HistoryStore(fileURL: file).records.count == 100)
        }
    }

    @Test
    func favoritesSearchAndUnfavoriteKeepTheUnderlyingHistory() throws {
        try withHistoryFile { file in
            let history = HistoryStore(fileURL: file)
            let saved = record(index: 1, isFavorite: true)
            #expect(history.add(saved))
            #expect(history.add(record(index: 2)))
            #expect(history.filteredRecords(query: "source", favoritesOnly: true) == [saved])
            #expect(history.filteredRecords(query: "译文 1", favoritesOnly: true) == [saved])
            #expect(history.filteredRecords(query: "2", favoritesOnly: true).isEmpty)
            #expect(history.setFavorite(false, id: saved.id))
            #expect(history.filteredRecords(query: "", favoritesOnly: true).isEmpty)
            #expect(history.records.count == 2)
        }
    }

    @Test
    func allFavoriteHistoryIsNotSuggestedForCleanup() throws {
        try withHistoryFile { file in
            try writeFixture((0..<100).map { record(index: $0, isFavorite: true) }, to: file)
            let history = HistoryStore(fileURL: file)
            #expect(!history.shouldSuggestCleanup(at: 100))
            #expect(history.clearUnfavorited())
            #expect(history.records.count == 100)
        }
    }

    private func apply(_ mutation: HistoryMutation, to history: HistoryStore,
                       target: TranslationRecord, extra: TranslationRecord) -> Bool {
        switch mutation {
        case .add: return history.add(extra)
        case .remove: return history.remove(target)
        case .favorite: return history.toggleFavorite(id: target.id)
        case .clear: return history.clear()
        case .clearUnfavorited: return history.clearUnfavorited()
        }
    }

    private func record(index: Int, isFavorite: Bool = false) -> TranslationRecord {
        TranslationRecord(date: Date(timeIntervalSince1970: TimeInterval(1_000 + index)), source: .input,
            original: "Source \(index)", translation: "译文 \(index)", sourceLanguage: .english,
            targetLanguage: .chinese, isFavorite: isFavorite)
    }

    private func writeFixture(_ records: [TranslationRecord], to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: file)
    }

    private func withHistoryFile(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ovo-HistoryRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("history.json"))
    }
}

enum HistoryMutation: CaseIterable, Sendable {
    case add, remove, favorite, clear, clearUnfavorited
}
