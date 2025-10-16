//
//  SystemMonitorService.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import Foundation
import UIKit

class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()

    @Published var batteryLevel: Float = 1.0
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var isLowPowerModeEnabled = false

    private var monitoringTimer: Timer?

    private init() {
        // Defer monitoring setup to avoid blocking UI initialization but ensure self remains strong
        DispatchQueue.global(qos: .utility).async {
            self.setupMonitoring()
            self.startMonitoring()
        }
    }

    // MARK: - Monitoring Setup
    private func setupMonitoring() {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Battery level notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        // Battery state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )

        // Thermal state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        // Low power mode notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerModeChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    private func startMonitoring() {
        updateCurrentValues()

        // Monitor every 30 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateCurrentValues()
            self?.checkSystemHealth()
        }
    }

    // MARK: - Notification Handlers
    @objc private func batteryLevelChanged() {
        DispatchQueue.main.async {
            self.batteryLevel = UIDevice.current.batteryLevel
            self.checkBatteryHealth()
        }
    }

    @objc private func batteryStateChanged() {
        DispatchQueue.main.async {
            self.batteryState = UIDevice.current.batteryState
            self.checkBatteryHealth()
        }
    }

    @objc private func thermalStateChanged() {
        DispatchQueue.main.async {
            self.thermalState = ProcessInfo.processInfo.thermalState
            self.checkThermalHealth()
        }
    }

    @objc private func powerModeChanged() {
        DispatchQueue.main.async {
            self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.checkPowerMode()
        }
    }

    // MARK: - Current Values Update
    private func updateCurrentValues() {
        DispatchQueue.main.async {
            self.batteryLevel = UIDevice.current.batteryLevel
            self.batteryState = UIDevice.current.batteryState
            self.thermalState = ProcessInfo.processInfo.thermalState
            self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: - Health Checks
    private func checkSystemHealth() {
        checkBatteryHealth()
        checkThermalHealth()
        checkPowerMode()
    }

    private func checkBatteryHealth() {
        if batteryLevel < 0.15 && batteryState != .charging {
            handleLowBattery()
        }
    }

    private func checkThermalHealth() {
        switch thermalState {
        case .critical, .serious:
            handleOverheating()
        case .fair:
            handleWarmDevice()
        case .nominal:
            // Normal operation
            break
        @unknown default:
            break
        }
    }

    private func checkPowerMode() {
        if isLowPowerModeEnabled {
            handleLowPowerMode()
        }
    }

    // MARK: - Response Actions
    private func handleLowBattery() {
        print("🔋 Low battery detected (\(Int(batteryLevel * 100))%) - Optimizing recording")

        // Reduce recording quality or pause non-essential uploads
        CloudStorageService.shared.configure(bucketName: "", projectId: "") // Pause uploads
    }

    private func handleOverheating() {
        print("🌡️ Device overheating - Stopping recording to prevent damage")

        // Stop recording to prevent device damage
        CameraService.shared.stopLoopRecording()

        // Show warning to user
        showTemperatureWarning()
    }

    private func handleWarmDevice() {
        print("🌡️ Device running warm - Monitoring thermal state")
        // Continue recording but monitor closely
    }

    private func handleLowPowerMode() {
        print("⚡ Low Power Mode enabled - Reducing background activity")

        // Reduce upload frequency
        // Reduce location update frequency
    }

    private func showTemperatureWarning() {
        // This would typically show a user alert
        print("⚠️ Device temperature too high. Recording stopped.")
    }

    // MARK: - Public Interface
    func getBatteryPercentage() -> Int {
        return Int(batteryLevel * 100)
    }

    func getThermalStateDescription() -> String {
        switch thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Warm"
        case .serious:
            return "Hot"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }

    func getBatteryStateDescription() -> String {
        switch batteryState {
        case .charging:
            return "Charging"
        case .full:
            return "Full"
        case .unplugged:
            return "On Battery"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    func isRecordingSafe() -> Bool {
        return thermalState != .critical && thermalState != .serious
    }

    deinit {
        monitoringTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}