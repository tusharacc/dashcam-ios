//
//  VoiceCommandService.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import Foundation
import Speech
import AVFoundation

class VoiceCommandService: NSObject, ObservableObject {
    static let shared = VoiceCommandService()

    @Published var isListening = false
    @Published var lastCommand = ""

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private override init() {
        super.init()
    }

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            print("❌ Speech recognition not authorized")
            return false
        }

        // Request microphone permission
        let micStatus = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micStatus else {
            print("❌ Microphone access not authorized")
            return false
        }

        return true
    }

    // MARK: - Voice Command Recognition
    func startListening() async {
        guard await requestPermissions() else { return }

        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Configure audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true

            // Start recognition
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                if let result = result {
                    let command = result.bestTranscription.formattedString.lowercased()
                    self?.processVoiceCommand(command)

                    if result.isFinal {
                        self?.stopListening()
                    }
                }

                if let error = error {
                    print("❌ Speech recognition error: \(error)")
                    self?.stopListening()
                }
            }
        } catch {
            print("❌ Failed to start voice recognition: \(error)")
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    // MARK: - Command Processing
    private func processVoiceCommand(_ command: String) {
        lastCommand = command
        print("🎤 Voice command: \(command)")

        DispatchQueue.main.async {
            if command.contains("start recording") || command.contains("begin recording") {
                CameraService.shared.startLoopRecording()
                self.speakResponse("Recording started")

            } else if command.contains("stop recording") || command.contains("end recording") {
                CameraService.shared.stopLoopRecording()
                self.speakResponse("Recording stopped")

            } else if command.contains("switch camera") || command.contains("flip camera") {
                CameraService.shared.switchCamera()
                self.speakResponse("Camera switched")

            } else if command.contains("emergency") || command.contains("incident") {
                self.handleEmergencyCommand()
                self.speakResponse("Emergency mode activated")

            } else if command.contains("status") {
                self.speakStatus()

            } else {
                print("❓ Unknown voice command: \(command)")
            }
        }
    }

    private func handleEmergencyCommand() {
        // Mark current recording as emergency
        if let currentURL = CameraService.shared.currentRecordingURL {
            CloudStorageService.shared.markAsEmergency(currentURL)
        }

        // Ensure recording is active
        if !CameraService.shared.isRecording {
            CameraService.shared.startLoopRecording()
        }
    }

    private func speakStatus() {
        let isRecording = CameraService.shared.isRecording
        let uploadStatus = CloudStorageService.shared.getUploadStatus()
        let connectionStatus = AutoStartService.shared.isCarConnected ? "connected" : "disconnected"

        let status = """
        Dashcam status: \(isRecording ? "Recording" : "Standby").
        Car \(connectionStatus).
        \(uploadStatus.queued) files queued for upload.
        """

        speakResponse(status)
    }

    // MARK: - Text-to-Speech
    private func speakResponse(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
}

// MARK: - Convenience Extensions
extension VoiceCommandService {
    func toggleListening() async {
        if isListening {
            stopListening()
        } else {
            await startListening()
        }
    }
}