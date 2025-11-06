//
//  AutoStartService.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import Foundation
import AVFoundation
import ExternalAccessory
import MediaPlayer

class AutoStartService: ObservableObject {
    static let shared = AutoStartService()

    @Published var isCarConnected = false
    @Published var autoRecordEnabled = true
    private var isInitialized = false

    private var audioSession: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }

    private init() {
        // Defer setup to avoid blocking UI initialization but ensure self remains strong
        DispatchQueue.global(qos: .utility).async {
            self.setupAudioSessionMonitoring()
            self.setupBluetoothMonitoring()
            DispatchQueue.main.async {
                self.isInitialized = true
            }
        }
    }

    // MARK: - Audio Route Monitoring (CarPlay detection)
    private func setupAudioSessionMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }

    @objc private func audioRouteChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else {
            return
        }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            checkCarConnection()
        default:
            break
        }
    }

    // MARK: - Bluetooth Monitoring
    private func setupBluetoothMonitoring() {
        // Monitor external accessory connections
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidConnect),
            name: .EAAccessoryDidConnect,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDidDisconnect),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
    }

    @objc private func accessoryDidConnect(_ notification: Notification) {
        checkCarConnection()
    }

    @objc private func accessoryDidDisconnect(_ notification: Notification) {
        checkCarConnection()
    }

    // MARK: - Car Connection Detection
    private func checkCarConnection() {
        let currentRoute = audioSession.currentRoute
        let isCarPlayConnected = currentRoute.outputs.contains { output in
            output.portType == .carAudio
        }

        let isBluetoothCarConnected = currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP
        }

        let wasConnected = isCarConnected
        isCarConnected = isCarPlayConnected || isBluetoothCarConnected

        // Auto-start recording when car connects
        if !wasConnected && isCarConnected && autoRecordEnabled {
            autoStartRecording()
        }

        // Auto-stop recording when car disconnects
        if wasConnected && !isCarConnected && autoRecordEnabled {
            autoStopRecording()
        }

        print("🚗 Car connection status: \(isCarConnected ? "Connected" : "Disconnected")")
    }

    // MARK: - Auto Recording Control
    private func autoStartRecording() {
        print("🚗 Car connected - Auto-starting loop recording")
        DispatchQueue.main.async {
            CameraService.shared.startLoopRecording()
        }
    }

    private func autoStopRecording() {
        print("🚗 Car disconnected - Auto-stopping recording")
        DispatchQueue.main.async {
            CameraService.shared.stopLoopRecording()
        }
    }

    // MARK: - Settings
    func setAutoRecordEnabled(_ enabled: Bool) {
        autoRecordEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "AutoRecordEnabled")
    }

    func loadSettings() {
        autoRecordEnabled = UserDefaults.standard.bool(forKey: "AutoRecordEnabled")
    }

    // MARK: - Manual Controls
    func forceCheckConnection() {
        guard isInitialized else {
            // Retry after a delay if not initialized yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.forceCheckConnection()
            }
            return
        }
        checkCarConnection()
    }
}

// MARK: - Background App Support
extension AutoStartService {
    func configureBackgroundRecording() {
        guard isInitialized else {
            // Retry after a delay if not initialized yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.configureBackgroundRecording()
            }
            return
        }

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers]
            )
            try audioSession.setActive(true)
            print("✅ Audio session configured to mix with Spotify/music apps")
        } catch {
            print("❌ Failed to configure audio session for background recording: \(error)")
        }
    }
}