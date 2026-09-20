import AppKit
import SwiftUI

struct ServiceSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var configuration: ServiceConfiguration
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewedProvider: TranslationProvider = .apple
    @State private var keyDraft = ""
    @State private var revealKey = false
    @State private var testing = false
    @State private var message: String?
    @State private var isError = false
    @State private var confirmDelete = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionID = UUID()

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            serviceList
                .frame(width: 253)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    providerActivation
                    sectionDivider
                    if viewedProvider == .apple {
                        appleSection
                    } else if viewedProvider == .custom {
                        CustomAPISettingsView(state: state, configuration: configuration)
                    } else {
                    Toggle("启用 DeepSeek 翻译", isOn: $configuration.isEnabled)
                        .toggleStyle(.switch).controlSize(.small).padding(.bottom, 12)
                    serviceNameSection
                    sectionDivider
                    instructionsSection
                    sectionDivider
                    modeSection
                    sectionDivider
                    apiKeySection
                    sectionDivider
                    modelSection
                    sectionDivider
                    customModelSection
                    sectionDivider
                    thinkingSection
                    sectionDivider
                    outputTokensSection
                    sectionDivider
                    temperatureSection
                    sectionDivider
                    rolePromptSection
                    sectionDivider
                    actionsSection
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(cardSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardBorder, lineWidth: 0.5))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 18)
        .alert("移除 DeepSeek API Key？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive, action: deleteKey)
        } message: {
            Text("移除后，需要重新填写密钥才能翻译。历史记录会保留。")
        }
        .onAppear { viewedProvider = configuration.provider }
        .onChange(of: viewedProvider) {
            connectionID = UUID()
            connectionTask?.cancel()
            connectionTask = nil
            testing = false
            revealKey = false
            keyDraft = ""
            message = nil
        }
        .onDisappear {
            connectionID = UUID()
            connectionTask?.cancel()
            connectionTask = nil
            testing = false
            revealKey = false
        }
    }

    private var serviceList: some View {
        VStack(spacing: 0) {
            ForEach(TranslationProvider.allCases) { provider in
                Button { viewedProvider = provider } label: {
                    HStack(spacing: 8) {
                        ProviderMark(provider: provider)
                        Text(configuration.displayName(for: provider)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(provider == .apple ? "免费" : (provider == .custom ? "自定义" : "密钥"))
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(provider == .apple ? Color.green : Color.blue, in: Capsule())
                        Image(systemName: configuration.provider == provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(configuration.provider == provider ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 10).frame(height: 44)
                    .contentShape(Rectangle())
                    .background(viewedProvider == provider ? Color.primary.opacity(0.11) : Color.clear)
                }.buttonStyle(.plain).accessibilityLabel(provider.title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardBorder, lineWidth: 0.5))
    }

    private var providerActivation: some View {
        HStack {
            Text(configuration.displayName(for: viewedProvider)).font(.system(size: 15, weight: .semibold))
            Spacer()
            if configuration.provider == viewedProvider {
                Label("当前服务", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
            } else {
                Button("设为当前服务") {
                    if viewedProvider == .deepseek { configuration.isEnabled = true }
                    configuration.provider = viewedProvider
                }.buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(viewedProvider == .apple && !ServiceConfiguration.appleAvailable)
            }
        }
    }

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("免费 · 无需 API Key", systemImage: "checkmark.seal")
                .font(.system(size: 15, weight: .medium))
            detailText("使用苹果系统提供的翻译能力，在本机完成中文与英文互译，无需注册账号或购买 API 额度。")
            Divider()
            sectionTitle("首次使用")
            detailText("首次翻译时，macOS 可能请求下载中英文语言包。确认下载后即可使用；语言包由系统管理。")
            detailText("划词、截图和输入翻译共用此服务。划词与截图仍需相应的系统权限。")
            if ServiceConfiguration.appleAvailable {
                Button("打开系统翻译") {
                    configuration.provider = .apple
                    state.onOpenInput()
                }.buttonStyle(.borderedProminent)
            } else {
                Label("需要 macOS 15 或以上", systemImage: "info.circle").foregroundStyle(.orange)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serviceNameSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("服务名称")
            TextField("DeepSeek 翻译", text: $configuration.displayName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 7)
                .frame(height: 23)
                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(fieldBorder, lineWidth: 1))
                .accessibilityLabel("服务名称")
                .disabled(testing)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("使用须知")
                Spacer()
                Button("查看申请教程") {
                    if let url = URL(string: "https://api-docs.deepseek.com/zh-cn/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(ServiceControlButtonStyle())
            }
            detailText("使用本服务需自行申请密钥并填写到下方设置项，如果没有密钥请查看申请教程。")
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("模式")
                Spacer()
                serviceMenu("翻译", width: 134, selectedValue: "translation",
                            items: [ChoiceMenuItem(title: "翻译", value: "translation")],
                            onSelect: { _ in })
                .accessibilityLabel("翻译模式")
            }
            detailText("「翻译」模式会将文本翻译为目标语言，支持中文和英文互译。源语言会根据输入内容自动识别，也可以在翻译窗口手动切换。")
            detailText("划词、截图和输入翻译共用当前服务配置。")
                .padding(.top, 7)
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("API Key")
            HStack(alignment: .top, spacing: 7) {
                Group {
                    if revealKey {
                        TextField(keyPlaceholder, text: $keyDraft)
                    } else {
                        SecureField(keyPlaceholder, text: $keyDraft)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 7)
                .padding(.top, 7)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: 41, alignment: .topLeading)
                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(fieldBorder, lineWidth: 1))
                .accessibilityLabel("DeepSeek API Key")
                .disabled(testing)
                .onChange(of: keyDraft) { if !keyDraft.isEmpty { message = nil } }

                Button { revealKey.toggle() } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                        .font(.system(size: 13))
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(ServiceControlButtonStyle(horizontalPadding: 5))
                .help(revealKey ? "隐藏输入的 API Key" : "显示输入的 API Key")
                .accessibilityLabel(revealKey ? "隐藏 API Key" : "显示 API Key")
                .disabled(testing || keyDraft.isEmpty)
            }
            detailText(state.hasAPIKey
                       ? "密钥已保存在系统钥匙串。填写新密钥并保存可替换。"
                       : "需要填写 API Key 才可以使用，参考上方申请教程。")
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("模型")
                Spacer()
                serviceMenu(configuration.selectedModel == ServiceConfiguration.customModelOption
                            ? "自定义模型" : configuration.selectedModel, width: 166,
                            selectedValue: configuration.selectedModel,
                            items: ServiceConfiguration.officialModels.map { ChoiceMenuItem(title: $0, value: $0) }
                                + [ChoiceMenuItem(title: "自定义模型", value: ServiceConfiguration.customModelOption)]) { model in
                    configuration.selectedModel = model
                    message = nil
                }
                .accessibilityLabel("DeepSeek 模型")
                .disabled(testing)
            }
            detailText("如果想要自行设置模型，请将此选项设置为「自定义模型」，并在下方输入框填入需要使用的模型名称。")
        }
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("自定义模型")
            TextField("e.g. deepseek-flash", text: $configuration.customModel)
                .textFieldStyle(.plain)
                .padding(.horizontal, 7)
                .frame(height: 23)
                .background(fieldSurface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(fieldBorder, lineWidth: 1))
                .accessibilityLabel("自定义模型名称")
                .disabled(testing || configuration.selectedModel != ServiceConfiguration.customModelOption)
                .onChange(of: configuration.customModel) { message = nil }
            detailText("此设置仅在「模型」选项设置为「自定义模型」时生效，请输入正确的模型名称。")
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("深度思考")
                Spacer()
                serviceMenu(configuration.thinkingEnabled ? "启用思考" : "禁用思考", width: 100,
                            selectedValue: configuration.thinkingEnabled ? "enabled" : "disabled",
                            items: [ChoiceMenuItem(title: "禁用思考", value: "disabled"),
                                    ChoiceMenuItem(title: "启用思考", value: "enabled")]) { value in
                    configuration.thinkingEnabled = value == "enabled"
                    message = nil
                }
                .accessibilityLabel("深度思考")
                .disabled(testing)
            }
            detailText("仅部分模型支持通过此设置控制深度思考能力的启用状态，主要用于同时支持思考模式和非思考模式的模型。")
        }
    }

    private var outputTokensSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("最大输出 token 数")
                Spacer()
                serviceMenu("\(configuration.maximumOutputTokens) tokens", width: 125,
                            selectedValue: String(configuration.maximumOutputTokens),
                            items: ServiceConfiguration.outputTokenOptions.map {
                                ChoiceMenuItem(title: "\($0) tokens", value: String($0))
                            }) { value in
                    guard let tokenCount = Int(value) else { return }
                    configuration.maximumOutputTokens = tokenCount
                    message = nil
                }
                .accessibilityLabel("最大输出 token 数")
                .disabled(testing)
            }
            detailText("用于限制 DeepSeek 返回结果时输出的最大 token 数量。")
        }
    }

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("温度")
                Spacer()
                serviceMenu(temperatureLabel(configuration.temperature), width: 67,
                            selectedValue: temperatureLabel(configuration.temperature),
                            items: ServiceConfiguration.temperatureOptions.map {
                                ChoiceMenuItem(title: temperatureLabel($0), value: temperatureLabel($0))
                            }) { value in
                    guard let temperature = Double(value) else { return }
                    configuration.temperature = temperature
                    message = nil
                }
                .accessibilityLabel("温度")
                .disabled(testing)
            }
            detailText("温度（temperature）参数用于控制生成文本的随机性。温度值越低，生成文本的确定性越强；值越高，生成文本的随机性和创造性越强。")
        }
    }

    private var rolePromptSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("角色设定")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $configuration.rolePrompt)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 4)
                    .frame(height: 96)
                    .accessibilityLabel("角色设定")
                    .disabled(testing)
                    .onChange(of: configuration.rolePrompt) { message = nil }
                if configuration.rolePrompt.isEmpty {
                    Text("例如：\n你是一个翻译器")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(7)
                        .allowsHitTesting(false)
                }
            }
            .background(fieldSurface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(fieldBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedDraft.isEmpty || testing)
                Button(testing ? "正在测试…" : "测试连接", action: test)
                    .disabled(testing || (!state.hasAPIKey && trimmedDraft.isEmpty) || configuration.effectiveModel.isEmpty)
                Spacer(minLength: 0)
                if state.hasAPIKey {
                    Button("移除密钥") { confirmDelete = true }
                        .foregroundStyle(.secondary)
                        .disabled(testing)
                }
            }
            .controlSize(.small)
            if let message {
                Label(message, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var keyPlaceholder: String {
        state.hasAPIKey ? "••••••••••••••••••••••••••••••••" : "输入你的 DeepSeek API Key"
    }
    private var trimmedDraft: String { keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cardSurface: Color { Color.white.opacity(colorScheme == .dark ? 0.045 : 0.27) }
    private var cardBorder: Color { Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18) }
    private var fieldSurface: Color { Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.45 : 0.84) }
    private var fieldBorder: Color { Color.primary.opacity(0.07) }
    private var sectionDivider: some View { Divider().opacity(0.45).padding(.vertical, 12) }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .medium))
    }

    private func detailText(_ value: String) -> some View {
        Text(value).font(.system(size: 11)).foregroundStyle(.secondary)
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    private func temperatureLabel(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func serviceMenu(_ title: String, width: CGFloat, selectedValue: String,
                             items: [ChoiceMenuItem], onSelect: @escaping (String) -> Void) -> some View {
        ChoiceMenu(title: title, selectedValue: selectedValue, items: items, onSelect: onSelect) {
            HStack(spacing: 0) {
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold)).frame(width: 10)
            }
            .padding(.horizontal, 11)
            .frame(width: width, height: 24)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.065), in: RoundedRectangle(cornerRadius: 7))
        }
        .fixedSize()
    }

    private func save() {
        do {
            guard !trimmedDraft.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                throw DeepSeekError.invalidAPIKey
            }
            try state.keychain.saveAPIKey(trimmedDraft)
            keyDraft = ""
            revealKey = false
            state.hasAPIKey = true
            message = "API Key 已安全保存。"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func deleteKey() {
        do {
            try state.keychain.deleteAPIKey()
            state.hasAPIKey = false
            keyDraft = ""
            revealKey = false
            message = "已移除 API Key。"
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    private func test() {
        let model = configuration.effectiveModel
        let options = DeepSeekRequestOptions(
            thinkingEnabled: configuration.thinkingEnabled,
            maximumOutputTokens: configuration.maximumOutputTokens,
            temperature: configuration.temperature,
            rolePrompt: configuration.rolePrompt
        )
        let draft = trimmedDraft
        let isSavedKey = draft.isEmpty
        let requestID = UUID()
        connectionID = requestID
        testing = true
        message = nil
        connectionTask = Task { @MainActor in
            defer {
                if connectionID == requestID { testing = false; connectionTask = nil }
            }
            do {
                try Task.checkCancellation()
                guard connectionID == requestID else { return }
                let key = isSavedKey ? (try state.keychain.getAPIKey() ?? "") : draft
                try await state.service.testConnection(apiKey: key, model: model, options: options)
                guard !Task.isCancelled, connectionID == requestID else { return }
                message = isSavedKey ? "连接成功，可以开始翻译。" : "连接成功。点击「保存」后即可使用。"
                isError = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, connectionID == requestID else { return }
                message = error.localizedDescription
                isError = true
            }
        }
    }
}

private struct ServiceControlButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.065), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}
