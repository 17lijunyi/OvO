import AppKit
import SwiftUI

struct ChoiceMenuItem {
    let title: String
    let value: String
}

/// Keeps the supplied label geometry intact while presenting a native macOS menu.
struct ChoiceMenu<Label: View>: View {
    let title: String
    let selectedValue: String
    let items: [ChoiceMenuItem]
    let onSelect: (String) -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        label().overlay(MenuTrigger(title: title, selectedValue: selectedValue, items: items, onSelect: onSelect))
    }
}

private struct MenuTrigger: NSViewRepresentable {
    let title: String
    let selectedValue: String
    let items: [ChoiceMenuItem]
    let onSelect: (String) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityRole(.popUpButton)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(items.first(where: { $0.value == selectedValue })?.title ?? selectedValue)
    }

    final class Coordinator: NSObject {
        var parent: MenuTrigger
        init(_ parent: MenuTrigger) { self.parent = parent }
        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            for choice in parent.items {
                let item = NSMenuItem(title: choice.title, action: #selector(selectItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = choice.value
                item.state = choice.value == parent.selectedValue ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 3), in: sender)
        }
        @objc func selectItem(_ sender: NSMenuItem) {
            guard let value = sender.representedObject as? String else { return }
            parent.onSelect(value)
        }
    }
}
