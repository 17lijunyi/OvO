import Combine
import Darwin
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [TranslationRecord] = []
    @Published var errorMessage: String?

    static let defaultCleanupThreshold = 100
    var favoriteCount: Int { records.filter(\.isFavorite).count }
    var unfavoritedCount: Int { records.count - favoriteCount }

    func shouldSuggestCleanup(at threshold: Int) -> Bool {
        threshold > 0 && records.count >= threshold && unfavoritedCount > 0
    }

    let fileURL: URL
    private var loadFailed = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ovo", isDirectory: true)
            .appendingPathComponent("history.json")
        load()
    }

    @discardableResult
    func add(_ record: TranslationRecord) -> Bool {
        var updated = records.filter { $0.id != record.id }
        updated.insert(record, at: 0)
        updated.sort { $0.date > $1.date }
        return persist(updated)
    }

    @discardableResult
    func remove(_ record: TranslationRecord) -> Bool { remove(id: record.id) }

    @discardableResult
    func remove(id: UUID) -> Bool { persist(records.filter { $0.id != id }) }

    @discardableResult
    func clear() -> Bool { persist([]) }

    @discardableResult
    func clearUnfavorited() -> Bool { persist(records.filter(\.isFavorite)) }

    @discardableResult
    func toggleFavorite(id: UUID) -> Bool {
        guard let record = records.first(where: { $0.id == id }) else { return false }
        return setFavorite(!record.isFavorite, id: id)
    }

    @discardableResult
    func setFavorite(_ isFavorite: Bool, id: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        let record = records[index]
        guard record.isFavorite != isFavorite else { return true }
        var updated = records
        updated[index] = TranslationRecord(id: record.id, date: record.date, source: record.source,
            original: record.original, translation: record.translation,
            sourceLanguage: record.sourceLanguage, targetLanguage: record.targetLanguage,
            isFavorite: isFavorite, provider: record.provider, providerName: record.providerName)
        return persist(updated)
    }

    func filteredRecords(query: String, favoritesOnly: Bool = false) -> [TranslationRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoped = favoritesOnly ? records.filter(\.isFavorite) : records
        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.original.localizedCaseInsensitiveContains(query)
                || $0.translation.localizedCaseInsensitiveContains(query)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([TranslationRecord].self, from: data)
                .sorted { $0.date > $1.date }
        } catch {
            loadFailed = true
            errorMessage = "无法读取历史记录，原文件已保留。请检查 \(fileURL.path)。"
        }
    }

    private func persist(_ updated: [TranslationRecord]) -> Bool {
        // Never replace an unreadable existing history with an empty or partial list.
        guard !loadFailed else {
            errorMessage = "历史记录文件无法读取，暂未写入新记录。原文件已保留在 \(fileURL.path)。"
            return false
        }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated)
            try writeAtomically(data)
            records = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "历史记录保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private func writeAtomically(_ data: Data) throws {
        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = open(temporaryURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw fileError(at: temporaryURL) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        // Finish both permissions and writing before replacing the last valid history.
        // A failure after replacing it would leave the UI and the disk out of sync.
        guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw fileError(at: temporaryURL) }
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(temporaryURL.path, fileURL.path) == 0 else { throw fileError(at: fileURL) }
    }

    private func fileError(at url: URL) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}
