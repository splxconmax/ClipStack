import Foundation
import SQLite3

public struct AppPaths: Sendable {
    public let baseDirectory: URL
    public let databaseURL: URL
    public let settingsURL: URL
    public let payloadsDirectory: URL
    public let imagesDirectory: URL
    public let thumbnailsDirectory: URL

    public init(baseDirectory: URL? = nil, fileManager: FileManager = FileManager()) throws {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "ClipStack.AppPaths", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate Application Support directory."])
            }
            self.baseDirectory = applicationSupportURL.appendingPathComponent("ClipStack", isDirectory: true)
        }

        databaseURL = self.baseDirectory.appendingPathComponent("clipstack.sqlite3")
        settingsURL = self.baseDirectory.appendingPathComponent("settings.json")
        payloadsDirectory = self.baseDirectory.appendingPathComponent("payloads", isDirectory: true)
        imagesDirectory = self.baseDirectory.appendingPathComponent("images", isDirectory: true)
        thumbnailsDirectory = self.baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)

        try fileManager.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
}

public final class SettingsStore {
    private let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(paths: AppPaths, fileManager: FileManager = FileManager()) {
        self.paths = paths
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> AppSettings {
        guard fileManager.fileExists(atPath: paths.settingsURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: paths.settingsURL)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsURL, options: .atomic)
    }
}

enum SQLiteValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case null
}

enum SQLiteDatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return message
        case let .statementFailed(message):
            return message
        }
    }
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open database."
            sqlite3_close(handle)
            throw SQLiteDatabaseError.openFailed(message)
        }
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw SQLiteDatabaseError.statementFailed(errorMessage)
        }
    }

    func query<T>(_ sql: String, bindings: [SQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                rows.append(try map(statement))
            case SQLITE_DONE:
                return rows
            default:
                throw SQLiteDatabaseError.statementFailed(errorMessage)
            }
        }
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try work()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.statementFailed(errorMessage)
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case let .text(text):
                result = sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
            case let .int(integer):
                result = sqlite3_bind_int64(statement, position, integer)
            case let .double(double):
                result = sqlite3_bind_double(statement, position, double)
            case .null:
                result = sqlite3_bind_null(statement, position)
            }

            guard result == SQLITE_OK else {
                throw SQLiteDatabaseError.statementFailed(errorMessage)
            }
        }
    }

    private var errorMessage: String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "SQLite error"
        }
        return String(cString: message)
    }
}

public enum ClipStoreError: LocalizedError {
    case missingRecord
    case pinLimitReached

    public var errorDescription: String? {
        switch self {
        case .missingRecord:
            return "The clip no longer exists."
        case .pinLimitReached:
            return "ClipStack can keep up to 20 pinned clips."
        }
    }
}

public final class ClipStore {
    public let paths: AppPaths

    private let database: SQLiteDatabase
    private let fileManager: FileManager

    public init(paths: AppPaths, fileManager: FileManager = FileManager()) throws {
        self.paths = paths
        self.fileManager = fileManager
        database = try SQLiteDatabase(url: paths.databaseURL)
        try createSchema()
    }

    public func fetchAll() throws -> [ClipRecord] {
        try database.query(
            """
            SELECT id, kind, created_at, source_app_name, source_bundle_id, source_icon_key,
                   preview_text, search_text, is_pinned, pin_title, pin_order,
                   text_payload, payload_path, thumbnail_path, metadata_json, signature
            FROM clips
            ORDER BY created_at DESC;
            """
        ) { statement in
            ClipRecord(
                id: UUID(uuidString: Self.string(from: statement, index: 0)) ?? UUID(),
                kind: ClipKind(rawValue: Self.string(from: statement, index: 1)) ?? .text,
                createdAt: Date(timeIntervalSince1970: Self.double(from: statement, index: 2)),
                sourceAppName: Self.string(from: statement, index: 3),
                sourceBundleID: Self.optionalString(from: statement, index: 4),
                sourceIconKey: Self.optionalString(from: statement, index: 5),
                previewText: Self.string(from: statement, index: 6),
                searchText: Self.string(from: statement, index: 7),
                isPinned: Self.int(from: statement, index: 8) == 1,
                pinTitle: Self.optionalString(from: statement, index: 9),
                pinOrder: Self.optionalInt(from: statement, index: 10),
                textPayload: Self.optionalString(from: statement, index: 11),
                payloadPath: Self.optionalString(from: statement, index: 12),
                thumbnailPath: Self.optionalString(from: statement, index: 13),
                metadataJSON: Self.optionalString(from: statement, index: 14),
                signature: Self.string(from: statement, index: 15)
            )
        }
    }

    public func ingest(_ normalizedClip: NormalizedClip, settings: AppSettings) throws -> ClipRecord {
        let record = try persist(normalizedClip)
        try prune(using: settings)
        return record
    }

    public func setPinned(id: UUID, isPinned: Bool) throws {
        let record = try fetchRecord(id: id)
        if record.isPinned == isPinned {
            return
        }

        if isPinned {
            let pinnedCount = try fetchPinned().count
            guard pinnedCount < 20 else {
                throw ClipStoreError.pinLimitReached
            }
            let nextOrder = (try fetchPinned().compactMap(\.pinOrder).max() ?? -1) + 1
            try database.execute(
                """
                UPDATE clips
                SET is_pinned = 1, pin_order = ?, pin_title = COALESCE(pin_title, '')
                WHERE id = ?;
                """,
                bindings: [.int(Int64(nextOrder)), .text(id.uuidString)]
            )
        } else {
            try database.execute(
                """
                UPDATE clips
                SET is_pinned = 0, pin_order = NULL, pin_title = NULL
                WHERE id = ?;
                """,
                bindings: [.text(id.uuidString)]
            )
        }
    }

    public func renamePin(id: UUID, title: String?) throws {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: SQLiteValue = {
            guard let trimmed, !trimmed.isEmpty else {
                return .null
            }
            return .text(trimmed)
        }()
        try database.execute(
            "UPDATE clips SET pin_title = ? WHERE id = ?;",
            bindings: [value, .text(id.uuidString)]
        )
    }

    public func reorderPinned(ids: [UUID]) throws {
        var desiredOrder = ids
        let existingPinned = try fetchPinned()
        for record in existingPinned where !desiredOrder.contains(record.id) {
            desiredOrder.append(record.id)
        }

        try database.transaction {
            for (index, id) in desiredOrder.enumerated() {
                try database.execute(
                    "UPDATE clips SET pin_order = ? WHERE id = ? AND is_pinned = 1;",
                    bindings: [.int(Int64(index)), .text(id.uuidString)]
                )
            }
        }
    }

    public func deleteClip(id: UUID) throws {
        let record = try fetchRecord(id: id)
        cleanupAssets(for: record)
        try database.execute("DELETE FROM clips WHERE id = ?;", bindings: [.text(id.uuidString)])
    }

    public func clearHistory() throws {
        let history = try fetchAll().filter { !$0.isPinned }
        for record in history {
            try deleteClip(id: record.id)
        }
    }

    public func clearAllData() throws {
        let allRecords = try fetchAll()
        for record in allRecords {
            cleanupAssets(for: record)
        }
        try database.execute("DELETE FROM clips;")
    }

    public func prune(using settings: AppSettings) throws {
        var candidates = try fetchAll().filter { !$0.isPinned }
        var idsToDelete = Set<UUID>()

        if let interval = settings.autoClearAfter.timeInterval {
            let threshold = Date().addingTimeInterval(-interval)
            for clip in candidates where clip.createdAt < threshold {
                idsToDelete.insert(clip.id)
            }
            candidates.removeAll { idsToDelete.contains($0.id) }
        }

        if let limit = settings.historyLimit.clipLimit, candidates.count > limit {
            let overflow = candidates.dropFirst(limit)
            overflow.forEach { idsToDelete.insert($0.id) }
        }

        for id in idsToDelete {
            try deleteClip(id: id)
        }
    }

    public func fetchPinned() throws -> [ClipRecord] {
        try fetchAll()
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

    private func createSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                created_at REAL NOT NULL,
                source_app_name TEXT NOT NULL,
                source_bundle_id TEXT,
                source_icon_key TEXT,
                preview_text TEXT NOT NULL,
                search_text TEXT NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                pin_title TEXT,
                pin_order INTEGER,
                text_payload TEXT,
                payload_path TEXT,
                thumbnail_path TEXT,
                metadata_json TEXT,
                signature TEXT NOT NULL
            );
            """
        )

        try database.execute("CREATE INDEX IF NOT EXISTS idx_clips_created_at ON clips(created_at DESC);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clips_pinned_order ON clips(is_pinned, pin_order);")
    }

    private func persist(_ normalizedClip: NormalizedClip) throws -> ClipRecord {
        let id = UUID()
        let payloadPath = try writePayload(
            data: normalizedClip.payloadData,
            id: id,
            fileExtension: normalizedClip.payloadFileExtension,
            directory: normalizedClip.kind == .image ? paths.imagesDirectory : paths.payloadsDirectory
        )
        let thumbnailPath = try writePayload(
            data: normalizedClip.thumbnailData,
            id: id,
            fileExtension: normalizedClip.thumbnailFileExtension,
            directory: paths.thumbnailsDirectory
        )

        let record = ClipRecord(
            id: id,
            kind: normalizedClip.kind,
            createdAt: normalizedClip.createdAt,
            sourceAppName: normalizedClip.sourceAppName,
            sourceBundleID: normalizedClip.sourceBundleID,
            sourceIconKey: normalizedClip.sourceIconKey,
            previewText: normalizedClip.previewText,
            searchText: normalizedClip.searchText,
            isPinned: false,
            pinTitle: nil,
            pinOrder: nil,
            textPayload: normalizedClip.textPayload,
            payloadPath: payloadPath,
            thumbnailPath: thumbnailPath,
            metadataJSON: normalizedClip.metadataJSON,
            signature: normalizedClip.signature
        )

        try database.execute(
            """
            INSERT INTO clips (
                id, kind, created_at, source_app_name, source_bundle_id, source_icon_key,
                preview_text, search_text, is_pinned, pin_title, pin_order,
                text_payload, payload_path, thumbnail_path, metadata_json, signature
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(record.id.uuidString),
                .text(record.kind.rawValue),
                .double(record.createdAt.timeIntervalSince1970),
                .text(record.sourceAppName),
                record.sourceBundleID.map(SQLiteValue.text) ?? .null,
                record.sourceIconKey.map(SQLiteValue.text) ?? .null,
                .text(record.previewText),
                .text(record.searchText),
                .int(record.isPinned ? 1 : 0),
                record.pinTitle.map(SQLiteValue.text) ?? .null,
                record.pinOrder.map { .int(Int64($0)) } ?? .null,
                record.textPayload.map(SQLiteValue.text) ?? .null,
                record.payloadPath.map(SQLiteValue.text) ?? .null,
                record.thumbnailPath.map(SQLiteValue.text) ?? .null,
                record.metadataJSON.map(SQLiteValue.text) ?? .null,
                .text(record.signature),
            ]
        )

        return record
    }

    private func writePayload(data: Data?, id: UUID, fileExtension: String?, directory: URL) throws -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }
        let ext = (fileExtension?.isEmpty == false ? fileExtension : "bin") ?? "bin"
        let fileURL = directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    private func fetchRecord(id: UUID) throws -> ClipRecord {
        let records = try database.query(
            """
            SELECT id, kind, created_at, source_app_name, source_bundle_id, source_icon_key,
                   preview_text, search_text, is_pinned, pin_title, pin_order,
                   text_payload, payload_path, thumbnail_path, metadata_json, signature
            FROM clips
            WHERE id = ?
            LIMIT 1;
            """,
            bindings: [.text(id.uuidString)]
        ) { statement in
            ClipRecord(
                id: UUID(uuidString: Self.string(from: statement, index: 0)) ?? UUID(),
                kind: ClipKind(rawValue: Self.string(from: statement, index: 1)) ?? .text,
                createdAt: Date(timeIntervalSince1970: Self.double(from: statement, index: 2)),
                sourceAppName: Self.string(from: statement, index: 3),
                sourceBundleID: Self.optionalString(from: statement, index: 4),
                sourceIconKey: Self.optionalString(from: statement, index: 5),
                previewText: Self.string(from: statement, index: 6),
                searchText: Self.string(from: statement, index: 7),
                isPinned: Self.int(from: statement, index: 8) == 1,
                pinTitle: Self.optionalString(from: statement, index: 9),
                pinOrder: Self.optionalInt(from: statement, index: 10),
                textPayload: Self.optionalString(from: statement, index: 11),
                payloadPath: Self.optionalString(from: statement, index: 12),
                thumbnailPath: Self.optionalString(from: statement, index: 13),
                metadataJSON: Self.optionalString(from: statement, index: 14),
                signature: Self.string(from: statement, index: 15)
            )
        }

        guard let record = records.first else {
            throw ClipStoreError.missingRecord
        }
        return record
    }

    private func cleanupAssets(for record: ClipRecord) {
        [record.payloadPath, record.thumbnailPath]
            .compactMap { $0 }
            .forEach { path in
                try? fileManager.removeItem(atPath: path)
            }
    }

    private static func string(from statement: OpaquePointer, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private static func optionalString(from statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return string(from: statement, index: index)
    }

    private static func int(from statement: OpaquePointer, index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    private static func optionalInt(from statement: OpaquePointer, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return int(from: statement, index: index)
    }

    private static func double(from statement: OpaquePointer, index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
