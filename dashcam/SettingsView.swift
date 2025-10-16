//
//  SettingsView.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var autoStartService = AutoStartService.shared
    @StateObject private var systemMonitor = SystemMonitorService.shared
    @StateObject private var cloudService = CloudStorageService.shared
    @StateObject private var voiceService = VoiceCommandService.shared
    @StateObject private var observabilityService = ObservabilityService.shared

    @State private var segmentDuration: Double = 300
    @State private var maxStorageGB: Double = 8.0
    @State private var compressionEnabled = true
    @State private var bucketName = "my-dashcam-storage"
    @State private var projectId = "my-dashcam-472908"
    @State private var serviceAccountConfigured = false
    @State private var showingFilePicker = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    // Logging settings
    @State private var showingLogViewer = false
    @State private var showingLogAnalytics = false

    var body: some View {
        NavigationView {
            List {
                Section("Recording Settings") {
                    Toggle("Auto-start when car connects", isOn: .init(
                        get: { autoStartService.autoRecordEnabled },
                        set: { autoStartService.setAutoRecordEnabled($0) }
                    ))

                    VStack(alignment: .leading) {
                        Text("Segment Duration: \(Int(segmentDuration / 60)) minutes")
                        Slider(value: $segmentDuration, in: 60...1800, step: 60)
                    }

                    VStack(alignment: .leading) {
                        Text("Max Local Storage: \(Int(maxStorageGB)) GB")
                        Slider(value: $maxStorageGB, in: 1...32, step: 1)
                    }
                }

                Section("Google Cloud Storage") {
                    HStack {
                        Text("Project ID")
                        Spacer()
                        Text(projectId)
                            .foregroundColor(.secondary)
                    }

                    TextField("Bucket Name", text: $bucketName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    HStack {
                        Text("Service Account")
                        Spacer()
                        if serviceAccountConfigured {
                            HStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Configured")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        } else {
                            Text("Not configured")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }

                    Button("Select Service Account Key") {
                        showingFilePicker = true
                    }

                    Toggle("Enable compression", isOn: $compressionEnabled)

                    Button("Save Cloud Settings") {
                        saveCloudSettings()
                    }
                    .disabled(bucketName.isEmpty)

                    if serviceAccountConfigured {
                        Button("Test Authentication") {
                            testAuthentication()
                        }
                        .foregroundColor(.blue)
                    }
                }

                Section("Voice Commands") {
                    Button(voiceService.isListening ? "Stop Listening" : "Start Voice Commands") {
                        Task {
                            await voiceService.toggleListening()
                        }
                    }
                    .foregroundColor(voiceService.isListening ? .red : .blue)

                    if !voiceService.lastCommand.isEmpty {
                        Text("Last command: \(voiceService.lastCommand)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Logging & Observability") {
                    Toggle("Enable Cloud Logging", isOn: .init(
                        get: { observabilityService.settings.enableCloudLogging },
                        set: { observabilityService.settings.enableCloudLogging = $0 }
                    ))

                    Toggle("Debug Mode", isOn: .init(
                        get: { observabilityService.settings.enableDebugMode },
                        set: { observabilityService.settings.enableDebugMode = $0 }
                    ))

                    VStack(alignment: .leading) {
                        Text("Sample Rate: \(Int(observabilityService.settings.sampleRate * 100))%")
                        Slider(value: .init(
                            get: { observabilityService.settings.sampleRate },
                            set: { observabilityService.settings.sampleRate = $0 }
                        ), in: 0.1...1.0, step: 0.1)
                    }

                    Button("View Logs") {
                        showingLogViewer = true
                    }
                    .foregroundColor(.blue)

                    Button("Log Analytics") {
                        showingLogAnalytics = true
                    }
                    .foregroundColor(.blue)

                    Button("Export Logs") {
                        exportLogs()
                    }
                    .foregroundColor(.green)
                }

                Section("System Status") {
                    SystemStatusRow(
                        label: "Battery",
                        value: "\(systemMonitor.getBatteryPercentage())%",
                        status: systemMonitor.getBatteryStateDescription(),
                        color: batteryColor
                    )

                    SystemStatusRow(
                        label: "Temperature",
                        value: systemMonitor.getThermalStateDescription(),
                        status: systemMonitor.isRecordingSafe() ? "Safe" : "Hot",
                        color: thermalColor
                    )

                    SystemStatusRow(
                        label: "Car Connection",
                        value: autoStartService.isCarConnected ? "Connected" : "Disconnected",
                        status: "",
                        color: autoStartService.isCarConnected ? .green : .gray
                    )

                    let uploadStatus = cloudService.getUploadStatus()
                    SystemStatusRow(
                        label: "Upload Queue",
                        value: "\(uploadStatus.queued) queued",
                        status: "\(uploadStatus.uploading) uploading",
                        color: cloudService.isOnline ? .green : .orange
                    )
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let files):
                    if let file = files.first {
                        handleServiceAccountFile(file)
                    }
                case .failure(let error):
                    print("❌ File picker error: \(error)")
                }
            }
            .onAppear {
                loadSettings()
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingLogViewer) {
                LogViewerView()
            }
            .sheet(isPresented: $showingLogAnalytics) {
                LogAnalyticsView()
            }
        }
    }

    private func exportLogs() {
        observabilityService.info("Settings", "Exporting logs from settings")

        if let exportURL = observabilityService.exportLogs() {
            let activityController = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityController, animated: true)
            }
        }
    }

    private func loadSettings() {
        bucketName = UserDefaults.standard.string(forKey: "CloudBucketName") ?? "my-dashcam-storage"
        compressionEnabled = UserDefaults.standard.bool(forKey: "CompressionEnabled")
        serviceAccountConfigured = UserDefaults.standard.bool(forKey: "ServiceAccountConfigured")
    }

    private func saveCloudSettings() {
        do {
            cloudService.configure(bucketName: bucketName, projectId: projectId)
            UserDefaults.standard.set(bucketName, forKey: "CloudBucketName")
            UserDefaults.standard.set(compressionEnabled, forKey: "CompressionEnabled")

            alertTitle = "Success"
            alertMessage = "Cloud settings saved successfully!"
            showingAlert = true
            print("✅ Cloud settings saved")
        } catch {
            alertTitle = "Error"
            alertMessage = "Failed to save cloud settings: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func handleServiceAccountFile(_ url: URL) {
        // Request access to the file
        guard url.startAccessingSecurityScopedResource() else {
            alertTitle = "Error"
            alertMessage = "Unable to access the selected file"
            showingAlert = true
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        do {
            let keyData = try Data(contentsOf: url)

            // Validate it's a JSON file
            guard let json = try JSONSerialization.jsonObject(with: keyData) as? [String: Any],
                  json["type"] as? String == "service_account",
                  json["private_key"] != nil,
                  json["client_email"] != nil else {
                throw NSError(domain: "InvalidServiceAccount", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid service account key file"])
            }

            cloudService.setServiceAccount(keyData: keyData)
            serviceAccountConfigured = true
            UserDefaults.standard.set(true, forKey: "ServiceAccountConfigured")

            alertTitle = "Success"
            alertMessage = "Service account key configured successfully!"
            showingAlert = true
            print("✅ Service account key configured")

        } catch {
            serviceAccountConfigured = false
            UserDefaults.standard.set(false, forKey: "ServiceAccountConfigured")

            alertTitle = "Error"
            alertMessage = "Failed to configure service account: \(error.localizedDescription)"
            showingAlert = true
            print("❌ Failed to load service account key: \(error)")
        }
    }

    private var batteryColor: Color {
        if systemMonitor.batteryLevel < 0.2 {
            return .red
        } else if systemMonitor.batteryLevel < 0.5 {
            return .orange
        } else {
            return .green
        }
    }

    private var thermalColor: Color {
        switch systemMonitor.thermalState {
        case .nominal:
            return .green
        case .fair:
            return .yellow
        case .serious:
            return .orange
        case .critical:
            return .red
        @unknown default:
            return .gray
        }
    }

    private func testAuthentication() {
        Task {
            print("🧪 Testing Google Cloud authentication...")

            // Force a token refresh to test authentication
            let success = await cloudService.testAuthentication()

            await MainActor.run {
                if success {
                    alertTitle = "Success"
                    alertMessage = "Google Cloud authentication test successful! Uploads should work now."
                } else {
                    alertTitle = "Authentication Failed"
                    alertMessage = "Could not authenticate with Google Cloud. Please check your service account key and try again."
                }
                showingAlert = true
            }
        }
    }
}

struct SystemStatusRow: View {
    let label: String
    let value: String
    let status: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)

            Spacer()

            VStack(alignment: .trailing) {
                Text(value)
                    .font(.caption)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}