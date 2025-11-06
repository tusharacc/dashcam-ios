//
//  CameraService.swift
//  dashcam
//
//  Created by Tushar Saurabh on 6/24/25.
//
//  Core camera service managing video recording, orientation, and motion detection.
//  This singleton service handles:
//  - AVCaptureSession configuration and lifecycle
//  - Loop recording with automatic segmentation
//  - Device orientation monitoring and video orientation updates
//  - Motion detection for impact/crash events
//  - GPS location tracking
//  - Storage management with automatic cleanup
//

import Foundation
import AVFoundation
import UIKit
import CoreLocation
import CoreMotion
import MediaPlayer

/// Singleton service managing camera recording, orientation, and motion detection.
///
/// This service provides comprehensive camera functionality including:
/// - Loop recording with 5-minute segments
/// - Automatic orientation handling for video recording
/// - Motion detection for crash/impact events
/// - GPS location tracking and embedding
/// - Storage management with 8GB limit
/// - Emergency file protection
///
/// - Important: All camera operations are performed on a dedicated sessionQueue
class CameraService: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let shared = CameraService()

    // MARK: - Camera session and components
    private(set) var session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var isSetup = false
    private var isConfiguring = false
    private var isSessionReady = false
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // MARK: - Orientation handling
    private var currentOrientation: UIDeviceOrientation = .portrait

    // MARK: - Loop Recording
    private var isLoopRecording = false
    private var segmentDuration: Foundation.TimeInterval = 300.0 // 5 minutes per segment
    private var segmentTimer: Timer?
    private var currentSegmentNumber = 0

    // MARK: - Storage Management
    private let maxStorageGB: Double = 8.0 // 8GB max local storage
    private let emergencyProtectedFiles = Set<URL>()

    // MARK: - Location Services
    private let locationManager = CLLocationManager()
    private(set) var currentLocation: CLLocation?

    // MARK: - Motion Detection
    private let motionManager = CMMotionManager()
    private var lastAcceleration: CMAcceleration?
    private let impactThreshold: Double = 2.5 // G-force threshold for impact detection

    // MARK: - Setup
    private override init() {
        super.init()
        // Defer heavy initialization to avoid blocking app startup but ensure self remains strong
        DispatchQueue.global(qos: .utility).async {
            self.setupSession()
            self.setupLocationServices()
            self.setupMotionDetection()
        }

        // Monitor device orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        // Setup lock screen controls
        setupLockScreenControls()
    }

    // MARK: - Lock Screen Controls
    private func setupLockScreenControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Handle pause command (stop recording)
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            print("🔒 Lock screen pause button tapped")
            self?.stopRecording()
            return .success
        }

        // Handle play command (start recording)
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            print("🔒 Lock screen play button tapped")
            self?.startRecording()
            return .success
        }

        print("✅ Lock screen controls configured")
    }

    private func updateNowPlayingInfo(isRecording: Bool) {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

        if isRecording {
            var nowPlayingInfo = [String: Any]()
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Dashcam Recording"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "Active"
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = segmentDuration

            nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
            print("🔒 Lock screen info updated: Recording active")
        } else {
            nowPlayingInfoCenter.nowPlayingInfo = nil
            print("🔒 Lock screen info cleared: Recording stopped")
        }
    }

    private func setupSession() {
        guard !isSetup else { return }
        isSetup = true

        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                // Configure session on dedicated queue to avoid conflicts
                self.sessionQueue.async {
                    self.configureSession()
                }
            } else {
                print("❌ Camera permission denied")
            }
        }
    }

    private func configureSession() {
        isConfiguring = true
        session.beginConfiguration()

        // Set session preset for better quality
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        // Try different camera types for iPhone 15
        let cameraTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera
        ]

        var videoDevice: AVCaptureDevice?
        for deviceType in cameraTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: currentCameraPosition) {
                videoDevice = device
                print("✅ Found camera: \(deviceType)")
                break
            }
        }

        // Add video input
        if let videoDevice = videoDevice,
           let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
           session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
            videoInput = videoDeviceInput
            print("✅ Camera input added successfully")
        } else {
            print("❌ Failed to add camera input")
        }

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioDeviceInput) {
            session.addInput(audioDeviceInput)
            audioInput = audioDeviceInput
            print("✅ Audio input added successfully")
        } else {
            print("⚠️ Audio input not available")
        }

        // Add movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            print("✅ Movie output added successfully")

            // Configure movie output
            // IMPORTANT: Do NOT set movieFragmentInterval - it can cause issues with video processing
            // Keep movie fragments DISABLED for standard MOV files that work with all tools
            movieOutput.movieFragmentInterval = .invalid
            print("✅ Movie fragmentation DISABLED for compatibility")

            // No maxRecordedDuration limit - we'll handle segmentation manually with timer
            // No maxRecordedFileSize limit - we'll handle storage cleanup manually
            print("✅ No automatic recording duration/size limits")

            // Set initial video orientation
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    currentOrientation = UIDevice.current.orientation
                    connection.videoOrientation = videoOrientationFromDeviceOrientation(currentOrientation)
                    print("✅ Initial video orientation set to: \(connection.videoOrientation.rawValue)")
                }
            }
        }

        session.commitConfiguration()
        isConfiguring = false
        isSessionReady = true
        session.startRunning()
        print("✅ Camera session started and ready")
    }

    private func setupLocationServices() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5 // Update every 5 meters

        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("⚠️ Location access denied - GPS data will not be available")
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func setupMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let data = data, error == nil else { return }
            self?.processAccelerometerData(data.acceleration)
        }
    }

    // MARK: - Public Controls
    func startRecording() {
        sessionQueue.async {
            guard !self.isConfiguring && self.session.isRunning else {
                print("⚠️ Cannot start recording - session not ready")
                return
            }

            self.cleanupOldFiles()
            let fileURL = self.makeOutputURL()
            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
            print("Started recording to: \(fileURL)")

            // Update lock screen controls
            DispatchQueue.main.async {
                self.updateNowPlayingInfo(isRecording: true)
            }
        }
    }

    func stopRecording() {
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.stopLoopRecording()

            // Update lock screen controls
            DispatchQueue.main.async {
                self.updateNowPlayingInfo(isRecording: false)
            }
        }
    }

    func startLoopRecording() {
        isLoopRecording = true
        currentSegmentNumber = 0
        startNextSegment()

        // Update lock screen controls
        DispatchQueue.main.async {
            self.updateNowPlayingInfo(isRecording: true)
        }
    }

    func stopLoopRecording() {
        isLoopRecording = false
        segmentTimer?.invalidate()
        segmentTimer = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }

        // Update lock screen controls
        DispatchQueue.main.async {
            self.updateNowPlayingInfo(isRecording: false)
        }
    }

    private func startNextSegment() {
        guard isLoopRecording else { return }

        cleanupOldFiles()
        let fileURL = makeOutputURL(segment: currentSegmentNumber)
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        print("Started loop recording segment \(currentSegmentNumber) to: \(fileURL)")

        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: false) { [weak self] _ in
            self?.nextSegment()
        }
    }

    private func nextSegment() {
        guard isLoopRecording else { return }

        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }

        currentSegmentNumber += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startNextSegment()
        }
    }

    func switchCamera() {
        guard let currentInput = videoInput else { return }

        session.beginConfiguration()
        session.removeInput(currentInput)

        currentCameraPosition = currentCameraPosition == .back ? .front : .back

        if let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
           let newInput = try? AVCaptureDeviceInput(device: newCamera),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        } else {
            // If adding the new camera fails, add the old one back
            session.addInput(currentInput)
        }

        session.commitConfiguration()
    }

    func ensureSessionRunning() {
        sessionQueue.async {
            // Don't start if we're in the middle of configuration
            guard !self.isConfiguring else {
                print("🎥 Camera session configuration in progress, waiting...")
                // Retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.ensureSessionRunning()
                }
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
                print("🎥 Camera session restarted")
            }
        }
    }

    // MARK: - Orientation Handling

    /// Handle device orientation change notifications.
    ///
    /// This method is called automatically when UIDevice.orientationDidChangeNotification fires.
    /// It filters out invalid orientations (face up/down/unknown) and updates the video recording orientation.
    ///
    /// - Note: Registered as an observer in init()
    @objc private func deviceOrientationDidChange() {
        let deviceOrientation = UIDevice.current.orientation

        // Only handle valid orientations (ignore face up/down/unknown)
        guard deviceOrientation.isValidInterfaceOrientation else { return }

        currentOrientation = deviceOrientation
        updateVideoOrientation()
    }

    /// Update the video recording orientation to match the current device orientation.
    ///
    /// This ensures that recorded videos are always oriented correctly regardless of how
    /// the device is held. The update is performed on the dedicated sessionQueue to avoid
    /// conflicts with other camera operations.
    ///
    /// - Important: Only updates the movieOutput connection, not preview layers
    private func updateVideoOrientation() {
        sessionQueue.async {
            // Get the video orientation from device orientation
            let videoOrientation = self.videoOrientationFromDeviceOrientation(self.currentOrientation)

            // Update all video connections
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = videoOrientation
                    print("📱 Updated video recording orientation to: \(videoOrientation.rawValue)")
                }
            }
        }
    }

    /// Convert UIDeviceOrientation to AVCaptureVideoOrientation.
    ///
    /// The mapping between device orientation and video orientation is counterintuitive
    /// for landscape orientations because the camera sensor's physical orientation needs
    /// to be compensated for:
    /// - Device landscape left (home button on right) → Video landscape right
    /// - Device landscape right (home button on left) → Video landscape left
    ///
    /// - Parameter deviceOrientation: The current device orientation
    /// - Returns: The corresponding video orientation for AVCapture connections
    private func videoOrientationFromDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            // Device rotated left, video should be right
            return .landscapeRight
        case .landscapeRight:
            // Device rotated right, video should be left
            return .landscapeLeft
        default:
            return .portrait
        }
    }

    // MARK: - Public Properties
    var isRecording: Bool {
        return movieOutput.isRecording
    }

    var sessionForPreview: AVCaptureSession? {
        return isSessionReady ? session : nil
    }

    var currentRecordingURL: URL? {
        return movieOutput.outputFileURL
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate Methods
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            print("❌ Recording error: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            ObservabilityService.shared.error("Recording", "Recording failed", error: error)
            GoogleCloudMonitoring.shared.trackUploadFailure(error: error.localizedDescription)
        } else {
            print("✅ Recording finished. Saved to: \(outputFileURL)")

            // Get ACTUAL video duration from the file
            let actualDuration = getActualVideoDuration(outputFileURL)
            let fileSize = getFileSize(outputFileURL) ?? 0

            print("📹 Video details:")
            print("   - File: \(outputFileURL.lastPathComponent)")
            print("   - Size: \(Double(fileSize) / (1024 * 1024)) MB")
            print("   - Duration: \(actualDuration) seconds (\(actualDuration / 60) minutes)")
            print("   - Expected: \(segmentDuration) seconds")

            if actualDuration < segmentDuration / 2 {
                print("⚠️ WARNING: Video is much shorter than expected!")
                print("   Expected: \(segmentDuration)s, Got: \(actualDuration)s")
            }

            // Log with actual duration
            ObservabilityService.shared.info("Recording", "Recording completed", metadata: [
                "file_size": String(fileSize),
                "actual_duration": String(actualDuration),
                "expected_duration": String(segmentDuration),
                "file_path": outputFileURL.lastPathComponent,
                "is_short": String(actualDuration < segmentDuration / 2)
            ])
            GoogleCloudMonitoring.shared.trackVideoRecorded(duration: actualDuration)

            // Queue for cloud upload
            CloudStorageService.shared.queueForUpload(outputFileURL)
        }
    }

    // MARK: - Motion Detection
    private func processAccelerometerData(_ acceleration: CMAcceleration) {
        let totalAcceleration = sqrt(acceleration.x * acceleration.x +
                                   acceleration.y * acceleration.y +
                                   acceleration.z * acceleration.z)

        if totalAcceleration > impactThreshold {
            handleImpactDetected()
        }

        lastAcceleration = acceleration
    }

    private func handleImpactDetected() {
        print("🚨 Impact detected! Current recording will be protected.")

        // Log the impact detection
        ObservabilityService.shared.critical("CrashDetection", "Impact detected", metadata: [
            "threshold": String(impactThreshold),
            "is_recording": String(movieOutput.isRecording),
            "current_location": currentLocation?.description ?? "unknown"
        ])

        // Track crash detection in monitoring
        GoogleCloudMonitoring.shared.trackCrashDetected(gForce: impactThreshold)

        // If currently recording, mark as emergency priority
        if movieOutput.isRecording, let currentURL = movieOutput.outputFileURL {
            CloudStorageService.shared.markAsEmergency(currentURL)
        }
    }

    // MARK: - Storage Management
    private func cleanupOldFiles() {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let videoFiles = files.filter { $0.pathExtension == "mov" }
        let totalSize = videoFiles.compactMap { getFileSize($0) }.reduce(0, +)
        let maxBytes = Int64(maxStorageGB * 1024 * 1024 * 1024)

        if totalSize > maxBytes {
            cleanupExcessFiles(videoFiles)
        }
    }

    private func cleanupExcessFiles(_ files: [URL]) {
        let sortedFiles = files
            .filter { !emergencyProtectedFiles.contains($0) }
            .sorted { getCreationDate($0) < getCreationDate($1) }

        let maxBytes = Int64(maxStorageGB * 1024 * 1024 * 1024)
        var currentSize = files.compactMap { getFileSize($0) }.reduce(0, +)

        for file in sortedFiles {
            guard currentSize > maxBytes else { break }

            if let fileSize = getFileSize(file) {
                try? FileManager.default.removeItem(at: file)
                currentSize -= fileSize
                print("🗑️ Deleted old file: \(file.lastPathComponent)")
            }
        }
    }

    private func getFileSize(_ url: URL) -> Int64? {
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
    }

    private func getCreationDate(_ url: URL) -> Date {
        return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private func getActualVideoDuration(_ url: URL) -> Double {
        let asset = AVAsset(url: url)
        let duration = asset.duration
        let durationInSeconds = CMTimeGetSeconds(duration)

        if durationInSeconds.isNaN || durationInSeconds.isInfinite {
            print("⚠️ Warning: Video duration is invalid (NaN or infinite)")
            return 0
        }

        return durationInSeconds
    }

    // MARK: - Helper
    private func makeOutputURL(segment: Int? = nil) -> URL {
        let timestamp = Date().timeIntervalSince1970
        let filename: String

        if let segment = segment {
            filename = "dashcam_\(timestamp)_seg\(segment).mov"
        } else {
            filename = "dashcam_\(timestamp).mov"
        }

        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

// MARK: - CLLocationManagerDelegate
extension CameraService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("⚠️ Location access denied - GPS data will not be available")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }

    private func authorizationStatusString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }
}

