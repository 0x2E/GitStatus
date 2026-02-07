import AppKit
import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "GitStatus"
    private static let logger = Logger(subsystem: subsystem, category: "app")
    private static let file = LogFile(fileURL: logFileURL)

    static var logDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = appSupport?.appending(path: "GitStatus/Logs", directoryHint: .isDirectory)
        return dir ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "GitStatus/Logs", directoryHint: .isDirectory)
    }

    static var logFileURL: URL {
        logDirectoryURL.appending(path: "GitStatus.log", directoryHint: .notDirectory)
    }

    static func bootstrap() {
        Task {
            await file.bootstrap()
        }
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        Task { await file.append(level: "INFO", message: message) }
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        Task { await file.append(level: "WARN", message: message) }
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        Task { await file.append(level: "ERROR", message: message) }
    }

#if DEBUG
    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        Task { await file.append(level: "DEBUG", message: message) }
    }
#else
    static func debug(_ message: String) {
        _ = message
    }
#endif

    @MainActor
    static func revealLogFileInFinder() {
        let url = logFileURL
        ensureLogFileExists()
        Task { await file.bootstrap() }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func copyLogFilePathToPasteboard() {
        let path = logFileURL.path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        logger.debug("Copied log path to pasteboard")
    }

    private static func ensureLogFileExists() {
        let dir = logDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let fileURL = logFileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }
}

private actor LogFile {
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let fileURL: URL
    private var handle: FileHandle?
    private let maxSizeBytes: Int64 = 512 * 1024

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func bootstrap() {
        openHandleIfNeeded()
    }

    func append(level: String, message: String) {
        openHandleIfNeeded()
        rotateIfNeeded()
        guard let handle else { return }

        let ts = formatter.string(from: Date())
        let line = "\(ts) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            closeHandle()
        }
    }

    private func openHandleIfNeeded() {
        if handle != nil { return }

        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            handle = try FileHandle(forWritingTo: fileURL)
            try handle?.seekToEnd()
        } catch {
            handle = nil
        }
    }

    private func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber else {
            return
        }
        guard size.int64Value > maxSizeBytes else { return }

        closeHandle()

        let rotated = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: fileURL, to: rotated)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        openHandleIfNeeded()
    }

    private func closeHandle() {
        do {
            try handle?.close()
        } catch {
            // ignore
        }
        handle = nil
    }
}
