import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var clips: [ClipRecord]
    @Published public private(set) var settings: AppSettings
    @Published public var searchText = ""
    @Published public var selectedFilter: ClipFilter = .all
    @Published public var showingSettings = false
    @Published public var popoverOpenToken = 0
    @Published public var expandedGroupIDs: Set<String> = []
    @Published public var draggedPinnedClipID: UUID?
    @Published public var launchAtLoginError: String?

    public let permissionState: PermissionState

    public var onRequestPopoverToggle: (() -> Void)?
    public var onRequestPopoverClose: (() -> Void)?
    public var onStatusIconNeedsUpdate: (() -> Void)?

    private let settingsStore: SettingsStore
    private let clipStore: ClipStore
    private let frontmostAppTracker: FrontmostAppTracker
    private let hotkeyManager: HotkeyManager
    private let pasteService: PasteService
    private let launchAtLoginService: LaunchAtLoginService
    private let iconProvider: AppIconProvider
    private var clipboardMonitor: ClipboardMonitor!

    public init() {
        do {
            let paths = try AppPaths()
            settingsStore = SettingsStore(paths: paths)
            clipStore = try ClipStore(paths: paths)
        } catch {
            fatalError("ClipStack failed to initialize storage: \(error.localizedDescription)")
        }

        settings = settingsStore.load()
        clips = (try? clipStore.fetchAll()) ?? []
        permissionState = PermissionState()
        frontmostAppTracker = FrontmostAppTracker()
        hotkeyManager = HotkeyManager()
        pasteService = PasteService(permissionState: permissionState)
        launchAtLoginService = LaunchAtLoginService()
        iconProvider = .shared

        clipboardMonitor = ClipboardMonitor(
            sourceProvider: { [weak self] in
                self?.frontmostAppTracker.currentCaptureSource()
            },
            settingsProvider: { [weak self] in
                self?.settings ?? AppSettings()
            },
            onCapture: { [weak self] clip in
                Task { @MainActor in
                    self?.handleCapturedClip(clip)
                }
            }
        )
    }

    public var preferredColorScheme: ColorScheme? {
        guard !settings.followSystemAppearance else {
            return nil
        }
        return settings.forcedAppearance.colorScheme
    }

    public var pinnedClips: [ClipRecord] {
        clips
            .filter(\.isPinned)
            .sorted {
                let lhs = $0.pinOrder ?? .max
                let rhs = $1.pinOrder ?? .max
                if lhs == rhs {
                    return $0.createdAt > $1.createdAt
                }
                return lhs < rhs
            }
    }

    public var historyItems: [ClipListItem] {
        let history = clips.filter { !$0.isPinned && filterMatches($0) && ClipSearch.matches($0, query: searchText) }
        return ClipGrouping.listItems(from: history, expandedGroupIDs: expandedGroupIDs)
    }

    public func start() {
        hotkeyManager.onTrigger = { [weak self] in
            self?.onRequestPopoverToggle?()
        }
        hotkeyManager.register(settings.globalShortcut)
        clipboardMonitor.start()
        try? clipStore.prune(using: settings)
        refreshClips()
        syncLaunchAtLoginAtStartup()
    }

    public func stop() {
        clipboardMonitor.stop()
        hotkeyManager.unregister()
    }

    public func prepareForPopoverOpen() {
        popoverOpenToken += 1
        try? clipStore.prune(using: settings)
        refreshClips()
    }

    public func popoverDidClose() {
        showingSettings = false
        searchText = ""
        selectedFilter = .all
        expandedGroupIDs.removeAll()
        draggedPinnedClipID = nil
    }

    public func selectClip(_ clip: ClipRecord) {
        if settings.pasteOnClick {
            pasteClip(clip)
        } else {
            copyClip(clip)
        }
    }

    public func copyClip(_ clip: ClipRecord) {
        clipboardMonitor.suppress(signature: clip.signature)
        do {
            try pasteService.copy(clip)
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func pasteClip(_ clip: ClipRecord) {
        clipboardMonitor.suppress(signature: clip.signature)
        switch pasteService.paste(clip, targetApplication: frontmostAppTracker.targetApplicationForPaste()) {
        case .pasted:
            onRequestPopoverClose?()
        case .copiedOnly:
            onRequestPopoverClose?()
        case .copiedNeedsAccessibility:
            DialogService.showError(message: "Clip copied, but ClipStack needs Accessibility access to paste automatically.")
        case let .failed(message):
            DialogService.showError(message: message)
        }
    }

    public func togglePinned(_ clip: ClipRecord) {
        do {
            try clipStore.setPinned(id: clip.id, isPinned: !clip.isPinned)
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func renamePin(_ clip: ClipRecord, title: String?) {
        do {
            try clipStore.renamePin(id: clip.id, title: title)
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func deleteClip(_ clip: ClipRecord) {
        do {
            try clipStore.deleteClip(id: clip.id)
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func clearHistory() {
        guard DialogService.confirmClearHistory() else {
            return
        }
        do {
            try clipStore.clearHistory()
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func clearAllData() {
        guard DialogService.confirmClearAllData() else {
            return
        }
        do {
            try clipStore.clearAllData()
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func quitApplication() {
        NSApp.terminate(nil)
    }

    public func movePinnedClip(draggedID: UUID, before targetID: UUID) {
        var ids = pinnedClips.map(\.id)
        guard
            let fromIndex = ids.firstIndex(of: draggedID),
            let targetIndex = ids.firstIndex(of: targetID),
            fromIndex != targetIndex
        else {
            return
        }

        let movingID = ids.remove(at: fromIndex)
        let insertionIndex = targetIndex > fromIndex ? targetIndex - 1 : targetIndex
        ids.insert(movingID, at: insertionIndex)

        do {
            try clipStore.reorderPinned(ids: ids)
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func toggleGroupExpansion(_ groupID: String) {
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
        }
    }

    public func updateGlobalShortcut(_ shortcut: KeyboardShortcut) {
        mutateSettings {
            $0.globalShortcut = shortcut
        }
        hotkeyManager.register(shortcut)
    }

    public func setPasteOnClick(_ enabled: Bool) {
        mutateSettings {
            $0.pasteOnClick = enabled
        }
    }

    public func setShowSourceIcons(_ enabled: Bool) {
        mutateSettings {
            $0.showSourceAppIcons = enabled
        }
    }

    public func setCompactMode(_ enabled: Bool) {
        mutateSettings {
            $0.compactMode = enabled
        }
    }

    public func setHistoryLimit(_ limit: HistoryLimit) {
        mutateSettings {
            $0.historyLimit = limit
        }
        try? clipStore.prune(using: settings)
        refreshClips()
    }

    public func setAutoClear(_ interval: AutoClearIntervalSetting) {
        mutateSettings {
            $0.autoClearAfter = interval
        }
        try? clipStore.prune(using: settings)
        refreshClips()
    }

    public func setFollowSystemAppearance(_ enabled: Bool) {
        mutateSettings {
            $0.followSystemAppearance = enabled
        }
    }

    public func setForcedAppearance(_ appearance: ForcedAppearance) {
        mutateSettings {
            $0.forcedAppearance = appearance
        }
    }

    public func setPauseCapturing(_ paused: Bool) {
        mutateSettings {
            $0.pauseCapturing = paused
        }
        onStatusIconNeedsUpdate?()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.sync(enabled: enabled)
            launchAtLoginError = nil
            mutateSettings {
                $0.launchAtLogin = enabled
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            DialogService.showError(message: error.localizedDescription)
        }
    }

    public func addExcludedApp() {
        guard let app = DialogService.pickExcludedApp() else {
            return
        }
        var apps = settings.excludedApps.filter { $0.bundleID != app.bundleID }
        apps.append(app)
        apps.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        mutateSettings {
            $0.excludedApps = apps
        }
    }

    public func removeExcludedApp(_ app: ExcludedApp) {
        mutateSettings {
            $0.excludedApps.removeAll { $0.bundleID == app.bundleID }
        }
    }

    public func sourceIcon(for clip: ClipRecord) -> NSImage {
        iconProvider.icon(for: clip.sourceIconKey)
    }

    public func sourceIcon(forKey key: String?) -> NSImage {
        iconProvider.icon(for: key)
    }

    public func sourceIcon(for excludedApp: ExcludedApp) -> NSImage {
        iconProvider.icon(for: excludedApp.appPath)
    }

    public func previewImage(for clip: ClipRecord) -> NSImage? {
        let preferredPath = clip.thumbnailPath ?? clip.payloadPath
        guard let preferredPath else {
            return nil
        }
        return NSImage(contentsOf: URL(fileURLWithPath: preferredPath))
    }

    public func relativeTimestamp(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let text = formatter.localizedString(for: date, relativeTo: Date())
            return text == "now" ? "Just now" : text.capitalized
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func handleCapturedClip(_ clip: NormalizedClip) {
        do {
            _ = try clipStore.ingest(clip, settings: settings)
            refreshClips()
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }

    private func syncLaunchAtLoginAtStartup() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        do {
            try launchAtLoginService.sync(enabled: settings.launchAtLogin)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }

    private func refreshClips() {
        clips = (try? clipStore.fetchAll()) ?? []
    }

    private func filterMatches(_ clip: ClipRecord) -> Bool {
        switch selectedFilter {
        case .all:
            return true
        case .text:
            return [.text, .richText, .url, .code].contains(clip.kind)
        case .images:
            return clip.kind == .image
        }
    }

    private func mutateSettings(_ mutation: (inout AppSettings) -> Void) {
        var updated = settings
        mutation(&updated)
        settings = updated
        do {
            try settingsStore.save(updated)
        } catch {
            DialogService.showError(message: error.localizedDescription)
        }
    }
}
