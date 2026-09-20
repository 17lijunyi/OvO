import AppKit
import SwiftUI

@MainActor
final class SettingsNavigation: ObservableObject { @Published var page = "translation" }

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("翻译").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 8)
                sidebarRow("翻译设置", "target", "translation")
                sidebarRow("服务", "shippingbox", "service")
                sidebarRow("历史记录", "clock", "history")
                sidebarRow("收藏", "star", "favorites")
                Text("通用").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 8).padding(.top, 18)
                sidebarRow("通用设置", "gearshape", "general")
                sidebarRow("关于", "info.circle", "about")
                Spacer()
            }.padding(.horizontal, 10).padding(.top, 46).frame(width: 172)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 18)).padding(8)
            Group {
                switch navigation.page {
                case "service": ServiceSettingsView(state: state, configuration: state.configuration)
                case "history": HistoryView(history: state.history, onOpen: state.onShowRecord)
                case "favorites": HistoryView(history: state.history, onOpen: state.onShowRecord, favoritesOnly: true)
                case "general": GeneralSettingsView()
                case "about": about
                default: TranslationSettingsView(state: state)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(FrostedGlassBackground())
            .preferredColorScheme(.light).ignoresSafeArea(.container, edges: .top)
    }

    private func sidebarRow(_ title: String, _ icon: String, _ page: String) -> some View {
        Button { navigation.page = page } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
            }.font(.system(size: 13)).padding(.horizontal, 9).padding(.vertical, 8)
                .foregroundStyle(navigation.page == page ? Color.white : Color.primary.opacity(0.8))
                .background(navigation.page == page ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var about: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: applicationIcon)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 110, height: 110)
                .accessibilityLabel("OvO 应用图标")
            Text("OvO 1.0.0").font(.system(size: 24, weight: .semibold))
            Text("划词 · 截图 · 输入 · 历史记录").foregroundStyle(.secondary)
            Text("为中英文互译而做的轻量 macOS 工具。")
                .font(.system(size: 13)).foregroundStyle(.tertiary)
            Spacer()
            Text("界面与操作参考 Bob，独立实现。")
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 30)
        }.frame(maxWidth: .infinity)
    }

    private var applicationIcon: NSImage {
        if let url = Bundle.main.url(forResource: "Ovo", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage ?? NSImage()
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 3)
                content()
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 30).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.leading, 8)
            VStack(spacing: 0, content: content).padding(12).background(cardColor, in: RoundedRectangle(cornerRadius: 11))
        }
    }
}

struct TranslationSettingsView: View {
    @ObservedObject var state: AppState
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("historyCleanupThreshold") private var cleanupThreshold = HistoryStore.defaultCleanupThreshold

    var body: some View {
        SettingsPage(title: "翻译设置") {
            SettingGroup(title: "全局快捷键") {
                shortcutRow("划词翻译", "选中需要翻译的文本，按下快捷键即可翻译。", "selection")
                Divider().padding(.vertical, 10)
                shortcutRow("截图翻译", "框选屏幕上的文字，识别后自动翻译。", "screenshot")
                Divider().padding(.vertical, 10)
                shortcutRow("输入翻译", "清空内容并显示翻译窗口，手动输入需要翻译的文本。", "input")
            }
            if let notice = state.shortcutNotice {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("重新检测", action: state.onReregisterShortcuts)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingGroup(title: "语言") {
                settingLine("第一语言", "自动模式下，英文会翻译为中文。") { Text("中文简体").foregroundStyle(.secondary) }
                Divider().padding(.vertical, 10)
                settingLine("第二语言", "原文是中文时，会自动翻译为英文。") { Text("英语").foregroundStyle(.secondary) }
                Divider().padding(.vertical, 10)
                settingLine("翻译方向", "可以在翻译浮窗里随时切换。") {
                    Picker("翻译方向", selection: $state.direction) {
                        ForEach(TranslationDirection.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 150)
                }
            }
            SettingGroup(title: "历史记录") {
                Toggle(isOn: $saveHistory) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动保存翻译历史")
                        Text("仅保存在这台 Mac，包含原文、译文和时间。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).controlSize(.small)
                Divider().padding(.vertical, 10)
                settingLine("清理提醒", "达到所选条数时提醒，可手动清理未收藏记录，收藏会保留。") {
                    Picker("清理提醒条数", selection: $cleanupThreshold) {
                        Text("100 条").tag(100)
                        Text("500 条").tag(500)
                        Text("1,000 条").tag(1_000)
                        Text("5,000 条").tag(5_000)
                    }.labelsHidden().frame(width: 130)
                }
            }
        }
    }

    private func shortcutRow(_ title: String, _ description: String, _ key: String) -> some View {
        settingLine(title, description) {
            Text(state.shortcutLabels[key] ?? "—").font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue).frame(width: 130, height: 27)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08)))
        }
    }
}

func settingLine<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        content()
    }
}

struct GeneralSettingsView: View {
    @State private var accessibility = SelectionService.hasAccessibilityPermission
    @State private var screenRecording = ScreenshotOCRService.hasScreenRecordingPermission

    var body: some View {
        SettingsPage(title: "通用设置") {
            SettingGroup(title: "系统权限") {
                permissionRow("辅助功能", "用于获取其他应用中选中的文字。", accessibility) {
                    SelectionService.requestAccessibilityPermission()
                    openPrivacy("Privacy_Accessibility")
                }
                Divider().padding(.vertical, 12)
                permissionRow("屏幕录制", "用于截图翻译，不会持续录屏。", screenRecording) {
                    ScreenshotOCRService.requestScreenRecordingPermission()
                    openPrivacy("Privacy_ScreenCapture")
                }
            }
            Text("若系统开关已开启，但这里仍未允许，请移除系统设置中的旧 OvO，再用「+」添加 /Applications/OvO.app，然后重新打开应用。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("重新检测权限", action: refreshPermissions)
                Spacer()
                Text("当前版本 \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(Bundle.main.bundleURL.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            SettingGroup(title: "使用方式") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("点击 Dock 图标可重新打开翻译窗口，关闭窗口后仍可使用快捷键。")
                    Text("输入翻译：Enter 翻译，Shift + Enter 换行。")
                    Text("框选截图时按 Esc 取消。")
                }.font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.onAppear(perform: refreshPermissions)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        accessibility = SelectionService.hasAccessibilityPermission
        screenRecording = ScreenshotOCRService.hasScreenRecordingPermission
    }

    private func permissionRow(_ title: String, _ description: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        settingLine(title, description) {
            if granted { Label("已允许", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green) }
            else { Button("前往授权", action: action).controlSize(.small) }
        }
    }
    private func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }
}
