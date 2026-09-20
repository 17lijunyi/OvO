import SwiftUI
import Translation

struct AppleTranslationJob: Identifiable {
    let id: UUID
    let text: String
    let languages: LanguagePair
    let source: TranslationSource
}

/// The session belongs to the visible translation panel, so macOS can present
/// its language download UI. Each request gets a fresh view/session identity.
@available(macOS 15.0, *)
struct AppleTranslationRunner: View {
    @ObservedObject var state: AppState
    let job: AppleTranslationJob

    private var sourceLanguage: Locale.Language {
        Locale.Language(identifier: job.languages.source == .chinese ? "zh-Hans" : "en")
    }
    private var targetLanguage: Locale.Language {
        Locale.Language(identifier: job.languages.target == .chinese ? "zh-Hans" : "en")
    }

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationTask(source: sourceLanguage, target: targetLanguage) { session in
                do {
                    let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
                    try Task.checkCancellation()
                    guard state.appleJob?.id == job.id else { return }
                    guard status != .unsupported else {
                        state.failAppleTranslation("此设备暂不支持所选语言的系统翻译，请选择其他服务。", jobID: job.id)
                        return
                    }
                    if status != .installed {
                        state.appleActivity("请确认下载中英文语言包…", jobID: job.id)
                        try await session.prepareTranslation()
                    }
                    try Task.checkCancellation()
                    guard state.appleJob?.id == job.id else { return }
                    state.appleActivity("苹果系统正在翻译…", jobID: job.id)
                    let response = try await session.translate(job.text)
                    try Task.checkCancellation()
                    let text = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { throw DeepSeekError.emptyResponse }
                    state.completeTranslation(TranslationResult(text: text, sourceLanguage: job.languages.source,
                        targetLanguage: job.languages.target), requestID: job.id, original: job.text,
                        source: job.source, provider: .apple, providerName: TranslationProvider.apple.title)
                } catch {
                    state.failAppleTranslation("系统翻译未完成：\(error.localizedDescription) 可重试并确认语言包下载，或选择其他服务。", jobID: job.id)
                }
            }
    }
}

struct ProviderMark: View {
    let provider: TranslationProvider
    var size: CGFloat = 16
    var body: some View {
        if provider == .deepseek {
            DeepSeekMark(size: size)
        } else {
            Image(systemName: provider == .apple ? "apple.logo" : "network")
                .font(.system(size: size - 2, weight: .medium))
                .foregroundStyle(provider == .apple ? Color.primary : Color.accentColor)
                .frame(width: size, height: size)
        }
    }
}
