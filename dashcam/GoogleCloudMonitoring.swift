//
//  GoogleCloudMonitoring.swift
//  dashcam
//
//  Created by Claude on 9/24/25.
//

import Foundation
import Network

class GoogleCloudMonitoring: ObservableObject {
    static let shared = GoogleCloudMonitoring()

    private let projectId: String
    private let baseURL = "https://monitoring.googleapis.com/v3"
    private var accessToken: String = ""
    private var tokenExpiry: Date = Date()

    // Metrics tracking
    @Published var metrics: DashcamMetrics = DashcamMetrics()

    private init() {
        self.projectId = "my-dashcam-472908" // Use direct project ID to avoid circular dependency
        // Defer metrics collection to avoid blocking startup but ensure self remains strong
        DispatchQueue.main.async {
            self.startMetricsCollection()
        }
    }

    struct DashcamMetrics {
        var recordingTime: Foundation.TimeInterval = 0.0
        var videosRecorded: Int = 0
        var videosUploaded: Int = 0
        var uploadFailures: Int = 0
        var gpsAccuracy: Double = 0
        var batteryLevel: Double = 0
        var thermalState: String = "normal"
        var storageUsed: Double = 0 // in MB
        var crashDetected: Int = 0

        var lastUpdated: Date = Date()
    }

    // MARK: - Metrics Collection
    private func startMetricsCollection() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await self?.collectAndSendMetrics()
            }
        }
    }

    private func collectAndSendMetrics() async {
        // Update metrics from various services
        updateMetricsFromServices()

        // Send to Google Cloud Monitoring
        await sendMetricsToCloud()
    }

    private func updateMetricsFromServices() {
        let cameraService = CameraService.shared
        let systemService = SystemMonitorService.shared
        let cloudService = CloudStorageService.shared

        // Update metrics
        metrics.batteryLevel = Double(systemService.getBatteryPercentage())
        metrics.thermalState = systemService.getThermalStateDescription()

        if let location = cameraService.currentLocation {
            metrics.gpsAccuracy = location.horizontalAccuracy
        }

        // Calculate storage used
        if let storageUsed = calculateStorageUsed() {
            metrics.storageUsed = storageUsed
        }

        let uploadStatus = cloudService.getUploadStatus()
        // Note: We'd need to track these incrementally in real implementation

        metrics.lastUpdated = Date()
    }

    private func calculateStorageUsed() -> Double? {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let videoFiles = files.filter { $0.pathExtension == "mov" }
        let totalBytes = videoFiles.compactMap { getFileSize($0) }.reduce(0, +)

        return Double(totalBytes) / (1024 * 1024) // Convert to MB
    }

    private func getFileSize(_ url: URL) -> Int64? {
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
    }

    // MARK: - Cloud Monitoring API
    private func sendMetricsToCloud() async {
        do {
            // Ensure we have a valid access token
            guard await ensureAccessToken() else {
                print("⚠️ Could not obtain access token for monitoring")
                return
            }

            // Create time series data
            let timeSeries = createTimeSeriesData()
            let request = MonitoringRequest(timeSeries: timeSeries)

            // Send to Google Cloud Monitoring
            await sendTimeSeriesData(request)

        } catch {
            print("❌ Failed to send metrics: \(error)")
        }
    }

    private func createTimeSeriesData() -> [TimeSeries] {
        let timestamp = Timestamp(seconds: Int(Date().timeIntervalSince1970))

        return [
            TimeSeries(
                metric: Metric(type: "custom.googleapis.com/dashcam/recording_time"),
                resource: MonitoredResource(type: "global", labels: ["project_id": projectId]),
                points: [Point(interval: MonitoringTimeInterval(end: timestamp), value: TypedValue(doubleValue: metrics.recordingTime))]
            ),
            TimeSeries(
                metric: Metric(type: "custom.googleapis.com/dashcam/videos_recorded"),
                resource: MonitoredResource(type: "global", labels: ["project_id": projectId]),
                points: [Point(interval: MonitoringTimeInterval(end: timestamp), value: TypedValue(int64Value: Int64(metrics.videosRecorded)))]
            ),
            TimeSeries(
                metric: Metric(type: "custom.googleapis.com/dashcam/battery_level"),
                resource: MonitoredResource(type: "global", labels: ["project_id": projectId]),
                points: [Point(interval: MonitoringTimeInterval(end: timestamp), value: TypedValue(doubleValue: metrics.batteryLevel))]
            ),
            TimeSeries(
                metric: Metric(type: "custom.googleapis.com/dashcam/gps_accuracy"),
                resource: MonitoredResource(type: "global", labels: ["project_id": projectId]),
                points: [Point(interval: MonitoringTimeInterval(end: timestamp), value: TypedValue(doubleValue: metrics.gpsAccuracy))]
            ),
            TimeSeries(
                metric: Metric(type: "custom.googleapis.com/dashcam/storage_used_mb"),
                resource: MonitoredResource(type: "global", labels: ["project_id": projectId]),
                points: [Point(interval: MonitoringTimeInterval(end: timestamp), value: TypedValue(doubleValue: metrics.storageUsed))]
            )
        ]
    }

    private func sendTimeSeriesData(_ request: MonitoringRequest) async {
        let urlString = "\(baseURL)/projects/\(projectId)/timeSeries"

        guard let url = URL(string: urlString) else {
            print("❌ Invalid monitoring URL")
            return
        }

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(request)
            httpRequest.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: httpRequest)

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    print("✅ Metrics sent successfully to Google Cloud Monitoring")
                } else {
                    print("⚠️ Metrics send failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ Error sending metrics: \(error)")
        }
    }

    // MARK: - Event Tracking
    func trackVideoRecorded(duration: Foundation.TimeInterval) {
        Task { @MainActor in
            metrics.videosRecorded += 1
            metrics.recordingTime += duration
        }

        // Send immediate event
        Task {
            await sendEventToCloud(
                eventType: "video_recorded",
                properties: ["duration": duration]
            )
        }
    }

    func trackVideoUploaded(fileSize: Int64) {
        Task { @MainActor in
            metrics.videosUploaded += 1
        }

        Task {
            await sendEventToCloud(
                eventType: "video_uploaded",
                properties: ["file_size_mb": Double(fileSize) / (1024 * 1024)]
            )
        }
    }

    func trackUploadFailure(error: String) {
        Task { @MainActor in
            metrics.uploadFailures += 1
        }

        Task {
            await sendEventToCloud(
                eventType: "upload_failure",
                properties: ["error": error]
            )
        }
    }

    func trackCrashDetected(gForce: Double) {
        Task { @MainActor in
            metrics.crashDetected += 1
        }

        Task {
            await sendEventToCloud(
                eventType: "crash_detected",
                properties: ["g_force": gForce, "timestamp": Date().timeIntervalSince1970]
            )
        }
    }

    private func sendEventToCloud(eventType: String, properties: [String: Any]) async {
        // For now, just log the event
        print("📊 Event: \(eventType) - \(properties)")

        // In a full implementation, you'd send this to Google Cloud Logging or Custom Events
        // This would require additional API calls to logging.googleapis.com
    }

    // MARK: - Authentication
    private func ensureAccessToken() async -> Bool {
        // Check if current token is still valid
        if !accessToken.isEmpty && Date() < tokenExpiry {
            return true
        }

        // Get new access token using the same method as CloudStorageService
        return await refreshAccessToken()
    }

    private func refreshAccessToken() async -> Bool {
        let cloudService = CloudStorageService.shared

        // Use the same service account key from CloudStorageService
        guard let storedKey = UserDefaults.standard.string(forKey: "ServiceAccountKey"),
              !storedKey.isEmpty else {
            print("⚠️ No service account key configured for monitoring")
            return false
        }

        do {
            let (token, expiresAt) = try await GoogleCloudAuth.generateAccessToken(from: storedKey)

            await MainActor.run {
                self.accessToken = token
                self.tokenExpiry = expiresAt
            }

            print("✅ Monitoring access token refreshed")
            return true

        } catch {
            print("❌ Failed to refresh monitoring access token: \(error)")
            return false
        }
    }
}

// MARK: - Monitoring API Models
struct MonitoringRequest: Codable {
    let timeSeries: [TimeSeries]
}

struct TimeSeries: Codable {
    let metric: Metric
    let resource: MonitoredResource
    let points: [Point]
}

struct Metric: Codable {
    let type: String
    let labels: [String: String]?

    init(type: String, labels: [String: String]? = nil) {
        self.type = type
        self.labels = labels
    }
}

struct MonitoredResource: Codable {
    let type: String
    let labels: [String: String]
}

struct Point: Codable {
    let interval: MonitoringTimeInterval
    let value: TypedValue
}

struct MonitoringTimeInterval: Codable {
    let end: Timestamp
}

struct Timestamp: Codable {
    let seconds: Int
    let nanos: Int?

    init(seconds: Int, nanos: Int? = nil) {
        self.seconds = seconds
        self.nanos = nanos
    }
}

struct TypedValue: Codable {
    let doubleValue: Double?
    let int64Value: Int64?
    let stringValue: String?

    init(doubleValue: Double) {
        self.doubleValue = doubleValue
        self.int64Value = nil
        self.stringValue = nil
    }

    init(int64Value: Int64) {
        self.doubleValue = nil
        self.int64Value = int64Value
        self.stringValue = nil
    }

    init(stringValue: String) {
        self.doubleValue = nil
        self.int64Value = nil
        self.stringValue = stringValue
    }
}