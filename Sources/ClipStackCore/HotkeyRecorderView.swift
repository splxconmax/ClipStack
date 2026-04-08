import AppKit
import Carbon
import SwiftUI

public struct HotkeyRecorderView: NSViewRepresentable {
    private let shortcut: KeyboardShortcut
    private let onChange: (KeyboardShortcut) -> Void

    public init(shortcut: KeyboardShortcut, onChange: @escaping (KeyboardShortcut) -> Void) {
        self.shortcut = shortcut
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.currentShortcut = shortcut
        field.onShortcutChange = onChange
        return field
    }

    public func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.currentShortcut = shortcut
        nsView.onShortcutChange = onChange
    }
}

public final class HotkeyRecorderField: NSTextField {
    var onShortcutChange: ((KeyboardShortcut) -> Void)?
    var currentShortcut: KeyboardShortcut = .defaultOpenPanel {
        didSet {
            stringValue = currentShortcut.label
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .systemFont(ofSize: 12, weight: .medium)
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 7
        updateAppearance()
        stringValue = currentShortcut.label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        updateAppearance(recording: true)
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        updateAppearance(recording: false)
        return result
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        guard let shortcut = makeShortcut(from: event) else {
            NSSound.beep()
            return
        }

        currentShortcut = shortcut
        onShortcutChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }

    private func updateAppearance(recording: Bool = false) {
        layer?.backgroundColor = (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.quaternaryLabelColor.withAlphaComponent(0.12)).cgColor
        textColor = recording ? .controlAccentColor : .labelColor
    }

    private func makeShortcut(from event: NSEvent) -> KeyboardShortcut? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            return nil
        }

        let displayKey: String
        if let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty {
            displayKey = characters.uppercased()
        } else {
            switch event.keyCode {
            case 36:
                displayKey = "↩"
            case 49:
                displayKey = "Space"
            default:
                return nil
            }
        }

        return KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(for: modifiers),
            displayKey: displayKey
        )
    }

    private func carbonModifiers(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) {
            value |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            value |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            value |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            value |= UInt32(cmdKey)
        }
        return value
    }
}
