import SwiftUI

struct CustomAPISettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var configuration: ServiceConfiguration
    @State private var keyDraft = ""
    @State private var reveal = false
    @State private var testing = false
    @State private var message: String?
    @State private var failed = false
    @State private var confirmRemove = false
    @State private var testTask: Task<Void, Never>?
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("接入支持 OpenAI Chat Completions 格式的服务。配置会自动保存，密钥需单独点击保存。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            field("服务名称", placeholder: "自定义 API", text: $configuration.customName)
            field("API 地址", placeholder: "https://example.com/v1", text: $configuration.customEndpoint)
            Text("可填写基础地址或完整 /chat/completions 地址。远程服务需 HTTPS；本机服务支持 http://localhost 或 127.0.0.1。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            field("模型名称", placeholder: "填写服务商提供的模型 ID", text: $configuration.customAPIModel)
            Divider()
            Text("API Key").fontWeight(.medium)
            HStack {
                Group {
                    if reveal { TextField(keyPlaceholder, text: $keyDraft) }
                    else { SecureField(keyPlaceholder, text: $keyDraft) }
                }.textFieldStyle(.roundedBorder).accessibilityLabel("自定义 API Key")
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .disabled(keyDraft.isEmpty).accessibilityLabel("显示或隐藏自定义密钥")
            }
            Text(state.hasCustomAPIKey ? "密钥已保存在系统钥匙串，与 DeepSeek 密钥独立。" : "需要鉴权的服务请填写密钥；无鉴权的本机服务可留空。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("翻译内容和此密钥将发送到上方配置的 API 地址。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("保存密钥", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if state.hasCustomAPIKey { Button("移除密钥") { confirmRemove = true } }
            }
            Divider()
            Picker("最大输出 token 数", selection: $configuration.customTokens) {
                ForEach(ServiceConfiguration.outputTokenOptions, id: \.self) { Text("\($0) tokens").tag($0) }
            }
            Picker("温度", selection: $configuration.customTemperature) {
                ForEach(ServiceConfiguration.temperatureOptions, id: \.self) {
                    Text(String(format: "%.1f", $0)).tag($0)
                }
            }
            Text("翻译偏好（可选）").fontWeight(.medium)
            TextEditor(text: $configuration.customRolePrompt).font(.system(size: 13))
                .frame(height: 80).overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.2)))
                .accessibilityLabel("自定义翻译偏好")
            Button(testing ? "正在测试…" : "测试连接", action: test).buttonStyle(.borderedProminent)
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(failed ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(testing)
        .alert("移除自定义 API Key？", isPresented: $confirmRemove) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                do {
                    try state.customKeychain.deleteAPIKey()
                    state.hasCustomAPIKey = false
                    keyDraft = ""
                    reveal = false
                    message = "密钥已移除。"; failed = false
                } catch { message = error.localizedDescription; failed = true }
            }
        }
        .onChange(of: configuration.customEndpoint) { message = nil }
        .onChange(of: configuration.customAPIModel) { message = nil }
        .onChange(of: keyDraft) { message = nil }
        .onDisappear {
            requestID = UUID()
            testTask?.cancel(); testTask = nil; testing = false
            keyDraft = ""; reveal = false
        }
    }

    private var keyPlaceholder: String { state.hasCustomAPIKey ? "已保存，输入新密钥可替换" : "API Key（本机无鉴权服务可留空）" }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.medium)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).accessibilityLabel("自定义\(title)")
        }
    }

    private func saveKey() {
        do {
            let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { throw DeepSeekError.invalidAPIKey }
            try state.customKeychain.saveAPIKey(key)
            state.hasCustomAPIKey = true
            keyDraft = ""; reveal = false
            message = "API Key 已安全保存。"; failed = false
        } catch { message = error.localizedDescription; failed = true }
    }

    private func test() {
        let id = UUID(); requestID = id
        let endpoint = configuration.customEndpoint
        let model = configuration.customAPIModel
        let draft = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = DeepSeekRequestOptions(maximumOutputTokens: configuration.customTokens,
            temperature: configuration.customTemperature, rolePrompt: configuration.customRolePrompt)
        testing = true; message = nil
        testTask = Task { @MainActor in
            defer { if requestID == id { testing = false; testTask = nil } }
            do {
                _ = try DeepSeekService.completionsURL(endpoint: endpoint, allowLocalHTTP: true)
                guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DeepSeekError.invalidModel }
                let key = draft.isEmpty ? (try state.customKeychain.getAPIKey() ?? "") : draft
                _ = try await state.service.translate(text: "Hello", direction: .englishToChinese,
                    apiKey: key, endpoint: endpoint, model: model, options: options, compatibleAPI: true)
                guard !Task.isCancelled, requestID == id else { return }
                message = draft.isEmpty ? "连接成功，可以开始翻译。" : "连接成功，请保存密钥后使用。"
                failed = false
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                message = error.localizedDescription; failed = true
            }
        }
    }
}
