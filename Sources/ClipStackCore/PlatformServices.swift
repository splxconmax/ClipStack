import AppKit
@preconcurrency import ApplicationServices
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
public final class PermissionState: ObservableObject {
    @Published public private(set) var accessibilityGranted: Bool

    public init() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    @discardableResult
    public func refresh(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibilityGranted = granted
        return granted
    }
}

@MainActor
public final class AppIconProvider {
    public static let shared = AppIconProvider()

    private var cache: [String: NSImage] = [:]

    private init() {}

    public func icon(for key: String?) -> NSImage {
        guard let key, !key.isEmpty else {
            return fallbackIcon()
        }
        if let cached = cache[key] {
            return cached
        }

        let image: NSImage
        if FileManager().fileExists(atPath: key) {
            image = NSWorkspace.shared.icon(forFile: key)
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            image = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            image = fallbackIcon()
        }

        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }

    private func fallbackIcon() -> NSImage {
        let symbol = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
        symbol.size = NSSize(width: 16, height: 16)
        return symbol
    }
}

@MainActor
public final class FrontmostAppTracker {
    private var activationObserver: NSObjectProtocol?
    private let workspace = NSWorkspace.shared
    private let selfBundleID = Bundle.main.bundleIdentifier

    public private(set) var lastExternalApplication: NSRunningApplication?

    public init() {
        seedFromCurrentApp()
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard
                let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }
            Task { @MainActor in
                self?.update(with: runningApplication)
            }
        }
    }

    public func currentCaptureSource() -> SourceApplication? {
        let runningApplication = workspace.frontmostApplication ?? lastExternalApplication
        guard let runningApplication else {
            return nil
        }
        if runningApplication.bundleIdentifier == selfBundleID {
            return lastExternalApplication.map(Self.sourceApplication)
        }
        return Self.sourceApplication(from: runningApplication)
    }

    public func targetApplicationForPaste() -> NSRunningApplication? {
        lastExternalApplication
    }

    private func seedFromCurrentApp() {
        if let frontmost = workspace.frontmostApplication {
            update(with: frontmost)
        }
    }

    private func update(with application: NSRunningApplication) {
        guard application.bundleIdentifier != selfBundleID else {
            return
        }
        lastExternalApplication = application
    }

    private static func sourceApplication(from application: NSRunningApplication) -> SourceApplication {
        SourceApplication(
            name: application.localizedName ?? "Unknown App",
            bundleID: application.bundleIdentifier,
            path: application.bundleURL?.path
        )
    }
}

public enum ClipNormalizer {
    public static func normalize(
        pasteboard: NSPasteboard,
        sourceApp: SourceApplication?,
        createdAt: Date = Date()
    ) -> NormalizedClip? {
        let sourceName = sourceApp?.name ?? "Unknown App"
        let sourceBundleID = sourceApp?.bundleID
        let sourceIconKey = sourceApp?.iconKey

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map(\.path)
            let preview = filePreview(paths: paths)
            return NormalizedClip(
                kind: .file,
                createdAt: createdAt,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceIconKey: sourceIconKey,
                previewText: preview,
                searchText: paths.joined(separator: " "),
                textPayload: jsonString(for: paths),
                payloadData: nil,
                payloadFileExtension: nil,
                thumbnailData: nil,
                thumbnailFileExtension: nil,
                metadataJSON: nil,
                signature: signature(kind: .file, primaryText: paths.joined(separator: "|"), data: nil)
            )
        }

        if let image = NSImage(pasteboard: pasteboard), let originalData = pngData(from: image) {
            let thumbnail = thumbnailData(from: image)
            let preview = imagePreviewText(from: image)
            return NormalizedClip(
                kind: .image,
                createdAt: createdAt,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceIconKey: sourceIconKey,
                previewText: preview,
                searchText: preview,
                textPayload: nil,
                payloadData: originalData,
                payloadFileExtension: "png",
                thumbnailData: thumbnail.data,
                thumbnailFileExtension: thumbnail.fileExtension,
                metadataJSON: jsonString(for: ["size": preview]),
                signature: signature(kind: .image, primaryText: preview, data: originalData)
            )
        }

        let plainText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let richTextData = pasteboard.data(forType: .rtf)
        let derivedPlainText = plainText?.isEmpty == false ? plainText : plainTextFromRTF(richTextData)

        if let derivedPlainText, let detectedURL = detectedURL(from: derivedPlainText) {
            let preview = truncatePreview(detectedURL.absoluteString)
            return NormalizedClip(
                kind: .url,
                createdAt: createdAt,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceIconKey: sourceIconKey,
                previewText: preview,
                searchText: detectedURL.absoluteString,
                textPayload: detectedURL.absoluteString,
                payloadData: nil,
                payloadFileExtension: nil,
                thumbnailData: nil,
                thumbnailFileExtension: nil,
                metadataJSON: jsonString(for: ["host": detectedURL.host ?? ""]),
                signature: signature(kind: .url, primaryText: detectedURL.absoluteString, data: nil)
            )
        }

        if let richTextData, let derivedPlainText, !derivedPlainText.isEmpty {
            return NormalizedClip(
                kind: .richText,
                createdAt: createdAt,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceIconKey: sourceIconKey,
                previewText: truncatePreview(derivedPlainText),
                searchText: derivedPlainText,
                textPayload: derivedPlainText,
                payloadData: richTextData,
                payloadFileExtension: "rtf",
                thumbnailData: nil,
                thumbnailFileExtension: nil,
                metadataJSON: nil,
                signature: signature(kind: .richText, primaryText: derivedPlainText, data: richTextData)
            )
        }

        if let derivedPlainText, !derivedPlainText.isEmpty {
            let kind: ClipKind = looksLikeCode(derivedPlainText) ? .code : .text
            return NormalizedClip(
                kind: kind,
                createdAt: createdAt,
                sourceAppName: sourceName,
                sourceBundleID: sourceBundleID,
                sourceIconKey: sourceIconKey,
                previewText: truncatePreview(derivedPlainText),
                searchText: derivedPlainText,
                textPayload: derivedPlainText,
                payloadData: nil,
                payloadFileExtension: nil,
                thumbnailData: nil,
                thumbnailFileExtension: nil,
                metadataJSON: nil,
                signature: signature(kind: kind, primaryText: derivedPlainText, data: nil)
            )
        }

        return nil
    }

    private static func filePreview(paths: [String]) -> String {
        guard let first = paths.first else {
            return "Files"
        }
        if paths.count == 1 {
            return URL(fileURLWithPath: first).lastPathComponent
        }
        return "\(URL(fileURLWithPath: first).lastPathComponent) +\(paths.count - 1) more"
    }

    private static func imagePreviewText(from image: NSImage) -> String {
        let size = image.size
        return "Image \(Int(size.width))×\(Int(size.height))"
    }

    private static func truncatePreview(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count <= 80 {
            return singleLine
        }
        return String(singleLine.prefix(80)) + "…"
    }

    private static func detectedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        guard ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private static func plainTextFromRTF(_ data: Data?) -> String? {
        guard let data else {
            return nil
        }
        let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        return attributed?.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let codeMarkers = ["{", "}", ";", "func ", "class ", "let ", "var ", "import ", "=>", "</", "const ", "return "]
        let score = codeMarkers.reduce(0) { partialResult, marker in
            partialResult + (text.contains(marker) ? 1 : 0)
        }
        let indentedLineCount = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        return score >= 2 || indentedLineCount >= 2
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func thumbnailData(from image: NSImage) -> (data: Data?, fileExtension: String?) {
        let targetSize = NSSize(width: 48, height: 48)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let imageSize = image.size
        let scale = min(targetSize.width / max(imageSize.width, 1), targetSize.height / max(imageSize.height, 1))
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
        thumbnail.unlockFocus()

        guard
            let tiffData = thumbnail.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return (nil, nil)
        }

        if let heicData = heicData(from: thumbnail) {
            return (heicData, "heic")
        }
        return (bitmap.representation(using: .png, properties: [:]), "png")
    }

    private static func heicData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func signature(kind: ClipKind, primaryText: String, data: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data(primaryText.utf8))
        if let data {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func jsonString(for object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
public final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let sourceProvider: () -> SourceApplication?
    private let settingsProvider: () -> AppSettings
    private let onCapture: (NormalizedClip) -> Void
    private let selfBundleID = Bundle.main.bundleIdentifier

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredSignatures: [String: Date] = [:]

    public init(
        sourceProvider: @escaping () -> SourceApplication?,
        settingsProvider: @escaping () -> AppSettings,
        onCapture: @escaping (NormalizedClip) -> Void
    ) {
        self.sourceProvider = sourceProvider
        self.settingsProvider = settingsProvider
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func suppress(signature: String, duration: TimeInterval = 2) {
        ignoredSignatures[signature] = Date().addingTimeInterval(duration)
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        let settings = settingsProvider()
        guard !settings.pauseCapturing else {
            return
        }

        let sourceApp = sourceProvider()
        if settings.excludes(bundleID: sourceApp?.bundleID) {
            return
        }
        if sourceApp?.bundleID == selfBundleID {
            return
        }

        pruneIgnoredSignatures()
        guard let clip = ClipNormalizer.normalize(pasteboard: pasteboard, sourceApp: sourceApp) else {
            return
        }
        if ignoredSignatures.removeValue(forKey: clip.signature) != nil {
            return
        }

        onCapture(clip)
    }

    private func pruneIgnoredSignatures() {
        let now = Date()
        ignoredSignatures = ignoredSignatures.filter { $0.value > now }
    }
}

public enum PasteOutcome {
    case pasted
    case copiedOnly
    case copiedNeedsAccessibility
    case failed(String)
}

@MainActor
public final class PasteService {
    public let permissionState: PermissionState

    public init(permissionState: PermissionState) {
        self.permissionState = permissionState
    }

    public func copy(_ clip: ClipRecord) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch clip.kind {
        case .text, .url, .code:
            guard let text = clip.textPayload else {
                throw NSError(domain: "ClipStack.PasteService", code: 1, userInfo: [NSLocalizedDescriptionKey: "This clip has no text payload."])
            }
            pasteboard.setString(text, forType: .string)

        case .richText:
            guard let payloadPath = clip.payloadPath else {
                throw NSError(domain: "ClipStack.PasteService", code: 2, userInfo: [NSLocalizedDescriptionKey: "This rich text clip is missing its payload."])
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
            pasteboard.setData(data, forType: .rtf)
            if let text = clip.textPayload {
                pasteboard.setString(text, forType: .string)
            }

        case .image:
            guard let payloadPath = clip.payloadPath, let image = NSImage(contentsOf: URL(fileURLWithPath: payloadPath)) else {
                throw NSError(domain: "ClipStack.PasteService", code: 3, userInfo: [NSLocalizedDescriptionKey: "This image clip is missing its stored image file."])
            }
            pasteboard.writeObjects([image])

        case .file:
            guard
                let textPayload = clip.textPayload,
                let data = textPayload.data(using: .utf8),
                let paths = try JSONSerialization.jsonObject(with: data) as? [String]
            else {
                throw NSError(domain: "ClipStack.PasteService", code: 4, userInfo: [NSLocalizedDescriptionKey: "This file clip is missing its file references."])
            }
            let urls = paths.map { NSURL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls)
        }
    }

    public func paste(_ clip: ClipRecord, targetApplication: NSRunningApplication?) -> PasteOutcome {
        do {
            try copy(clip)
        } catch {
            return .failed(error.localizedDescription)
        }

        guard let targetApplication else {
            return .copiedOnly
        }

        targetApplication.activate(options: [.activateIgnoringOtherApps])

        if !permissionState.refresh(prompt: false), !permissionState.refresh(prompt: true) {
            return .copiedNeedsAccessibility
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.sendPasteKeystroke()
        }
        return .pasted
    }

    private static func sendPasteKeystroke() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let keyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
