import AppKit
import Carbon
import Foundation
import SwiftUI

public enum ClipKind: String, CaseIterable, Codable, Sendable {
    case text
    case richText
    case image
    case url
    case file
    case code
}

public struct ClipRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    public var createdAt: Date
    public var sourceAppName: String
    public var sourceBundleID: String?
    public var sourceIconKey: String?
    public var previewText: String
    public var searchText: String
    public var isPinned: Bool
    public var pinTitle: String?
    public var pinOrder: Int?
    public var textPayload: String?
    public var payloadPath: String?
    public var thumbnailPath: String?
    public var metadataJSON: String?
    public var signature: String

    public init(
        id: UUID,
        kind: ClipKind,
        createdAt: Date,
        sourceAppName: String,
        sourceBundleID: String?,
        sourceIconKey: String?,
        previewText: String,
        searchText: String,
        isPinned: Bool,
        pinTitle: String?,
        pinOrder: Int?,
        textPayload: String?,
        payloadPath: String?,
        thumbnailPath: String?,
        metadataJSON: String?,
        signature: String
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.sourceIconKey = sourceIconKey
        self.previewText = previewText
        self.searchText = searchText
        self.isPinned = isPinned
        self.pinTitle = pinTitle
        self.pinOrder = pinOrder
        self.textPayload = textPayload
        self.payloadPath = payloadPath
        self.thumbnailPath = thumbnailPath
        self.metadataJSON = metadataJSON
        self.signature = signature
    }

    public var effectiveTitle: String {
        if let pinTitle, !pinTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pinTitle
        }
        return previewText
    }
}

public struct ExcludedApp: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var appPath: String

    public init(bundleID: String, displayName: String, appPath: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.appPath = appPath
    }

    public var id: String { bundleID }
}

public enum HistoryLimit: Int, CaseIterable, Codable, Sendable {
    case fifty = 50
    case hundred = 100
    case fiveHundred = 500
    case unlimited = 0

    public var displayName: String {
        switch self {
        case .fifty:
            return "50"
        case .hundred:
            return "100"
        case .fiveHundred:
            return "500"
        case .unlimited:
            return "Unlimited"
        }
    }

    public var clipLimit: Int? {
        switch self {
        case .unlimited:
            return nil
        default:
            return rawValue
        }
    }
}

public enum AutoClearIntervalSetting: String, CaseIterable, Codable, Sendable {
    case never
    case oneDay
    case sevenDays
    case thirtyDays

    public var displayName: String {
        switch self {
        case .never:
            return "Never"
        case .oneDay:
            return "1 day"
        case .sevenDays:
            return "7 days"
        case .thirtyDays:
            return "30 days"
        }
    }

    public var timeInterval: TimeInterval? {
        switch self {
        case .never:
            return nil
        case .oneDay:
            return 86_400
        case .sevenDays:
            return 604_800
        case .thirtyDays:
            return 2_592_000
        }
    }
}

public enum ForcedAppearance: String, CaseIterable, Codable, Sendable {
    case light
    case dark

    public var displayName: String {
        rawValue.capitalized
    }

    public var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayKey: String

    public init(keyCode: UInt32, modifiers: UInt32, displayKey: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayKey = displayKey.uppercased()
    }

    public static let defaultOpenPanel = KeyboardShortcut(
        keyCode: 9,
        modifiers: UInt32(cmdKey) | UInt32(shiftKey),
        displayKey: "V"
    )

    public var label: String {
        modifierLabel + displayKey
    }

    private var modifierLabel: String {
        var output = ""
        if modifiers & UInt32(controlKey) != 0 {
            output += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            output += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            output += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            output += "⌘"
        }
        return output
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var globalShortcut: KeyboardShortcut
    public var pasteOnClick: Bool
    public var showSourceAppIcons: Bool
    public var compactMode: Bool
    public var historyLimit: HistoryLimit
    public var autoClearAfter: AutoClearIntervalSetting
    public var excludedApps: [ExcludedApp]
    public var followSystemAppearance: Bool
    public var forcedAppearance: ForcedAppearance
    public var pauseCapturing: Bool

    public init(
        launchAtLogin: Bool = true,
        globalShortcut: KeyboardShortcut = .defaultOpenPanel,
        pasteOnClick: Bool = true,
        showSourceAppIcons: Bool = true,
        compactMode: Bool = false,
        historyLimit: HistoryLimit = .hundred,
        autoClearAfter: AutoClearIntervalSetting = .never,
        excludedApps: [ExcludedApp] = [],
        followSystemAppearance: Bool = true,
        forcedAppearance: ForcedAppearance = .dark,
        pauseCapturing: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.globalShortcut = globalShortcut
        self.pasteOnClick = pasteOnClick
        self.showSourceAppIcons = showSourceAppIcons
        self.compactMode = compactMode
        self.historyLimit = historyLimit
        self.autoClearAfter = autoClearAfter
        self.excludedApps = excludedApps
        self.followSystemAppearance = followSystemAppearance
        self.forcedAppearance = forcedAppearance
        self.pauseCapturing = pauseCapturing
    }

    public func excludes(bundleID: String?) -> Bool {
        guard let bundleID else {
            return false
        }
        return excludedApps.contains { $0.bundleID == bundleID }
    }
}

public enum ClipFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case images

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .images:
            return "Images"
        }
    }
}

public struct SourceApplication: Equatable, Hashable, Sendable {
    public var name: String
    public var bundleID: String?
    public var path: String?

    public init(name: String, bundleID: String?, path: String?) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }

    public var iconKey: String? {
        bundleID ?? path
    }
}

public struct NormalizedClip: Equatable, Sendable {
    public var kind: ClipKind
    public var createdAt: Date
    public var sourceAppName: String
    public var sourceBundleID: String?
    public var sourceIconKey: String?
    public var previewText: String
    public var searchText: String
    public var textPayload: String?
    public var payloadData: Data?
    public var payloadFileExtension: String?
    public var thumbnailData: Data?
    public var thumbnailFileExtension: String?
    public var metadataJSON: String?
    public var signature: String

    public init(
        kind: ClipKind,
        createdAt: Date,
        sourceAppName: String,
        sourceBundleID: String?,
        sourceIconKey: String?,
        previewText: String,
        searchText: String,
        textPayload: String?,
        payloadData: Data?,
        payloadFileExtension: String?,
        thumbnailData: Data?,
        thumbnailFileExtension: String?,
        metadataJSON: String?,
        signature: String
    ) {
        self.kind = kind
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.sourceIconKey = sourceIconKey
        self.previewText = previewText
        self.searchText = searchText
        self.textPayload = textPayload
        self.payloadData = payloadData
        self.payloadFileExtension = payloadFileExtension
        self.thumbnailData = thumbnailData
        self.thumbnailFileExtension = thumbnailFileExtension
        self.metadataJSON = metadataJSON
        self.signature = signature
    }
}

public struct ClipGroup: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var sourceAppName: String
    public var sourceBundleID: String?
    public var sourceIconKey: String?
    public var clips: [ClipRecord]

    public init(id: String, sourceAppName: String, sourceBundleID: String?, sourceIconKey: String?, clips: [ClipRecord]) {
        self.id = id
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.sourceIconKey = sourceIconKey
        self.clips = clips
    }
}

public enum ClipListItem: Identifiable, Equatable, Hashable, Sendable {
    case clip(ClipRecord)
    case group(ClipGroup)

    public var id: String {
        switch self {
        case let .clip(record):
            return record.id.uuidString
        case let .group(group):
            return group.id
        }
    }
}
