import AppKit
import SwiftUI

struct TranslationView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var configuration: ServiceConfiguration
    @ObservedObject private var history: HistoryStore
    @ObservedObject private var speech = SpeechService.shared
    @State private var resultExpanded = true
    @State private var copied = false
    @AppStorage("historyCleanupThreshold") private var cleanupThreshold = HistoryStore.defaultCleanupThreshold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: AppState) {
        self.state = state
        configuration = state.configuration
        history = state.history
    }

    private var editorHeight: CGFloat { state.source == .input ? 104 : 89 }
    private var languagePair: LanguagePair { state.pair ?? state.direction.resolved(for: state.input) }
    private var detailHeight: CGFloat {
        guard resultExpanded else { return 0 }
        if state.isWorking { return 46 }
        if state.errorMessage != nil { return 92 }
        guard !state.output.isEmpty else { return 0 }
        let bounds = (state.output as NSString).boundingRect(
            with: NSSize(width: 348, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14)])
        return min(max(ceil(bounds.height) + 48, 70), 270)
    }
    private var desiredHeight: CGFloat { 129 + editorHeight + detailHeight + (history.errorMessage == nil ? 0 : 36) + (history.shouldSuggestCleanup(at: cleanupThreshold) ? 32 : 0) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: 41)
            VStack(spacing: 8) {
                inputCard.frame(height: editorHeight)
                languageBar.frame(height: 30)
                serviceCard
                if history.shouldSuggestCleanup(at: cleanupThreshold) {
                    HStack(spacing: 6) {
                        Text("历史记录已达 \(history.records.count) 条，建议清理。")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("去整理") { state.onSettings("history") }.controlSize(.mini)
                    }.frame(height: 24)
                }
                if let error = history.errorMessage {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FrostedGlassBackground())
        .background {
            if #available(macOS 15.0, *), let job = state.appleJob {
                AppleTranslationRunner(state: state, job: job).id(job.id)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.65), lineWidth: 0.75))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.17), lineWidth: 0.5))
        .preferredColorScheme(.light)
        .ignoresSafeArea()
        .onAppear { state.onPanelHeightChange(desiredHeight) }
        .onChange(of: desiredHeight) { state.onPanelHeightChange(desiredHeight) }
        .onChange(of: state.output) { if !state.output.isEmpty { resultExpanded = true } }
        .onChange(of: state.errorMessage) { if state.errorMessage != nil { resultExpanded = true } }
        .onChange(of: state.isWorking) { if state.isWorking { resultExpanded = true } }
        .onExitCommand(perform: state.onClose)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { state.isPinned.toggle() } label: {
                Image(systemName: "pin.fill")
                    .font(.system(size: 18, weight: .medium))
                    .rotationEffect(.degrees(state.isPinned ? 0 : -28))
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55), value: state.isPinned)
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PinButtonStyle())
            .foregroundStyle(state.isPinned ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
            .help(state.isPinned ? "取消置顶，切换应用时自动收起" : "置顶，切换应用时保留窗口")
            .accessibilityLabel(state.isPinned ? "取消置顶" : "窗口置顶")
            .accessibilityValue(state.isPinned ? "已置顶" : "未置顶，切换应用时自动收起")
            Spacer(minLength: 0)
            Button(action: state.toggleFavorite) {
                ZStack {
                    Image(systemName: "star.fill").font(.system(size: 19, weight: .medium))
                    SmileMark().stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        .frame(width: 9, height: 4).offset(y: 2)
                }.frame(width: 18, height: 26)
            }.buttonStyle(.plain).foregroundStyle(state.currentIsFavorite ? Color.orange : Color(nsColor: .secondaryLabelColor))
                .disabled(state.currentRecord == nil).help("收藏当前翻译").accessibilityLabel("收藏当前翻译")
                .contextMenu {
                    Button("查看收藏") { state.onSettings("favorites") }
                    Button("查看历史记录") { state.onSettings("history") }
                }
            toolbarButton("截图翻译", "scissors", action: state.onScreenshot)
            toolbarButton("翻译服务", "cube.fill") { state.onSettings("service") }
            Button { state.onSettings("translation") } label: {
                SwitchesMark().frame(width: 17, height: 18).frame(width: 18, height: 26)
            }.buttonStyle(.plain).foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .help("偏好设置").accessibilityLabel("偏好设置")
        }.padding(.horizontal, 16)
            .background(WindowDragArea())
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            InputEditor(text: $state.input, onSubmit: state.translate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help("Enter 翻译，Shift + Enter 换行")
            HStack(spacing: 11) {
                inputAction("朗读原文", speech.speakingText == state.input && !state.input.isEmpty ? "stop.fill" : "speaker.wave.2") {
                    speech.toggle(text: state.input, languageCode: languagePair.source == .chinese ? "zh-CN" : "en-US")
                }
                inputAction("复制原文", "square.on.square") { if !state.input.isEmpty { copyText(state.input) } }
                Spacer()
                if state.isWorking {
                    Button("停止", action: state.cancel).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12).frame(height: 29).padding(.bottom, 2)
        }.background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .glassCard()
    }

    private var languageBar: some View {
        HStack(spacing: 0) {
            languageMenu(isSource: true).frame(maxWidth: .infinity)
            Button(action: state.swapLanguages) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .regular)).frame(width: 34, height: 30)
            }.buttonStyle(.plain).help("交换语言").accessibilityLabel("交换翻译方向")
            languageMenu(isSource: false).frame(maxWidth: .infinity)
        }.background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9)).glassCard()
    }

    private func languageMenu(isSource: Bool) -> some View {
        let title = state.direction == .automatic ? (isSource ? "自动检测" : "自动选择")
            : (isSource ? languagePair.source : languagePair.target).title.replacingOccurrences(of: "中文", with: "中文简体")
        let selected = state.direction == .automatic ? "auto" : (isSource ? languagePair.source : languagePair.target).rawValue
        return ChoiceMenu(title: isSource ? "原文语言" : "目标语言", selectedValue: selected, items: [
            ChoiceMenuItem(title: isSource ? "自动检测" : "自动选择", value: "auto"),
            ChoiceMenuItem(title: "中文简体", value: "zh"),
            ChoiceMenuItem(title: "英语", value: "en")
        ], onSelect: { value in
            if value == "auto" { state.direction = .automatic }
            else if value == "zh" { state.direction = isSource ? .chineseToEnglish : .englishToChinese }
            else { state.direction = isSource ? .englishToChinese : .chineseToEnglish }
        }) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 13))
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
            }.frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
        }
    }

    private var serviceCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ProviderMark(provider: state.currentRecord?.provider ?? configuration.provider)
                Text(state.currentRecord?.providerName ?? configuration.activeDisplayName)
                    .font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
                if state.source == .input {
                    inputAction("翻译服务设置", "slider.horizontal.3") { state.onSettings("service") }
                }
                Button {
                    if state.output.isEmpty && state.errorMessage == nil && !state.isWorking { state.onSettings("service") }
                    else { resultExpanded.toggle() }
                } label: {
                    Image(systemName: resultExpanded ? "chevron.left" : "chevron.down")
                        .font(.system(size: 12, weight: .medium)).frame(width: 20, height: 28)
                }.buttonStyle(.plain).help("展开或收起译文").accessibilityLabel("展开或收起译文")
            }.padding(.horizontal, 10).frame(height: 30)
            if detailHeight > 0 {
                Divider().opacity(0.3).padding(.horizontal, 10)
                serviceDetails.frame(height: max(detailHeight - 1, 0))
            }
        }.background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9)).glassCard()
    }

    @ViewBuilder private var serviceDetails: some View {
        if state.isWorking {
            HStack(spacing: 9) {
                ProgressView().controlSize(.mini)
                Text(state.activity).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 12)
        } else if let error = state.errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("服务设置") { state.onSettings("service") }
                    Button("权限设置") { state.onSettings("general") }
                    Spacer()
                    if state.canRetry { Button(state.retryTitle, action: state.retry) }
                }.controlSize(.small)
            }.padding(12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Text(state.output).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10)
                }
                HStack(spacing: 11) {
                    inputAction("朗读译文", speech.speakingText == state.output ? "stop.fill" : "speaker.wave.2") {
                        speech.toggle(text: state.output, languageCode: languagePair.target == .chinese ? "zh-CN" : "en-US")
                    }
                    inputAction(copied ? "已复制" : "复制译文", copied ? "checkmark" : "square.on.square") {
                        copyText(state.output); copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    Spacer()
                    inputAction("重新翻译", "arrow.clockwise", action: state.translate)
                }.padding(.horizontal, 12).frame(height: 32)
            }
        }
    }

    private func toolbarButton(_ label: String, _ symbol: String,
                               color: Color = Color(nsColor: .secondaryLabelColor),
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 18, height: 26)
        }.buttonStyle(.plain).foregroundStyle(color).help(label).accessibilityLabel(label)
    }
    private func inputAction(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 16, height: 22)
        }.buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.9)).help(label).accessibilityLabel(label)
    }
}

private struct PinButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.80 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct SmileMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.midX, y: rect.height * 1.6)) }
    }
}

private struct SwitchesMark: View {
    var body: some View {
        VStack(spacing: 3) {
            Capsule().strokeBorder(lineWidth: 1.6).overlay(alignment: .leading) { Circle().fill().frame(width: 4, height: 4).padding(.leading, 2.5) }
            Capsule().fill().overlay(alignment: .trailing) { Circle().fill(Color.white).frame(width: 4, height: 4).padding(.trailing, 2.5) }
        }
    }
}

var cardColor: Color { Color.white.opacity(0.22) }

func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 13)).frame(width: 19, height: 22)
    }.buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
}

struct InputEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = SubmitTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.delegate = context.coordinator
        editor.onSubmit = onSubmit
        editor.setAccessibilityLabel("翻译原文")
        scroll.documentView = editor
        DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? SubmitTextView else { return }
        editor.onSubmit = onSubmit
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputEditor
        init(_ parent: InputEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit()
        } else if event.keyCode == 53, !hasMarkedText() { window?.orderOut(nil) }
        else { super.keyDown(with: event) }
    }
}
