import SwiftUI
import AVFoundation

/// Main dashboard view with optimized orientation handling.
///
/// This view implements a performance-optimized architecture for seamless orientation changes:
/// - **Persistent Camera Preview**: Single @StateObject camera preview that never gets recreated
/// - **Conditional Overlays**: Only UI overlays change based on orientation, not the camera
/// - **Minimal State Updates**: Only updates isLandscape when orientation actually changes
/// - **Zero-Lag Transitions**: Instant orientation changes without view recreation
///
/// ## Architecture
/// The view uses a ZStack with:
/// 1. Bottom layer: Persistent SafeCameraPreview (full screen, never changes)
/// 2. Top layer: Conditional overlays (landscapeOverlay or portraitOverlay)
///
/// This prevents the expensive recreation of AVCaptureVideoPreviewLayer on orientation changes.
struct ContentView: View {
    // MARK: - Recording State
    @State private var isRecording = false
    @State private var isLoopMode = true
    @State private var recordings: [URL] = []
    @State private var showingSettings = false

    // MARK: - Service State
    /// Lazy service initialization flag to prevent blocking UI startup
    @State private var servicesInitialized = false
    @State private var batteryPercentage = 100
    @State private var isRecordingSafe = true
    @State private var isOnline = false
    @State private var isCarConnected = false
    @State private var isVoiceListening = false

    // MARK: - Upload State
    @State private var showUploadAlert = false
    @State private var uploadMessage = ""

    // MARK: - Orientation State
    /// Efficient orientation tracking - only changes when orientation actually changes
    @State private var isLandscape = false

    /// Persistent camera preview ViewModel that survives orientation changes
    /// - Important: @StateObject ensures this persists across view updates
    @StateObject private var sharedCameraPreview = CameraPreviewViewModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Single persistent camera preview that never gets recreated - always full screen
                SafeCameraPreview(viewModel: sharedCameraPreview)
                    .edgesIgnoringSafeArea(.all)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        DispatchQueue.global(qos: .userInitiated).async {
                            CameraService.shared.ensureSessionRunning()
                        }
                    }

                // Overlay controls that change based on orientation
                if isLandscape {
                    landscapeOverlay()
                } else {
                    portraitOverlay(screenHeight: geometry.size.height)
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Immediate orientation update without debouncing
            updateOrientationState()
        }
        .onAppear {
            updateOrientationState()
            initializeServicesIfNeeded()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Upload Started", isPresented: $showUploadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadMessage)
        }
    }

    /// Update the orientation state when device orientation changes.
    ///
    /// This method is called when UIDevice.orientationDidChangeNotification fires.
    /// It performs a minimal state update to switch between portrait and landscape overlays
    /// without recreating the camera preview.
    ///
    /// Key optimizations:
    /// - Only updates state if orientation actually changed
    /// - Uses screen dimensions as fallback when orientation is unknown
    /// - Logs orientation change for performance monitoring
    ///
    /// - Note: The persistent camera preview is NOT recreated during this update
    private func updateOrientationState() {
        let startTime = Date()
        let orientation = UIDevice.current.orientation
        let newIsLandscape = orientation.isLandscape ||
                           (orientation == .unknown && UIScreen.main.bounds.width > UIScreen.main.bounds.height)

        // Only update if actually changed to minimize view recreation
        if newIsLandscape != isLandscape {
            let fromOrientation = isLandscape ? "Landscape" : "Portrait"
            let toOrientation = newIsLandscape ? "Landscape" : "Portrait"

            print("⏱️ [ContentView] 📱 Orientation changing from \(fromOrientation) to \(toOrientation)")

            // Update immediately
            isLandscape = newIsLandscape

            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️ [ContentView] ✅ Orientation state updated in \(String(format: "%.3f", elapsed))s")

            // Log orientation change
            ObservabilityService.shared.logOrientation(from: fromOrientation, to: toOrientation, duration: elapsed)
        }
    }

    // MARK: - Landscape Overlay
    private func landscapeOverlay() -> some View {
        ZStack {
            // Video overlay
            VideoOverlayView()

            // Landscape controls overlay
            VStack {
                // Status bar at top
                HStack {
                    // System status
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(isRecordingSafe ? .green : .red)
                                .frame(width: 6, height: 6)
                            Text("\(batteryPercentage)%")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }

                        if isOnline {
                            Image(systemName: "wifi")
                                .foregroundColor(.green)
                                .font(.caption2)
                        }

                        if isCarConnected {
                            Image(systemName: "car.fill")
                                .foregroundColor(.blue)
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)

                    Spacer()

                    // Recording status
                    HStack(spacing: 8) {
                        if isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("REC")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                            }
                        }

                        Text(isLoopMode ? "LOOP" : "SINGLE")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(15)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                // Recording controls at bottom
                HStack {
                    Spacer()

                    // Mode toggle
                    Button(action: toggleMode) {
                        Text(isLoopMode ? "LOOP" : "SINGLE")
                            .font(.caption)
                            .foregroundColor(isLoopMode ? .blue : .gray)
                    }

                    Spacer()

                    // Main record button
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red.opacity(0.8) : Color.red)
                                .frame(width: 70, height: 70)

                            if isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            } else {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 50, height: 50)
                            }
                        }
                    }

                    Spacer()

                    // Settings
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - Portrait Overlay
    private func portraitOverlay(screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Top quarter: camera preview area with overlay controls
            ZStack {
                // Video overlay with timestamp and GPS
                VideoOverlayView()

                VStack {
                    // Clean status bar at top
                    HStack {
                        // Left side - system status in compact form
                        HStack(spacing: 8) {
                            // Battery
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isRecordingSafe ? .green : .red)
                                    .frame(width: 6, height: 6)
                                Text("\(batteryPercentage)%")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }

                            // Online status
                            if isOnline {
                                Image(systemName: "wifi")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                            }

                            // Car connection
                            if isCarConnected {
                                Image(systemName: "car.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)

                        Spacer()

                        // Right side - recording mode and status
                        HStack(spacing: 8) {
                            if isRecording {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("REC")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .fontWeight(.semibold)
                                }
                            }

                            Text(isLoopMode ? "LOOP" : "SINGLE")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Spacer()

                    // Control buttons - larger record button, smaller others
                    VStack(spacing: 12) {
                        // Main record button - larger and prominent
                        Button(action: toggleRecording) {
                            ZStack {
                                Circle()
                                    .fill(isRecording ? Color.red.opacity(0.8) : Color.red)
                                    .frame(width: 80, height: 80)

                                if isRecording {
                                    // When recording - show pulsing effect and stop icon
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .frame(width: 24, height: 24)
                                        .scaleEffect(isRecording ? 1.0 : 0.8)
                                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)
                                } else {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }

                        // Secondary controls row
                        HStack(spacing: 24) {
                            Button(action: toggleMode) {
                                VStack(spacing: 2) {
                                    Image(systemName: isLoopMode ? "repeat" : "record.circle")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                    Text(isLoopMode ? "LOOP" : "SINGLE")
                                        .font(.caption2)
                                        .foregroundColor(isLoopMode ? .blue : .gray)
                                }
                            }

                            Button(action: {
                                CameraService.shared.switchCamera()
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }

                            Button(action: {
                                Task {
                                    await VoiceCommandService.shared.toggleListening()
                                    await updateVoiceStatus()
                                }
                            }) {
                                Image(systemName: isVoiceListening ? "mic.fill" : "mic")
                                    .font(.title2)
                                    .foregroundColor(isVoiceListening ? .blue : .white)
                            }

                            Button(action: {
                                showingSettings = true
                            }) {
                                Image(systemName: "gearshape")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .frame(height: 300)

            // Bottom three-quarters: recorded files (with black background to cover camera preview)
            VStack(spacing: 0) {
                // Section header
                HStack {
                    Text("Recorded Files")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    Spacer()
                    Text("(\(recordings.count) files)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(red: 0.15, green: 0.15, blue: 0.15))

                if recordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                            .foregroundColor(.gray)

                        Text("No recordings yet")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Text("Press the record button to start capturing")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    VStack(spacing: 0) {
                        // Upload status header
                        HStack {
                            let stats = CloudStorageService.shared.getVideoStats()
                            Text("\(stats.localOnly) videos need upload")
                                .font(.caption)
                                .foregroundColor(stats.localOnly > 0 ? .orange : .green)

                            Spacer()

                            if stats.localOnly > 0 {
                                Button(action: {
                                    print("🔵 Upload All button tapped - queuing \(stats.localOnly) videos")
                                    CloudStorageService.shared.uploadAllLocalVideos()

                                    // Show feedback alert
                                    uploadMessage = "Queued \(stats.localOnly) video(s) for upload. Check logs for details."
                                    showUploadAlert = true

                                    // Refresh recordings list
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        fetchRecordings()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "icloud.and.arrow.up")
                                        Text("Upload All")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.15, green: 0.15, blue: 0.15))

                        List(recordings, id: \.self) { url in
                            HStack {
                                // Cloud status indicator
                                Image(systemName: CloudStorageService.shared.isFileInCloud(url) ? "icloud.fill" : "iphone")
                                    .foregroundColor(CloudStorageService.shared.isFileInCloud(url) ? .green : .orange)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(formatFileDate(url))
                                            .font(.caption2)
                                            .foregroundColor(.gray)

                                        if CloudStorageService.shared.isFileInCloud(url) {
                                            Text("• Cloud")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("• Local")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }

                                Spacer()

                                Text(formatFileSize(url))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.black)
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.black)
                    }
                }
            }
            .background(Color.black)
            .onAppear { fetchRecordings() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                fetchRecordings()
            }
        }
    }

    private func toggleRecording() {
        let startTime = Date()
        isRecording.toggle()

        if isRecording {
            if isLoopMode {
                CameraService.shared.startLoopRecording()
                ObservabilityService.shared.logRecordingEvent(type: "start_loop_recording")
            } else {
                CameraService.shared.startRecording()
                ObservabilityService.shared.logRecordingEvent(type: "start_single_recording")
            }
        } else {
            let duration = Date().timeIntervalSince(startTime)
            if isLoopMode {
                CameraService.shared.stopLoopRecording()
                ObservabilityService.shared.logRecordingEvent(type: "stop_loop_recording", duration: duration)
            } else {
                CameraService.shared.stopRecording()
                ObservabilityService.shared.logRecordingEvent(type: "stop_single_recording", duration: duration)
            }
            fetchRecordings()
        }
    }

    private func toggleMode() {
        guard !isRecording else { return }
        isLoopMode.toggle()
    }

    private func fetchRecordings() {
        let dir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) {
            recordings = files
                .filter { $0.pathExtension == "mov" }
                .sorted { ($0.creationDate) > ($1.creationDate) }
        }
        print("📁 Found \(recordings.count) recordings")
    }

    private func formatFileDate(_ url: URL) -> String {
        let date = url.creationDate
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFileSize(_ url: URL) -> String {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "Unknown"
        }

        let bytes = Double(fileSize)
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        }
    }

    // MARK: - Service Management
    private func initializeServicesIfNeeded() {
        guard !servicesInitialized else { return }
        servicesInitialized = true

        // Log app launch
        ObservabilityService.shared.logAppLaunch()

        // Initialize services in background and update UI state periodically
        DispatchQueue.global(qos: .utility).async {
            // Initialize services
            _ = SystemMonitorService.shared
            _ = CloudStorageService.shared
            _ = AutoStartService.shared
            _ = VoiceCommandService.shared
            _ = ObservabilityService.shared

            ObservabilityService.shared.info("ServiceInit", "All services initialized")

            // Update UI every few seconds
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    await updateServiceStatus()
                }
            }

            // Initial status update
            Task { @MainActor in
                await updateServiceStatus()
            }
        }
    }

    @MainActor
    private func updateServiceStatus() async {
        batteryPercentage = SystemMonitorService.shared.getBatteryPercentage()
        isRecordingSafe = SystemMonitorService.shared.isRecordingSafe()
        isOnline = CloudStorageService.shared.isOnline
        isCarConnected = AutoStartService.shared.isCarConnected
        isVoiceListening = VoiceCommandService.shared.isListening
    }

    @MainActor
    private func updateVoiceStatus() async {
        isVoiceListening = VoiceCommandService.shared.isListening
    }
}

private extension URL {
    var creationDate: Date {
        (try? resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

#Preview {
    ContentView()
}