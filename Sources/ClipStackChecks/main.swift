import ClipStackCore
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

@main
struct ClipStackChecks {
    static func main() {
        let checks: [(String, () throws -> Void)] = [
            ("search relative date", searchMatchesRelativeDateToken),
            ("grouping collapse", groupingCollapsesThreeCompatibleClips),
            ("settings round trip", settingsStoreRoundTrip),
            ("history prune preserves pins", prunePreservesPinnedClipsWhileApplyingHistoryLimit),
            ("asset cleanup", deleteClipRemovesStoredAssets),
            ("pin limit", pinLimitStopsAtTwentyPins),
        ]

        var failures: [String] = []
        for (name, check) in checks {
            do {
                try check()
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                fputs("FAIL \(name): \(error)\n", stderr)
            }
        }

        if failures.isEmpty {
            print("All ClipStack checks passed.")
        } else {
            exit(1)
        }
    }

    private static func searchMatchesRelativeDateToken() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let clip = makeRecord(createdAt: yesterday, sourceAppName: "Notes", searchText: "Shopping list")

        try expect(ClipSearch.matches(clip, query: "yesterday", now: now, calendar: calendar), "Expected search to match relative date.")
        try expect(ClipSearch.matches(clip, query: "notes shopping", now: now, calendar: calendar), "Expected search to match text and app name.")
        try expect(!ClipSearch.matches(clip, query: "safari", now: now, calendar: calendar), "Expected unrelated query to fail.")
    }

    private static func groupingCollapsesThreeCompatibleClips() throws {
        let now = Date()
        let clips = [
            makeRecord(createdAt: now, sourceAppName: "Notes"),
            makeRecord(createdAt: now.addingTimeInterval(-30), sourceAppName: "Notes"),
            makeRecord(createdAt: now.addingTimeInterval(-60), sourceAppName: "Notes"),
            makeRecord(createdAt: now.addingTimeInterval(-120), sourceAppName: "Safari"),
        ]

        let items = ClipGrouping.listItems(from: clips, expandedGroupIDs: [])
        try expect(items.count == 2, "Expected one group plus one standalone clip.")
        guard case let .group(group) = items[0] else {
            throw CheckFailure.message("Expected the first item to be a grouped card.")
        }
        try expect(group.clips.count == 3, "Expected three clips in the group.")
        try expect(group.sourceAppName == "Notes", "Expected Notes group.")
    }

    private static func settingsStoreRoundTrip() throws {
        let paths = try makePaths()
        let store = SettingsStore(paths: paths)
        let settings = AppSettings(
            launchAtLogin: false,
            globalShortcut: KeyboardShortcut(keyCode: 11, modifiers: 256, displayKey: "B"),
            pasteOnClick: false,
            showSourceAppIcons: false,
            compactMode: true,
            historyLimit: .fiveHundred,
            autoClearAfter: .sevenDays,
            excludedApps: [ExcludedApp(bundleID: "com.example.app", displayName: "Example", appPath: "/Applications/Example.app")],
            followSystemAppearance: false,
            forcedAppearance: .light,
            pauseCapturing: true
        )

        try store.save(settings)
        let loaded = store.load()
        try expect(loaded == settings, "Expected settings round trip to preserve all values.")
    }

    private static func prunePreservesPinnedClipsWhileApplyingHistoryLimit() throws {
        let paths = try makePaths()
        let store = try ClipStore(paths: paths)
        let baseDate = Date()

        var createdIDs: [UUID] = []
        for index in 0..<55 {
            let clip = makeNormalizedClip(text: "clip-\(index)", createdAt: baseDate.addingTimeInterval(TimeInterval(-index)))
            let record = try store.ingest(clip, settings: AppSettings(historyLimit: .unlimited))
            createdIDs.append(record.id)
        }

        try store.setPinned(id: createdIDs.last!, isPinned: true)
        try store.prune(using: AppSettings(historyLimit: .fifty))

        let remaining = try store.fetchAll()
        try expect(remaining.count == 51, "Expected 50 history clips plus one pinned clip.")
        try expect(remaining.contains { $0.id == createdIDs.last! && $0.isPinned }, "Expected pinned clip to survive prune.")
    }

    private static func deleteClipRemovesStoredAssets() throws {
        let paths = try makePaths()
        let store = try ClipStore(paths: paths)
        let fileManager = FileManager()

        let clip = NormalizedClip(
            kind: .image,
            createdAt: Date(),
            sourceAppName: "Preview",
            sourceBundleID: "com.apple.Preview",
            sourceIconKey: "com.apple.Preview",
            previewText: "Image 10×10",
            searchText: "Image",
            textPayload: nil,
            payloadData: Data([0x01, 0x02, 0x03]),
            payloadFileExtension: "png",
            thumbnailData: Data([0x04, 0x05]),
            thumbnailFileExtension: "png",
            metadataJSON: nil,
            signature: "image-signature"
        )

        let record = try store.ingest(clip, settings: AppSettings(historyLimit: .unlimited))
        guard let payloadPath = record.payloadPath, let thumbnailPath = record.thumbnailPath else {
            throw CheckFailure.message("Expected persisted image assets.")
        }

        try expect(fileManager.fileExists(atPath: payloadPath), "Expected payload image file.")
        try expect(fileManager.fileExists(atPath: thumbnailPath), "Expected thumbnail image file.")

        try store.deleteClip(id: record.id)

        try expect(!fileManager.fileExists(atPath: payloadPath), "Expected payload image file to be removed.")
        try expect(!fileManager.fileExists(atPath: thumbnailPath), "Expected thumbnail image file to be removed.")
    }

    private static func pinLimitStopsAtTwentyPins() throws {
        let paths = try makePaths()
        let store = try ClipStore(paths: paths)

        var records: [ClipRecord] = []
        for index in 0..<21 {
            let record = try store.ingest(
                makeNormalizedClip(text: "pin-\(index)", createdAt: Date().addingTimeInterval(TimeInterval(index))),
                settings: AppSettings(historyLimit: .unlimited)
            )
            records.append(record)
        }

        for record in records.prefix(20) {
            try store.setPinned(id: record.id, isPinned: true)
        }

        do {
            try store.setPinned(id: records[20].id, isPinned: true)
            throw CheckFailure.message("Expected pin limit error for the 21st pinned clip.")
        } catch {
            let message = (error as? ClipStoreError)?.errorDescription ?? error.localizedDescription
            try expect(message == ClipStoreError.pinLimitReached.errorDescription, "Expected pin limit failure.")
        }
    }

    private static func makePaths() throws -> AppPaths {
        let directory = FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try AppPaths(baseDirectory: directory)
    }

    private static func makeRecord(
        createdAt: Date,
        sourceAppName: String,
        searchText: String = "Example text"
    ) -> ClipRecord {
        ClipRecord(
            id: UUID(),
            kind: .text,
            createdAt: createdAt,
            sourceAppName: sourceAppName,
            sourceBundleID: "bundle.\(sourceAppName)",
            sourceIconKey: "bundle.\(sourceAppName)",
            previewText: searchText,
            searchText: searchText,
            isPinned: false,
            pinTitle: nil,
            pinOrder: nil,
            textPayload: searchText,
            payloadPath: nil,
            thumbnailPath: nil,
            metadataJSON: nil,
            signature: UUID().uuidString
        )
    }

    private static func makeNormalizedClip(text: String, createdAt: Date) -> NormalizedClip {
        NormalizedClip(
            kind: .text,
            createdAt: createdAt,
            sourceAppName: "Notes",
            sourceBundleID: "com.apple.Notes",
            sourceIconKey: "com.apple.Notes",
            previewText: text,
            searchText: text,
            textPayload: text,
            payloadData: nil,
            payloadFileExtension: nil,
            thumbnailData: nil,
            thumbnailFileExtension: nil,
            metadataJSON: nil,
            signature: text
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CheckFailure.message(message)
        }
    }
}
