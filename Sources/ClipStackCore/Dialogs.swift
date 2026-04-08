import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DialogService {
    static func showError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ClipStack"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        activateApp()
        alert.runModal()
    }

    static func confirmClearHistory() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear History?"
        alert.informativeText = "This removes all unpinned clips. Pinned clips stay intact."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        activateApp()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func confirmClearAllData() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Clear All Data?"
        alert.informativeText = "Type \"clear\" to permanently delete all history and pinned clips."
        let textField = NSTextField(string: "")
        textField.placeholderString = "clear"
        textField.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: "Delete Everything")
        alert.addButton(withTitle: "Cancel")
        activateApp()
        return alert.runModal() == .alertFirstButtonReturn
            && textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "clear"
    }

    static func promptForPinName(currentValue: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename Pin"
        alert.informativeText = "Give this pinned clip an optional label."
        let textField = NSTextField(string: currentValue ?? "")
        textField.placeholderString = "Pinned clip label"
        textField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        activateApp()

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func pickExcludedApp() -> ExcludedApp? {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [UTType.applicationBundle]
        openPanel.prompt = "Add App"
        activateApp()

        guard openPanel.runModal() == .OK, let url = openPanel.url, let bundle = Bundle(url: url) else {
            return nil
        }

        let bundleID = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return ExcludedApp(bundleID: bundleID, displayName: displayName, appPath: url.path)
    }

    private static func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
