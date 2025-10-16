//
//  ObservabilityService.swift
//  dashcam
//
//  Enhanced logging and observability with cost optimization
//

import Foundation
import os.log
import Network
import UIKit

class ObservabilityService: ObservableObject {
    static let shared = ObservabilityService()

    // MARK: - Configuration
    private let maxLocalLogSizeMB = 50.0 // Max 50MB local logs
    private let logRetentionDays = 7 // Keep logs for 7 days
    private let cloudBatchSize = 10 // Batch logs before sending to reduce costs
    private let cloudFlushInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Storage
    private let localLogDirectory: URL
    private var currentLogFile: URL
    private var logQueue = DispatchQueue(label: "observability.logging", qos: .utility)
    private var cloudLogBatch: [LogEntry] = []
    private var batchTimer: Timer?

    // MARK: - Network monitoring
    private let monitor = NWPathMonitor()
    private var isOnline = false

    // MARK: - Log levels and filtering
    enum LogLevel: String, CaseIterable, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"

        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            case .critical: return 4
            }
        }
    }

    // MARK: - Cost optimization settings
    @Published var settings = LoggingSettings()

    struct LoggingSettings {
        var enableCloudLogging = true
        var minCloudLogLevel: LogLevel = .warning // Only send warnings and above to cloud
        var enableLocalLogging = true
        var enableDebugMode = false // Detailed logs when debugging
        var sampleRate: Double = 1.0 // 1.0 = log everything, 0.1 = log 10%
    }

    struct LogEntry: Codable {
        let timestamp: Date
        let level: LogLevel
        let category: String
        let message: String
        let metadata: [String: String]?
        let deviceId: String

        var jsonData: Data? {
            try? JSONEncoder().encode(self)
        }
    }

    // MARK: - Initialization
    private init() {
        // Setup local log directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        localLogDirectory = documentsPath.appendingPathComponent("logs")
        currentLogFile = localLogDirectory.appendingPathComponent("current.log")

        createLogDirectoryIfNeeded()
        setupNetworkMonitoring()
        startBatchTimer()

        // Clean old logs on startup
        cleanOldLogs()

        log(.info, category: "System", message: "ObservabilityService initialized")
    }

    // MARK: - Public Logging Methods
    func log(_ level: LogLevel, category: String, message: String, metadata: [String: String]? = nil) {
        // Apply sampling for cost control (except for critical logs)
        if level != .critical && Double.random(in: 0...1) > settings.sampleRate {
            return
        }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            deviceId: getDeviceId()
        )

        logQueue.async {
            // Always log locally if enabled
            if self.settings.enableLocalLogging {
                self.writeToLocalLog(entry)
            }

            // Log to system log
            self.writeToSystemLog(entry)

            // Add to cloud batch if meets criteria
            if self.shouldSendToCloud(entry) {
                self.addToCloudBatch(entry)
            }
        }
    }

    // MARK: - Convenience methods
    func debug(_ category: String, _ message: String, metadata: [String: String]? = nil) {
        if settings.enableDebugMode {
            log(.debug, category: category, message: message, metadata: metadata)
        }
    }

    func info(_ category: String, _ message: String, metadata: [String: String]? = nil) {
        log(.info, category: category, message: message, metadata: metadata)
    }

    func warning(_ category: String, _ message: String, metadata: [String: String]? = nil) {
        log(.warning, category: category, message: message, metadata: metadata)
    }

    func error(_ category: String, _ message: String, error: Error? = nil) {
        var metadata: [String: String]? = nil
        if let error = error {
            metadata = ["error": error.localizedDescription]
        }
        log(.error, category: category, message: message, metadata: metadata)
    }

    func critical(_ category: String, _ message: String, error: Error? = nil, metadata: [String: String]? = nil) {
        var finalMetadata = metadata ?? [:]
        if let error = error {
            finalMetadata["error"] = error.localizedDescription
        }
        log(.critical, category: category, message: message, metadata: finalMetadata.isEmpty ? nil : finalMetadata)

        // Critical logs are sent immediately
        flushCloudBatch()
    }

    // MARK: - Performance Tracking
    func trackPerformance(_ operation: String, duration: TimeInterval, metadata: [String: String]? = nil) {
        var perfMetadata = metadata ?? [:]
        perfMetadata["duration"] = String(duration)
        perfMetadata["operation_type"] = "performance"

        log(.info, category: "Performance", message: "Operation '\(operation)' took \(duration)s", metadata: perfMetadata)
    }

    func trackError(_ category: String, error: Error, context: String? = nil) {
        var metadata: [String: String] = [
            "error_domain": (error as NSError).domain,
            "error_code": String((error as NSError).code)
        ]

        if let context = context {
            metadata["context"] = context
        }

        log(.error, category: category, message: error.localizedDescription, metadata: metadata)
    }

    // MARK: - Local Logging
    private func createLogDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: localLogDirectory, withIntermediateDirectories: true)
    }

    private func writeToLocalLog(_ entry: LogEntry) {
        let logLine = formatLogEntry(entry)

        // Rotate log if needed
        if shouldRotateLog() {
            rotateLogFile()
        }

        // Write to current log file
        if let data = (logLine + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: currentLogFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: currentLogFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: currentLogFile)
            }
        }
    }

    private func formatLogEntry(_ entry: LogEntry) -> String {
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        var logLine = "[\(timestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"

        if let metadata = entry.metadata, !metadata.isEmpty {
            let metadataString = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            logLine += " {\(metadataString)}"
        }

        return logLine
    }

    private func writeToSystemLog(_ entry: LogEntry) {
        let osLog = OSLog(subsystem: "com.tusharsaurabh.dashcam", category: entry.category)
        let osLogType: OSLogType = {
            switch entry.level {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }()

        os_log("%{public}@", log: osLog, type: osLogType, entry.message)
    }

    // MARK: - Cloud Logging (Cost Optimized)
    private func shouldSendToCloud(_ entry: LogEntry) -> Bool {
        return settings.enableCloudLogging &&
               isOnline &&
               entry.level.priority >= settings.minCloudLogLevel.priority
    }

    private func addToCloudBatch(_ entry: LogEntry) {
        cloudLogBatch.append(entry)

        // Send immediately if batch is full or if critical
        if cloudLogBatch.count >= cloudBatchSize || entry.level == .critical {
            flushCloudBatch()
        }
    }

    private func flushCloudBatch() {
        guard !cloudLogBatch.isEmpty else { return }

        let batch = cloudLogBatch
        cloudLogBatch.removeAll()

        Task {
            await sendBatchToCloud(batch)
        }
    }

    private func sendBatchToCloud(_ entries: [LogEntry]) async {
        // Use Google Cloud Logging API (cheapest option)
        let projectId = "my-dashcam-472908"
        let url = URL(string: "https://logging.googleapis.com/v2/entries:write")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert to Google Cloud Logging format
        let logEntries = entries.map { entry in
            return [
                "logName": "projects/\(projectId)/logs/dashcam",
                "resource": [
                    "type": "generic_task",
                    "labels": [
                        "task_id": entry.deviceId,
                        "job": "dashcam-app"
                    ]
                ],
                "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                "severity": entry.level.rawValue,
                "labels": [
                    "category": entry.category
                ],
                "jsonPayload": [
                    "message": entry.message,
                    "metadata": entry.metadata ?? [:]
                ]
            ]
        }

        let requestBody = [
            "entries": logEntries
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                log(.debug, category: "CloudLogging", message: "Successfully sent \(entries.count) log entries to cloud")
            } else {
                log(.warning, category: "CloudLogging", message: "Failed to send logs to cloud")
            }
        } catch {
            log(.error, category: "CloudLogging", message: "Error sending logs to cloud", metadata: ["error": error.localizedDescription])
        }
    }

    // MARK: - Log Management
    private func shouldRotateLog() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: currentLogFile.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return false
        }

        let fileSizeMB = Double(fileSize) / (1024 * 1024)
        return fileSizeMB > (maxLocalLogSizeMB / 5) // Rotate at 10MB for 50MB total
    }

    private func rotateLogFile() {
        let timestamp = DateFormatter().string(from: Date())
        let archivedLogFile = localLogDirectory.appendingPathComponent("archived_\(timestamp).log")

        // Move current log to archived
        try? FileManager.default.moveItem(at: currentLogFile, to: archivedLogFile)

        // Clean old logs
        cleanOldLogs()
    }

    private func cleanOldLogs() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -logRetentionDays, to: Date()) ?? Date()

        guard let files = try? FileManager.default.contentsOfDirectory(at: localLogDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }

        for file in files {
            if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               creationDate < cutoffDate {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Network Monitoring
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }

    private func startBatchTimer() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: cloudFlushInterval, repeats: true) { [weak self] _ in
            self?.flushCloudBatch()
        }
    }

    // MARK: - Utilities
    private func getDeviceId() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    // MARK: - Log Viewing
    func getLocalLogs(limit: Int = 1000) -> [String] {
        guard FileManager.default.fileExists(atPath: currentLogFile.path) else { return [] }

        guard let content = try? String(contentsOf: currentLogFile, encoding: .utf8) else { return [] }

        let lines = content.components(separatedBy: .newlines)
        return Array(lines.suffix(limit))
    }

    func exportLogs() -> URL? {
        let exportFile = localLogDirectory.appendingPathComponent("exported_logs_\(Date().timeIntervalSince1970).txt")

        var allLogs = ""

        // Get all log files
        if let files = try? FileManager.default.contentsOfDirectory(at: localLogDirectory, includingPropertiesForKeys: nil) {
            let logFiles = files.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            for file in logFiles {
                if let content = try? String(contentsOf: file, encoding: .utf8) {
                    allLogs += "=== \(file.lastPathComponent) ===\n"
                    allLogs += content
                    allLogs += "\n\n"
                }
            }
        }

        try? allLogs.write(to: exportFile, atomically: true, encoding: .utf8)
        return exportFile
    }

    deinit {
        batchTimer?.invalidate()
        monitor.cancel()
        flushCloudBatch() // Ensure logs are sent before shutdown
    }
}

// MARK: - Extensions for easier usage
extension ObservabilityService {
    func logAppLaunch() {
        info("AppLifecycle", "App launched", metadata: [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ])
    }

    func logOrientation(from: String, to: String, duration: TimeInterval) {
        trackPerformance("orientation_change", duration: duration, metadata: [
            "from": from,
            "to": to
        ])
    }

    func logRecordingEvent(type: String, duration: TimeInterval? = nil) {
        var metadata: [String: String] = ["event_type": type]
        if let duration = duration {
            metadata["duration"] = String(duration)
        }

        info("Recording", "Recording event: \(type)", metadata: metadata)
    }
}