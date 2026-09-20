import AppKit
import SwiftUI

/// A native, live backdrop blur; no wallpaper snapshots are captured or stored.
struct FrostedGlassBackground: View {
    var body: some View {
        NativeBackdrop()
            .overlay(Color.white.opacity(0.10))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 65)
            }
            .allowsHitTesting(false)
    }
}

private struct NativeBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassEffectView { GlassEffectView() }
    func updateNSView(_ view: GlassEffectView, context: Context) { view.refreshAccessibility() }
}

private final class GlassEffectView: NSVisualEffectView {
    private var displayObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        refreshAccessibility()
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAccessibility() }
    }

    required init?(coder: NSCoder) { nil }
    override var allowsVibrancy: Bool { false }
    func refreshAccessibility() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.94, alpha: 1).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    deinit {
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 9
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
    }
}

extension View {
    func glassCard(radius: CGFloat = 9) -> some View { modifier(GlassCard(radius: radius)) }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

final class TranslationPanel: NSPanel {
    var isPinned = false
    var isPresentingTranslation = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // The source application remains active while this nonactivating panel
        // accepts input, so app deactivation alone cannot detect an outside click.
        if !isPinned && !isPresentingTranslation && attachedSheet == nil { orderOut(nil) }
    }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
    override func performClose(_ sender: Any?) { orderOut(sender) }
}
