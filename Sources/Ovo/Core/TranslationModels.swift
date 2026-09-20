import Foundation
import NaturalLanguage

enum TranslationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }
    var code: String { rawValue }
    var title: String { self == .chinese ? "中文" : "英语" }
    var promptName: String { self == .chinese ? "Simplified Chinese" : "English" }
}

struct LanguagePair: Equatable, Sendable {
    let source: TranslationLanguage
    let target: TranslationLanguage
}

enum TranslationDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case englishToChinese
    case chineseToEnglish

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动检测"
        case .englishToChinese: return "英语 → 中文"
        case .chineseToEnglish: return "中文 → 英语"
        }
    }

    func resolved(for text: String) -> LanguagePair {
        switch self {
        case .englishToChinese: return LanguagePair(source: .english, target: .chinese)
        case .chineseToEnglish: return LanguagePair(source: .chinese, target: .english)
        case .automatic:
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese, .english]
            recognizer.processString(text)
            let language = recognizer.dominantLanguage
            var hanCount = 0
            var latinWordCount = 0
            var previousWasLatin = false
            for scalar in text.unicodeScalars {
                if scalar.properties.isIdeographic { hanCount += 1 }
                let isLatin = (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                if isLatin && !previousWasLatin { latinWordCount += 1 }
                previousWasLatin = isLatin
            }
            // The recognizer often calls short Chinese phrases containing product names
            // (e.g. "DeepSeek API 怎么配置？") English. Count Latin words, not their
            // letters, so long product names do not outweigh the Chinese sentence.
            let chineseTechnicalPhrase = hanCount >= 2 && latinWordCount <= hanCount / 2
            let ideographsOnly = hanCount > 0 && latinWordCount == 0
            let isChinese = language == .simplifiedChinese || language == .traditionalChinese
                || ideographsOnly || chineseTechnicalPhrase
            return isChinese
                ? LanguagePair(source: .chinese, target: .english)
                : LanguagePair(source: .english, target: .chinese)
        }
    }
}

enum TranslationSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case input
    case selection
    case screenshot

    var id: String { rawValue }
    var title: String {
        switch self {
        case .input: return "输入翻译"
        case .selection: return "划词翻译"
        case .screenshot: return "截图翻译"
        }
    }
    var systemImage: String {
        switch self {
        case .input: return "keyboard"
        case .selection: return "cursorarrow.and.square.on.square.dashed"
        case .screenshot: return "viewfinder"
        }
    }
}

struct TranslationRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let source: TranslationSource
    let original: String
    let translation: String
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
    let provider: TranslationProvider
    let providerName: String
    let isFavorite: Bool

    init(id: UUID = UUID(), date: Date = Date(), source: TranslationSource,
         original: String, translation: String,
         sourceLanguage: TranslationLanguage, targetLanguage: TranslationLanguage,
         isFavorite: Bool = false, provider: TranslationProvider = .deepseek, providerName: String = "DeepSeek 翻译") {
        self.id = id
        self.date = date
        self.source = source
        self.original = original
        self.translation = translation
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.isFavorite = isFavorite
        self.provider = provider
        self.providerName = providerName
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, source, original, translation, sourceLanguage, targetLanguage, isFavorite, provider, providerName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        source = try values.decode(TranslationSource.self, forKey: .source)
        original = try values.decode(String.self, forKey: .original)
        translation = try values.decode(String.self, forKey: .translation)
        sourceLanguage = try values.decode(TranslationLanguage.self, forKey: .sourceLanguage)
        targetLanguage = try values.decode(TranslationLanguage.self, forKey: .targetLanguage)
        provider = try values.decodeIfPresent(TranslationProvider.self, forKey: .provider) ?? .deepseek
        providerName = try values.decodeIfPresent(String.self, forKey: .providerName) ?? provider.title
        // Records written before favorites were introduced have no such field.
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

struct TranslationResult: Equatable, Sendable {
    let text: String
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
}
