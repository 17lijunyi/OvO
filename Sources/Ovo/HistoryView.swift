import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: HistoryStore
    var onOpen: (TranslationRecord) -> Void
    @State private var query = ""
    @State private var showSearch = false
    var favoritesOnly = false
    @AppStorage("historyCleanupThreshold") private var cleanupThreshold = HistoryStore.defaultCleanupThreshold
    @State private var selection: UUID?
    @State private var pendingDeletion: TranslationRecord?
    @State private var confirmClear = false
    @State private var confirmClearAll = false
    @FocusState private var searchFocused: Bool

    private var records: [TranslationRecord] {
        history.filteredRecords(query: query, favoritesOnly: favoritesOnly)
    }
    private var selected: TranslationRecord? {
        records.first(where: { $0.id == selection }) ?? records.first
    }

    var body: some View {
        HStack(spacing: 0) {
            historyList
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5)
            if let record = selected {
                recordDetail(record)
            } else {
                emptyDetail
            }
        }
        .alert("删除这条记录？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let record = pendingDeletion { history.remove(record) }
                pendingDeletion = nil
            }
        }
        .alert("清理未收藏的历史记录？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                if history.clearUnfavorited() { selection = nil }
            }
        } message: {
            Text("将删除 \(history.unfavoritedCount) 条未收藏记录，保留 \(history.favoriteCount) 条收藏。此操作无法撤销。")
        }
        .alert("删除全部历史记录？", isPresented: $confirmClearAll) {
            Button("取消", role: .cancel) {}
            Button("删除全部", role: .destructive) {
                if history.clear() { selection = nil }
            }
        } message: {
            Text("将删除全部 \(history.records.count) 条历史记录，其中包含 \(history.favoriteCount) 条收藏。此操作无法撤销。若要保留收藏，请选择「清理未收藏记录」。")
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(favoritesOnly ? "收藏" : "历史记录").font(.system(size: 14, weight: .semibold))
                    Text("\(favoritesOnly ? history.favoriteCount : history.records.count) 项")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                historyOptions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            if !favoritesOnly && history.shouldSuggestCleanup(at: cleanupThreshold) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("历史记录较多", systemImage: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text("已有 \(history.records.count) 条记录，可清理未收藏的内容。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("清理未收藏记录…") { confirmClear = true }.controlSize(.small)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 10).padding(.bottom, 10)
            }

            if showSearch {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(favoritesOnly ? "搜索收藏" : "搜索历史记录", text: $query)
                        .textFieldStyle(.plain).focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.22), lineWidth: 0.5))
                .padding(.horizontal, 10).padding(.bottom, 10)
                .onAppear { searchFocused = true }
            }

            if records.isEmpty {
                Text(emptyListMessage)
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.top, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            historyRow(record)
                            Rectangle().fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5).padding(.horizontal, 10)
                        }
                    }.padding(.horizontal, 6).padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            }
        }
        .padding(.top, 14)
        .frame(width: 240)
    }

    private var historyOptions: some View {
        ChoiceMenu(title: favoritesOnly ? "收藏选项" : "历史记录选项", selectedValue: "", items: [
            ChoiceMenuItem(title: showSearch ? "收起搜索" : (favoritesOnly ? "搜索收藏" : "搜索历史记录"), value: "search"),
            ChoiceMenuItem(title: "在翻译窗口打开", value: "open")
        ] + (favoritesOnly ? [] : [
            ChoiceMenuItem(title: "清理未收藏记录…", value: "clear"),
            ChoiceMenuItem(title: "删除全部历史记录…", value: "clearAll")
        ]), onSelect: { action in
            switch action {
            case "search":
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSearch.toggle()
                    if !showSearch { query = "" }
                }
            case "open": if let record = selected { onOpen(record) }
            case "clearAll": if !history.records.isEmpty { confirmClearAll = true }
            case "clear": if history.unfavoritedCount > 0 { confirmClear = true }
            default: break
            }
        }) {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.38), in: Circle())
        }
        .fixedSize()
    }

    private func historyRow(_ record: TranslationRecord) -> some View {
        Button { selection = record.id } label: {
            Text(record.original)
                .font(.system(size: 13)).lineSpacing(4).lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 10)
                .frame(minHeight: 52, maxHeight: 104, alignment: .topLeading)
                .background(
                    selected?.id == record.id ? Color.primary.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("在翻译窗口打开") { onOpen(record) }
            Button(record.isFavorite ? "取消收藏" : "收藏") { history.toggleFavorite(id: record.id) }
            Button("复制原文") { copyText(record.original) }
            Divider()
            Button("删除", role: .destructive) { pendingDeletion = record }
        }
    }

    private func recordDetail(_ record: TranslationRecord) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Text(record.date, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))
                Spacer(minLength: 8)
                historyIconButton(record.isFavorite ? "取消收藏" : "收藏", record.isFavorite ? "star.fill" : "star", size: 18) {
                    history.toggleFavorite(id: record.id)
                }
                historyIconButton("删除当前记录", "trash", size: 18) { pendingDeletion = record }
            }
            .frame(minHeight: 25)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    textCard(record.original, language: record.sourceLanguage, isTranslation: false)
                    HStack(spacing: 12) {
                        languagePill(record.sourceLanguage.title)
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        languagePill(record.targetLanguage.title)
                    }
                    textCard(record.translation, language: record.targetLanguage, isTranslation: true)
                }
                .padding(.bottom, 4)
            }.scrollIndicators(.hidden)

            if let error = history.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.top, 11).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func textCard(_ text: String, language: TranslationLanguage, isTranslation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(.system(size: 14)).lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                historyIconButton(isTranslation ? "朗读译文" : "朗读原文", "speaker.wave.2") {
                    SpeechService.shared.toggle(text: text, languageCode: language == .chinese ? "zh-CN" : "en-US")
                }
                historyIconButton(isTranslation ? "复制译文" : "复制原文", "square.on.square") { copyText(text) }
                Spacer(minLength: 0)
                if isTranslation {
                    Text(selected?.providerName ?? "翻译").font(.system(size: 11)).foregroundStyle(.secondary)
                    ProviderMark(provider: selected?.provider ?? .deepseek, size: 15)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.22), lineWidth: 0.5))
    }

    private func languagePill(_ title: String) -> some View {
        Text(title == "中文" ? "中文简体" : title).font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.22), lineWidth: 0.5))
    }

    private func historyIconButton(_ title: String, _ systemImage: String, size: CGFloat = 13, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Color.primary.opacity(0.82))
                .frame(width: 21, height: 21)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private var emptyListMessage: String {
        if !query.isEmpty { return "没有匹配的记录" }
        return favoritesOnly ? "暂无收藏记录" : "暂无历史记录"
    }

    private var emptyDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: favoritesOnly ? "star" : "clock")
                .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(!query.isEmpty ? "换个关键词试试" : favoritesOnly ? "收藏的翻译，会显示在这里" : "翻译过的文字，都在这里")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if query.isEmpty && !favoritesOnly {
                Text("完成一次翻译后，原文和译文会自动保存在本机。")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            if let error = history.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
