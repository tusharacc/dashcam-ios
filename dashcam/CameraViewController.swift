//
//  CameraViewController.swift
//  dashcam
//
//  Created by Tushar Saurabh on 6/24/25.
//

import UIKit
import AVFoundation

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {

    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice)
        else {
            print("Failed to get video/audio devices.")
            return
        }

        captureSession.beginConfiguration()

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        captureSession.commitConfiguration()

        // Set up the preview
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        // Start camera
        captureSession.startRunning()

        // Start recording automatically
        startRecording()
    }

    func startRecording() {
        let outputDirectory = FileManager.default.temporaryDirectory
        let fileURL = outputDirectory.appendingPathComponent("dashcam_\(Date().timeIntervalSince1970).mov")

        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        print("Recording started at: \(fileURL)")
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        } else {
            print("Recording finished. Saved to \(outputFileURL)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}
