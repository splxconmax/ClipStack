import AppKit
import SwiftUI

@MainActor
public final class ClipStackApplicationDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusBarController: StatusBarController?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(model: model)
        model.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        wireModelCallbacks()
        refreshIcon()
    }

    func popoverDidClose(_ notification: Notification) {
        model.popoverDidClose()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverContentView().environmentObject(model))
    }

    private func wireModelCallbacks() {
        model.onRequestPopoverToggle = { [weak self] in
            self?.togglePopover()
        }
        model.onRequestPopoverClose = { [weak self] in
            self?.closePopover()
        }
        model.onStatusIconNeedsUpdate = { [weak self] in
            self?.refreshIcon()
        }
    }

    @objc
    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        model.prepareForPopoverOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func refreshIcon() {
        statusItem.button?.image = MenuBarIcon.image(paused: model.settings.pauseCapturing)
    }
}

private enum MenuBarIcon {
    static func image(paused: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let base = (NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "ClipStack") ?? NSImage(size: NSSize(width: 18, height: 18)))
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 18, height: 18))

        if !paused {
            base.isTemplate = true
            return base
        }

        let composed = NSImage(size: NSSize(width: 18, height: 18))
        composed.lockFocus()
        base.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16))
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 11, y: 10, width: 6, height: 6)).fill()
        composed.unlockFocus()
        composed.isTemplate = false
        return composed
    }
}
