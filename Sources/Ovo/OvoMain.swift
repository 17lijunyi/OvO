import AppKit
import SwiftUI

@main
enum OvoMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private let hotKeys = GlobalHotKeyManager()
    private let selection = SelectionService()
    private let screenshot = ScreenshotOCRService()
    private var translationWindow: TranslationPanel?
    private var preferencesWindow: NSWindow?
    private let navigation = SettingsNavigation()
    private let captureCoordinator = CaptureCoordinator()
    private let screenshotPresentation = ScreenshotPresentation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMainMenu()
        state.onSettings = { [weak self] page in self?.showSettings(page) }
        state.onOpenInput = { [weak self] in self?.openInput() }
        state.onScreenshot = { [weak self] in self?.captureScreenshot() }
        state.onRetryCapture = { [weak self] source in
            if source == .selection { self?.translateSelection() }
            else if source == .screenshot { self?.captureScreenshot() }
        }
        state.onClose = { [weak self] in self?.state.cancel(); self?.translationWindow?.orderOut(nil) }
        state.onAppleSessionChanged = { [weak self] active in self?.translationWindow?.isPresentingTranslation = active }
        state.onPin = { [weak self] _ in self?.updateTranslationPinning() }
        state.onShowRecord = { [weak self] record in self?.state.show(record); self?.showTranslation() }
        state.onReregisterShortcuts = { [weak self] in self?.registerShortcuts() }
        state.onPanelHeightChange = { [weak self] height in self?.resizeTranslation(to: height) }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        registerShortcuts()
        showTranslation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hotKeys.unregisterAll()
        captureCoordinator.cancel()
        state.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidResignActive(_ notification: Notification) {
        dismissUnpinnedTranslation()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        dismissUnpinnedTranslation()
    }

    private func dismissUnpinnedTranslation() {
        // Keep the text and result so reopening from the Dock restores this session.
        guard !state.isPinned, state.appleJob == nil else { return }
        translationWindow?.orderOut(nil)
    }

    private func updateTranslationPinning() {
        translationWindow?.isPinned = state.isPinned
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTranslation()
        return true
    }

    private func makeMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 OvO", action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 OvO", action: #selector(quit), keyEquivalent: "q")
        applicationItem.submenu = appMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
                                    ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                                    ("全选", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let translationItem = NSMenuItem()
        let translationMenu = NSMenu(title: "翻译")
        for (title, action) in [("划词翻译", #selector(translateSelection)), ("截图翻译", #selector(captureScreenshot)),
                                ("输入翻译", #selector(openInput)), ("历史记录", #selector(openHistory)),
                                ("收藏", #selector(openFavorites))] {
            translationMenu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        translationItem.submenu = translationMenu
        menu.addItem(translationItem)
        NSApp.mainMenu = menu
    }

    private func registerShortcuts() {
        let handler: (HotKeyAction) -> Void = { [weak self] action in
            switch action {
            case .input: self?.openInput()
            case .selection: self?.translateSelection()
            case .screenshot: self?.captureScreenshot()
            }
        }
        let failures = hotKeys.register(handler: handler)
        state.shortcutNotice = failures.isEmpty ? nil : failures.map(\.localizedDescription).joined(separator: "\n")
        for action in HotKeyAction.allCases {
            state.shortcutLabels[action.rawValue] = GlobalHotKeyManager.shortcutLabel(for: action)
        }
    }

    func showTranslation() {
        if translationWindow == nil {
            let window = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 404, height: 233),
                                          styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "OvO 翻译"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isFloatingPanel = true
            window.level = .floating
            // A nonactivating panel receives input without switching the source app's Space.
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.appearance = NSAppearance(named: .aqua)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 360, height: 233)
            let hosting = NSHostingView(rootView: TranslationView(state: state))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            translationWindow = window
        }
        updateTranslationPinning()
        translationWindow?.makeKeyAndOrderFront(nil)
        if let content = translationWindow?.contentView {
            DispatchQueue.main.async { [weak self] in
                func findEditor(_ view: NSView) -> SubmitTextView? {
                    if let editor = view as? SubmitTextView { return editor }
                    return view.subviews.lazy.compactMap(findEditor).first
                }
                if let editor = findEditor(content) { self?.translationWindow?.makeFirstResponder(editor) }
            }
        }
    }

    private func resizeTranslation(to height: CGFloat) {
        guard let window = translationWindow else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let targetHeight = min(height, (visible?.height ?? 850) - 40)
        window.minSize = NSSize(width: 360, height: targetHeight)
        var frame = window.frame
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        if let visible, frame.minY < visible.minY { frame.origin.y = visible.minY }
        window.setFrame(frame, display: true, animate: false)
    }

    func showSettings(_ page: String) {
        navigation.page = page
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 925, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "OvO 设置"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.appearance = NSAppearance(named: .aqua)
            window.minSize = NSSize(width: 900, height: 560)
            let hosting = NSHostingView(rootView: SettingsView(state: state, navigation: navigation))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openInput() {
        captureCoordinator.cancel()
        screenshotPresentation.reset()
        state.prepare(source: .input)
        showTranslation()
    }
    @objc func openSettings() { showSettings("service") }
    @objc func openHistory() { showSettings("history") }
    @objc func openFavorites() { showSettings("favorites") }
    @objc func openAbout() { showSettings("about") }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func translateSelection() {
        state.cancel()
        screenshotPresentation.reset()
        captureCoordinator.start { [weak self] in
            guard let self else { return }
            do {
                let text = try await selection.captureSelectedText()
                guard !Task.isCancelled else { return }
                state.prepare(source: .selection, text: text)
                showTranslation()
                state.translate()
            } catch {
                guard !Task.isCancelled else { return }
                state.prepare(source: .selection)
                state.errorMessage = error.localizedDescription
                state.captureRetrySource = .selection
                showTranslation()
            }
        }
    }

    @objc func captureScreenshot() {
        state.cancel()
        let presentation = screenshotPresentation.begin(visible: .init(
            translation: translationWindow?.isVisible ?? false,
            settings: preferencesWindow?.isVisible ?? false
        ))
        translationWindow?.orderOut(nil)
        preferencesWindow?.orderOut(nil)
        captureCoordinator.start { [weak self] in
            guard let self else { return }
            defer { _ = screenshotPresentation.finish(presentation) }
            do {
                let text = try await screenshot.captureAndRecognize()
                guard !Task.isCancelled else { return }
                state.prepare(source: .screenshot, text: text)
                showTranslation()
                state.translate()
            } catch {
                guard !Task.isCancelled else { return }
                if case PlatformError.cancelled = error {
                    guard let visibility = screenshotPresentation.finish(presentation) else { return }
                    if visibility.translation { showTranslation() }
                    if visibility.settings {
                        preferencesWindow?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    return
                }
                state.prepare(source: .screenshot)
                state.errorMessage = error.localizedDescription
                state.captureRetrySource = .screenshot
                showTranslation()
            }
        }
    }
}
