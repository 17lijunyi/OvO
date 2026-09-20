import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var input = "" {
        didSet { if oldValue != input { invalidateTranslation() } }
    }
    @Published var output = ""
    @Published var direction: TranslationDirection = .automatic {
        didSet { if oldValue != direction { invalidateTranslation() } }
    }
    @Published var source: TranslationSource = .input
    @Published var isWorking = false
    @Published var activity = "正在翻译…"
    @Published var errorMessage: String?
    @Published var captureRetrySource: TranslationSource?
    @Published var hasAPIKey = false
    @Published var isPinned = false {
        didSet { if oldValue != isPinned { onPin(isPinned) } }
    }
    @Published var shortcutNotice: String?
    @Published var shortcutLabels: [String: String] = [:]
    @Published var pair: LanguagePair?
    @Published private(set) var currentRecord: TranslationRecord?
    let history: HistoryStore
    let configuration: ServiceConfiguration
    let customKeychain: KeychainService
    @Published var hasCustomAPIKey = false
    @Published private(set) var appleJob: AppleTranslationJob? {
        didSet { onAppleSessionChanged(appleJob != nil) }
    }
    var onAppleSessionChanged: (Bool) -> Void = { _ in }
    private var providerSubscription: AnyCancellable?
    let keychain: KeychainService
    let service = DeepSeekService()
    var onSettings: (String) -> Void = { _ in }
    var onScreenshot: () -> Void = {}
    var onOpenInput: () -> Void = {}
    var onRetryCapture: (TranslationSource) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onPin: (Bool) -> Void = { _ in }
    var onShowRecord: (TranslationRecord) -> Void = { _ in }
    var onReregisterShortcuts: () -> Void = {}
    var onPanelHeightChange: (CGFloat) -> Void = { _ in }
    private var translationTask: Task<Void, Never>?
    private var generation = UUID()

    init(history: HistoryStore? = nil, checkKey: Bool = true, keychain: KeychainService? = nil, configuration: ServiceConfiguration? = nil, customKeychain: KeychainService? = nil) {
        self.history = history ?? HistoryStore()
        self.keychain = keychain ?? KeychainService()
        self.configuration = configuration ?? ServiceConfiguration()
        self.customKeychain = customKeychain ?? KeychainService(account: "custom-api-key")
        if checkKey {
            refreshKeyStatus()
            if !self.configuration.hasSavedProvider && hasAPIKey { self.configuration.provider = .deepseek }
        }
        providerSubscription = self.configuration.$provider.dropFirst().removeDuplicates().sink { [weak self] _ in
            self?.invalidateTranslation()
        }
    }

    func refreshKeyStatus() {
        do { hasAPIKey = try keychain.containsAPIKey() }
        catch { /* An unavailable keychain does not mean a saved key was removed. */ }
        do { hasCustomAPIKey = try customKeychain.containsAPIKey() } catch {}
    }

    func cancel() {
        generation = UUID()
        translationTask?.cancel()
        translationTask = nil
        appleJob = nil
        isWorking = false
    }

    private func invalidateTranslation() {
        cancel()
        output = ""
        pair = nil
        errorMessage = nil
        captureRetrySource = nil
        currentRecord = nil
    }

    func prepare(source: TranslationSource, text: String = "") {
        cancel()
        self.source = source
        input = text
        output = ""
        pair = nil
        errorMessage = nil
        captureRetrySource = nil
        currentRecord = nil
    }

    func show(_ record: TranslationRecord) {
        prepare(source: record.source, text: record.original)
        output = record.translation
        pair = LanguagePair(source: record.sourceLanguage, target: record.targetLanguage)
        currentRecord = record
    }

    func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        cancel()
        errorMessage = nil
        captureRetrySource = nil
        output = ""
        currentRecord = nil
        guard text.count <= DeepSeekService.maximumInputLength else {
            errorMessage = DeepSeekError.inputTooLong.localizedDescription
            return
        }
        let provider = configuration.provider
        guard provider != .deepseek || configuration.isEnabled else {
            errorMessage = "DeepSeek 翻译已停用，请在服务设置中开启。"
            return
        }
        let requestID = generation
        let requestDirection = direction
        let requestSource = source
        let providerName = configuration.activeDisplayName
        let languages = requestDirection.resolved(for: text)
        pair = languages
        if provider == .apple {
            guard ServiceConfiguration.appleAvailable else {
                errorMessage = "苹果系统翻译需要 macOS 15 或以上，请升级系统或选择其他服务。"
                return
            }
            isWorking = true
            activity = "正在准备苹果系统翻译…"
            appleJob = AppleTranslationJob(id: requestID, text: text, languages: languages, source: requestSource)
            return
        }
        let requestModel = provider == .custom ? configuration.customAPIModel : configuration.effectiveModel
        let endpoint = provider == .custom ? configuration.customEndpoint : DeepSeekService.defaultEndpoint
        let requestOptions = provider == .custom
            ? DeepSeekRequestOptions(maximumOutputTokens: configuration.customTokens,
                                     temperature: configuration.customTemperature, rolePrompt: configuration.customRolePrompt)
            : DeepSeekRequestOptions(thinkingEnabled: configuration.thinkingEnabled,
                                     maximumOutputTokens: configuration.maximumOutputTokens,
                                     temperature: configuration.temperature, rolePrompt: configuration.rolePrompt)
        let key: String
        do {
            // Validate destination before requesting access to saved credentials.
            _ = try DeepSeekService.completionsURL(endpoint: endpoint, allowLocalHTTP: provider == .custom)
            guard !requestModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeepSeekError.invalidModel }
            key = try (provider == .custom ? customKeychain : keychain).getAPIKey() ?? ""
            guard generation == requestID else { return }
            if provider == .deepseek {
                hasAPIKey = !key.isEmpty
                guard hasAPIKey else { throw DeepSeekError.missingAPIKey }
            } else { hasCustomAPIKey = !key.isEmpty }
        } catch {
            guard generation == requestID else { return }
            errorMessage = error.localizedDescription
            return
        }
        isWorking = true
        activity = "\(providerName)正在翻译…"
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.translate(text: text, direction: requestDirection, apiKey: key,
                    endpoint: endpoint, model: requestModel, options: requestOptions, compatibleAPI: provider == .custom)
                guard !Task.isCancelled else { return }
                completeTranslation(result, requestID: requestID, original: text, source: requestSource,
                                    provider: provider, providerName: providerName)
            } catch {
                guard !Task.isCancelled, generation == requestID else { return }
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func completeTranslation(_ result: TranslationResult, requestID: UUID, original: String,
                             source: TranslationSource, provider: TranslationProvider, providerName: String) {
        guard generation == requestID else { return }
        output = result.text
        pair = LanguagePair(source: result.sourceLanguage, target: result.targetLanguage)
        let record = TranslationRecord(source: source, original: original, translation: result.text,
            sourceLanguage: result.sourceLanguage, targetLanguage: result.targetLanguage,
            provider: provider, providerName: providerName)
        currentRecord = record
        if UserDefaults.standard.object(forKey: "saveHistory") as? Bool ?? true { history.add(record) }
        isWorking = false
        appleJob = nil
    }

    func appleActivity(_ message: String, jobID: UUID) {
        guard appleJob?.id == jobID else { return }
        activity = message
    }

    func failAppleTranslation(_ message: String, jobID: UUID) {
        guard generation == jobID, appleJob?.id == jobID else { return }
        appleJob = nil
        isWorking = false
        errorMessage = message
    }

    func swapLanguages() {
        let resolved = pair ?? direction.resolved(for: input)
        let previousOutput = output
        cancel()
        direction = resolved.target == .english ? .englishToChinese : .chineseToEnglish
        if !previousOutput.isEmpty { input = previousOutput }
        output = ""
        pair = nil
        currentRecord = nil
    }

    var currentIsFavorite: Bool {
        guard let record = currentRecord else { return false }
        return history.records.first(where: { $0.id == record.id })?.isFavorite ?? false
    }

    var canRetry: Bool { captureRetrySource != nil || !input.isEmpty }

    var retryTitle: String {
        switch captureRetrySource {
        case .selection: return "重新取词"
        case .screenshot: return "重新截图"
        default: return "重试"
        }
    }

    func retry() {
        if let captureRetrySource { onRetryCapture(captureRetrySource) }
        else { translate() }
    }

    func toggleFavorite() {
        guard let record = currentRecord else { return }
        if history.records.contains(where: { $0.id == record.id }) {
            history.toggleFavorite(id: record.id)
        } else {
            history.add(TranslationRecord(id: record.id, date: record.date, source: record.source,
                                          original: record.original, translation: record.translation,
                                          sourceLanguage: record.sourceLanguage, targetLanguage: record.targetLanguage,
                                          isFavorite: true, provider: record.provider, providerName: record.providerName))
        }
    }
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
