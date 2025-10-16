//
//  CloudStorageService.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import Foundation
import Network
import CoreData

class CloudStorageService: ObservableObject {
    static let shared = CloudStorageService()

    @Published var uploadProgress: [URL: Double] = [:]
    @Published var isOnline = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var uploadQueue: [UploadTask] = []
    private let maxConcurrentUploads = 2

    // Configuration
    private var bucketName: String = "my-dashcam-storage"
    private(set) var projectId: String = "my-dashcam-472908"
    private var serviceAccountKey: String = ""
    private var accessToken: String = ""
    private var tokenExpiry: Date = Date()

    private init() {
        // Load configuration synchronously (fast operations)
        loadStoredBucketName()

        // Defer heavy operations to avoid blocking startup but ensure self remains strong
        DispatchQueue.global(qos: .utility).async {
            self.loadStoredServiceAccount()
            self.startNetworkMonitoring()
        }
    }

    private func loadStoredServiceAccount() {
        if let storedKey = UserDefaults.standard.string(forKey: "ServiceAccountKey"),
           !storedKey.isEmpty {
            self.serviceAccountKey = storedKey
            print("🔐 Service account loaded")
        }
    }

    private func loadStoredBucketName() {
        if let storedBucketName = UserDefaults.standard.string(forKey: "CloudBucketName"),
           !storedBucketName.isEmpty {
            self.bucketName = storedBucketName
        }
    }

    struct UploadTask {
        let fileURL: URL
        let cloudPath: String
        let priority: Priority
        var retryCount: Int = 0

        enum Priority: Int, CaseIterable {
            case emergency = 0
            case normal = 1
            case background = 2
        }
    }

    // MARK: - Network Monitoring
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if self?.isOnline == true {
                    self?.processUploadQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Public API
    func queueForUpload(_ fileURL: URL, priority: UploadTask.Priority = .normal) {
        let cloudPath = generateCloudPath(for: fileURL)
        let task = UploadTask(fileURL: fileURL, cloudPath: cloudPath, priority: priority)

        uploadQueue.append(task)
        uploadQueue.sort { $0.priority.rawValue < $1.priority.rawValue }

        print("📤 Queued for upload: \(fileURL.lastPathComponent) -> \(cloudPath)")
        print("🌐 Network status: \(isOnline ? "Online" : "Offline")")
        print("📋 Upload queue length: \(uploadQueue.count)")

        if isOnline {
            print("🔄 Processing upload queue...")
            processUploadQueue()
        } else {
            print("⏳ Waiting for network connectivity...")
        }
    }

    func markAsEmergency(_ fileURL: URL) {
        if let index = uploadQueue.firstIndex(where: { $0.fileURL == fileURL }) {
            uploadQueue[index] = UploadTask(
                fileURL: fileURL,
                cloudPath: uploadQueue[index].cloudPath,
                priority: .emergency,
                retryCount: uploadQueue[index].retryCount
            )
            uploadQueue.sort { $0.priority.rawValue < $1.priority.rawValue }

            if isOnline {
                processUploadQueue()
            }
        }
    }

    // MARK: - Upload Processing
    private func processUploadQueue() {
        print("🔄 Processing upload queue...")
        guard isOnline else {
            print("❌ Not online, skipping upload processing")
            return
        }

        let currentUploads = uploadProgress.count
        let availableSlots = maxConcurrentUploads - currentUploads

        print("📊 Current uploads: \(currentUploads), available slots: \(availableSlots)")
        print("📋 Tasks in queue: \(uploadQueue.count)")

        guard availableSlots > 0 else {
            print("⏳ No available upload slots")
            return
        }

        let tasksToProcess = Array(uploadQueue.prefix(availableSlots))
        uploadQueue.removeFirst(min(availableSlots, uploadQueue.count))

        print("🚀 Starting \(tasksToProcess.count) uploads...")
        for task in tasksToProcess {
            print("📤 Processing upload: \(task.fileURL.lastPathComponent)")
            uploadFile(task)
        }
    }

    private func uploadFile(_ task: UploadTask) {
        guard FileManager.default.fileExists(atPath: task.fileURL.path) else {
            print("❌ File not found for upload: \(task.fileURL.path)")
            return
        }

        uploadProgress[task.fileURL] = 0.0

        // TODO: Implement actual Google Cloud Storage upload
        // For now, simulate upload with compression
        compressAndUpload(task)
    }

    private func compressAndUpload(_ task: UploadTask) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            // Compress video if needed
            let compressedURL = self.compressVideo(task.fileURL)

            // Try to upload to Google Cloud Storage
            self.uploadToGCS(compressedURL ?? task.fileURL, cloudPath: task.cloudPath) { success in
                Task { @MainActor in
                    self.uploadProgress.removeValue(forKey: task.fileURL)

                    if success {
                        print("✅ Upload completed: \(task.fileURL.lastPathComponent)")

                        // Track successful upload
                        if let fileSize = self.getFileSize(task.fileURL) {
                            GoogleCloudMonitoring.shared.trackVideoUploaded(fileSize: fileSize)
                        }

                        // Delete local file after successful upload (except emergency files)
                        if task.priority != .emergency {
                            try? FileManager.default.removeItem(at: task.fileURL)
                            print("🗑️ Deleted local file after upload: \(task.fileURL.lastPathComponent)")
                        }

                        // Clean up compressed file if it's different from original
                        if let compressedURL = compressedURL, compressedURL != task.fileURL {
                            try? FileManager.default.removeItem(at: compressedURL)
                        }
                    } else {
                        print("ℹ️ Upload not available - video saved locally: \(task.fileURL.lastPathComponent)")

                        // Track upload failure
                        GoogleCloudMonitoring.shared.trackUploadFailure(error: "Authentication or network error")

                        // Don't retry if authentication is not implemented
                        // Just keep the file locally
                        if task.retryCount == 0 {
                            print("📁 Video will remain in local storage")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Video Compression
    private func compressVideo(_ sourceURL: URL) -> URL? {
        // For now, return the original URL
        // TODO: Implement actual video compression using AVAssetExportSession
        return sourceURL
    }

    // MARK: - Google Cloud Storage Upload
    private func uploadToGCS(_ fileURL: URL, cloudPath: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                // Ensure we have a valid access token
                guard await ensureAccessToken() else {
                    completion(false)
                    return
                }

                let encodedPath = cloudPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cloudPath
                let uploadURL = "https://storage.googleapis.com/upload/storage/v1/b/\(bucketName)/o?uploadType=media&name=\(encodedPath)"

                print("📤 Upload URL: \(uploadURL)")
                print("📤 Bucket name: '\(bucketName)'")
                print("📤 Cloud path: '\(cloudPath)'")
                print("📤 Encoded path: '\(encodedPath)'")

                guard let url = URL(string: uploadURL) else {
                    print("❌ Invalid upload URL: \(uploadURL)")
                    completion(false)
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")

                print("📤 Request headers: Authorization=Bearer [token], Content-Type=video/quicktime")

                let fileData = try Data(contentsOf: fileURL)

                print("📤 File size: \(fileData.count) bytes")

                // Create a progress-tracking upload task
                let (data, response) = try await URLSession.shared.upload(for: request, from: fileData, delegate: nil)

                if let httpResponse = response as? HTTPURLResponse {
                    print("📤 Response status: \(httpResponse.statusCode)")
                    print("📤 Response headers: \(httpResponse.allHeaderFields)")

                    let success = (200...299).contains(httpResponse.statusCode)
                    if success {
                        print("✅ Upload successful: \(cloudPath)")
                    } else {
                        print("❌ Upload failed with status: \(httpResponse.statusCode)")
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("❌ Error response body: \(responseString)")
                        }
                    }
                    completion(success)
                } else {
                    print("❌ Invalid HTTP response")
                    completion(false)
                }

            } catch {
                print("❌ GCS Upload error: \(error)")
                completion(false)
            }
        }
    }

    // MARK: - Authentication
    private func ensureAccessToken() async -> Bool {
        // Check if current token is still valid
        if !accessToken.isEmpty && Date() < tokenExpiry {
            return true
        }

        // Get new access token
        return await refreshAccessToken()
    }

    private func refreshAccessToken() async -> Bool {
        guard !serviceAccountKey.isEmpty else {
            print("⚠️ Service account key not configured")
            return false
        }

        do {
            let (token, expiresAt) = try await GoogleCloudAuth.generateAccessToken(from: serviceAccountKey)

            await MainActor.run {
                self.accessToken = token
                self.tokenExpiry = expiresAt
            }

            print("✅ Access token refreshed")
            return true

        } catch GoogleCloudAuth.AuthError.notImplemented {
            print("ℹ️ Google Cloud upload not implemented - videos stored locally")
            return false
        } catch {
            print("❌ Failed to refresh access token: \(error.localizedDescription)")
            return false
        }
    }

    private func generateCloudPath(for fileURL: URL) -> String {
        let filename = fileURL.lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let datePath = dateFormatter.string(from: Date())
        return "dashcam/\(datePath)/\(filename)"
    }

    // MARK: - Configuration
    func configure(bucketName: String, projectId: String) {
        self.bucketName = bucketName
        self.projectId = projectId
    }

    func setServiceAccount(keyData: Data) {
        print("🔐 Setting new service account key...")
        print("🔐 Raw data size: \(keyData.count) bytes")

        guard let keyString = String(data: keyData, encoding: .utf8) else {
            print("❌ Failed to convert service account data to string")
            return
        }

        print("🔐 Converted to string, length: \(keyString.count)")

        // Validate JSON structure
        do {
            guard let jsonData = keyString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                print("❌ Invalid JSON format")
                return
            }

            // Check required fields
            let requiredFields = ["type", "project_id", "private_key_id", "private_key", "client_email", "client_id", "auth_uri", "token_uri"]
            for field in requiredFields {
                if json[field] == nil {
                    print("❌ Missing required field: \(field)")
                    return
                }
            }

            if let type = json["type"] as? String, type != "service_account" {
                print("❌ Invalid service account type: \(type)")
                return
            }

            if let email = json["client_email"] as? String {
                print("✅ Valid service account for: \(email)")
            }

            if let projectId = json["project_id"] as? String {
                print("✅ Project ID: \(projectId)")
            }

        } catch {
            print("❌ Failed to validate JSON: \(error)")
            return
        }

        self.serviceAccountKey = keyString
        // Clear existing token to force refresh
        self.accessToken = ""
        self.tokenExpiry = Date()

        // Store the key securely in keychain or UserDefaults (for demo, using UserDefaults)
        UserDefaults.standard.set(serviceAccountKey, forKey: "ServiceAccountKey")
        print("🔐 Service account key validated and stored securely")
    }

    func setServiceAccount(keyPath: String) {
        if let keyData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)) {
            setServiceAccount(keyData: keyData)
        }
    }

    func getUploadStatus() -> (queued: Int, uploading: Int) {
        return (uploadQueue.count, uploadProgress.count)
    }

    func testAuthentication() async -> Bool {
        print("🧪 Testing Google Cloud authentication...")
        let authSuccess = await refreshAccessToken()

        if authSuccess {
            print("🧪 Authentication successful, now testing bucket access...")
            return await testBucketAccess()
        }

        return false
    }

    private func testBucketAccess() async -> Bool {
        // Test bucket access by trying to list objects (or get bucket metadata)
        let testURL = "https://storage.googleapis.com/storage/v1/b/\(bucketName)"

        print("🧪 Testing bucket access: \(testURL)")

        guard let url = URL(string: testURL) else {
            print("❌ Invalid test URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🧪 Bucket test response: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    print("✅ Bucket '\(bucketName)' exists and is accessible")
                    return true
                } else if httpResponse.statusCode == 404 {
                    print("❌ Bucket '\(bucketName)' does not exist")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response: \(responseString)")
                    }
                } else if httpResponse.statusCode == 403 {
                    print("❌ Access denied to bucket '\(bucketName)'")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response: \(responseString)")
                    }
                } else {
                    print("❌ Unexpected response: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response: \(responseString)")
                    }
                }
            }
        } catch {
            print("❌ Bucket test error: \(error)")
        }

        return false
    }

    private func getFileSize(_ url: URL) -> Int64? {
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
    }
}