import Combine
import Foundation

enum TranslationProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple, deepseek, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: return "苹果系统翻译"
        case .deepseek: return "DeepSeek 翻译"
        case .custom: return "自定义 API"
        }
    }
}

/// Preferences for translation providers.
/// Credentials are deliberately kept out of preferences and stay in KeychainService.
@MainActor
final class ServiceConfiguration: ObservableObject {
    @Published var provider: TranslationProvider {
        didSet { defaults.set(provider.rawValue, forKey: "service.provider") }
    }
    @Published var customName: String { didSet { defaults.set(customName, forKey: "service.custom.name") } }
    @Published var customEndpoint: String { didSet { defaults.set(customEndpoint, forKey: "service.custom.endpoint") } }
    @Published var customAPIModel: String { didSet { defaults.set(customAPIModel, forKey: "service.custom.model") } }
    @Published var customTokens: Int { didSet { defaults.set(customTokens, forKey: "service.custom.tokens") } }
    @Published var customTemperature: Double { didSet { defaults.set(customTemperature, forKey: "service.custom.temperature") } }
    @Published var customRolePrompt: String { didSet { defaults.set(customRolePrompt, forKey: "service.custom.prompt") } }
    var hasSavedProvider: Bool { defaults.string(forKey: "service.provider") != nil }
    static var appleAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
    var activeDisplayName: String { displayName(for: provider) }
    func displayName(for provider: TranslationProvider) -> String {
        switch provider {
        case .apple: return provider.title
        case .deepseek: return effectiveDisplayName
        case .custom:
            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? provider.title : name
        }
    }
    static let officialModels = [DeepSeekService.defaultModel, "deepseek-v4-pro"]
    static let customModelOption = "custom"
    static let outputTokenOptions = [512, 1024, 2048, 4096, 8192, 16384, 32768]
    static let temperatureOptions = (0...20).map { Double($0) / 10 }

    @Published var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.displayName) }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) }
    }
    @Published var customModel: String {
        didSet { defaults.set(customModel, forKey: Keys.customModel) }
    }
    @Published var thinkingEnabled: Bool {
        didSet { defaults.set(thinkingEnabled, forKey: Keys.thinkingEnabled) }
    }
    @Published var maximumOutputTokens: Int {
        didSet { defaults.set(maximumOutputTokens, forKey: Keys.maximumOutputTokens) }
    }
    @Published var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }
    @Published var rolePrompt: String {
        didSet { defaults.set(rolePrompt, forKey: Keys.rolePrompt) }
    }

    var effectiveModel: String {
        let value = selectedModel == Self.customModelOption ? customModel : selectedModel
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveDisplayName: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "DeepSeek 翻译" : value
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let legacy = defaults.object(forKey: Keys.selectedModel) != nil || defaults.object(forKey: Keys.isEnabled) != nil
        provider = defaults.string(forKey: "service.provider").flatMap(TranslationProvider.init(rawValue:))
            ?? (legacy || !Self.appleAvailable ? .deepseek : .apple)
        customName = defaults.string(forKey: "service.custom.name") ?? "自定义 API"
        customEndpoint = defaults.string(forKey: "service.custom.endpoint") ?? ""
        customAPIModel = defaults.string(forKey: "service.custom.model") ?? ""
        let tokens = defaults.integer(forKey: "service.custom.tokens")
        customTokens = Self.outputTokenOptions.contains(tokens) ? tokens : 1024
        let temp = defaults.double(forKey: "service.custom.temperature")
        customTemperature = temp.isFinite && (0...2).contains(temp) ? temp : 0
        customRolePrompt = defaults.string(forKey: "service.custom.prompt") ?? ""
        displayName = defaults.string(forKey: Keys.displayName) ?? "DeepSeek 翻译"
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        let storedModel = defaults.string(forKey: Keys.selectedModel) ?? DeepSeekService.defaultModel
        selectedModel = Self.officialModels.contains(storedModel) || storedModel == Self.customModelOption
            ? storedModel : DeepSeekService.defaultModel
        customModel = defaults.string(forKey: Keys.customModel) ?? ""
        thinkingEnabled = defaults.object(forKey: Keys.thinkingEnabled) as? Bool ?? false
        let storedTokens = defaults.object(forKey: Keys.maximumOutputTokens) as? Int ?? 1024
        maximumOutputTokens = Self.outputTokenOptions.contains(storedTokens) ? storedTokens : 1024
        let storedTemperature = defaults.object(forKey: Keys.temperature) as? Double ?? 0
        temperature = Self.temperatureOptions.contains(storedTemperature) ? storedTemperature : 0
        rolePrompt = defaults.string(forKey: Keys.rolePrompt) ?? ""
    }

    private enum Keys {
        static let displayName = "service.deepseek.displayName"
        static let isEnabled = "service.deepseek.isEnabled"
        static let selectedModel = "service.deepseek.selectedModel"
        static let customModel = "service.deepseek.customModel"
        static let thinkingEnabled = "service.deepseek.thinkingEnabled"
        static let maximumOutputTokens = "service.deepseek.maximumOutputTokens"
        static let temperature = "service.deepseek.temperature"
        static let rolePrompt = "service.deepseek.rolePrompt"
    }
}
