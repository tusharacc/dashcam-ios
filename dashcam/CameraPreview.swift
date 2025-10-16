//
//  CameraPreview.swift
//  dashcam
//
//  Created by Tushar Saurabh on 6/26/25.
//
//  This file provides optimized camera preview components with seamless orientation handling.
//  Key features:
//  - Zero-lag orientation changes using persistent AVCaptureSession
//  - Main thread optimization for AVCaptureVideoPreviewLayer creation
//  - Smart frame calculation based on screen dimensions
//  - Equatable conformance to prevent unnecessary view recreation
//

import SwiftUI
import AVFoundation

/// Stateful camera preview wrapper that waits for AVCaptureSession to be ready.
///
/// This view manages the camera preview lifecycle and ensures smooth orientation transitions
/// by maintaining a persistent ViewModel across orientation changes.
///
/// - Note: Uses @ObservedObject to react to session availability changes
struct SafeCameraPreview: View {
    @ObservedObject var viewModel: CameraPreviewViewModel

    /// Initialize with an optional ViewModel
    /// - Parameter viewModel: Optional ViewModel to use. Creates a new one if nil.
    init(viewModel: CameraPreviewViewModel? = nil) {
        if let viewModel = viewModel {
            self.viewModel = viewModel
        } else {
            // Fallback: create a new one (shouldn't happen in our app)
            self.viewModel = CameraPreviewViewModel()
        }
    }

    var body: some View {
        CameraPreview(session: viewModel.session)
            .equatable() // Prevent recreation when session doesn't change
            .id(viewModel.id) // Stable ID across orientation changes
    }
}

/// ViewModel that manages the AVCaptureSession lifecycle and availability.
///
/// This class polls CameraService for session availability and publishes it to SwiftUI.
/// It maintains a stable UUID identity to prevent view recreation during orientation changes.
///
/// - Important: Uses a timer-based polling approach to detect when the camera session becomes ready
class CameraPreviewViewModel: ObservableObject {
    /// Stable identifier that persists across orientation changes
    let id = UUID()

    /// Published camera session - updates trigger UI refresh
    @Published var session: AVCaptureSession?

    /// Timer for polling session availability
    private var refreshTimer: Timer?

    /// Timestamp when initialization started (for performance tracking)
    private let initStartTime = Date()

    /// Timestamp when session was found (for performance tracking)
    private var sessionFoundTime: Date?

    /// Initialize the ViewModel and begin checking for session availability
    init() {
        print("⏱️ [CameraPreviewViewModel] Initialization started (id: \(id))")
        checkForSession()
        if session == nil {
            print("⏱️ [CameraPreviewViewModel] Session not ready, starting timer")
            startSessionTimer()
        }
    }

    /// Check if the camera session is available from CameraService
    private func checkForSession() {
        let checkStart = Date()
        if let readySession = CameraService.shared.sessionForPreview {
            if sessionFoundTime == nil {
                sessionFoundTime = Date()
                let elapsed = sessionFoundTime!.timeIntervalSince(initStartTime)
                print("⏱️ [CameraPreviewViewModel] ✅ Session found after \(String(format: "%.3f", elapsed))s, isRunning: \(readySession.isRunning)")
            }

            DispatchQueue.main.async {
                let publishStart = Date()
                self.session = readySession
                self.refreshTimer?.invalidate()
                self.refreshTimer = nil
                let publishTime = Date().timeIntervalSince(publishStart)
                print("⏱️ [CameraPreviewViewModel] ✅ Session published to UI (took \(String(format: "%.3f", publishTime))s)")
            }
        } else {
            let elapsed = Date().timeIntervalSince(initStartTime)
            let checkTime = Date().timeIntervalSince(checkStart)
            print("⏱️ [CameraPreviewViewModel] ⏳ Session not ready yet (elapsed: \(String(format: "%.3f", elapsed))s, check took: \(String(format: "%.3f", checkTime))s)")
        }
    }

    /// Start a timer to poll for session availability every 0.5 seconds
    private func startSessionTimer() {
        guard refreshTimer == nil else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForSession()
        }
    }

    /// Clean up timer on deinitialization
    deinit {
        refreshTimer?.invalidate()
        print("⏱️ [CameraPreviewViewModel] Deinitialized")
    }
}

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer with orientation handling.
///
/// This struct bridges UIKit's AVCaptureVideoPreviewLayer to SwiftUI and manages:
/// - Preview layer creation on the main thread for optimal performance
/// - Dynamic frame updates based on screen dimensions during orientation changes
/// - Orientation synchronization for preview and recorded video
///
/// - Important: Conforms to Equatable to prevent recreation when session doesn't change
struct CameraPreview: UIViewRepresentable, Equatable {
    let session: AVCaptureSession?

    /// Stable identifier based on the session object pointer
    private var sessionIdentifier: String {
        if let session = session {
            return "\(Unmanaged.passUnretained(session).toOpaque())"
        }
        return "noSession"
    }

    /// Equatable implementation to prevent unnecessary view recreation
    ///
    /// Only recreates the view if the actual AVCaptureSession instance changes,
    /// not when other properties change. This is critical for orientation performance.
    ///
    /// - Returns: True if both previews reference the same session instance
    static func == (lhs: CameraPreview, rhs: CameraPreview) -> Bool {
        // Only recreate if the actual session object changes
        let isEqual = lhs.session === rhs.session
        let lhsId = lhs.session != nil ? "\(Unmanaged.passUnretained(lhs.session!).toOpaque())" : "nil"
        let rhsId = rhs.session != nil ? "\(Unmanaged.passUnretained(rhs.session!).toOpaque())" : "nil"
        print("⏱️ [CameraPreview] Equatable check - lhs: \(lhsId), rhs: \(rhsId), equal: \(isEqual)")
        return isEqual
    }

    /// Create the UIView with AVCaptureVideoPreviewLayer
    ///
    /// This method creates the preview layer on the main thread for optimal performance.
    /// Previously creating the layer on a background thread caused 9-second delays.
    ///
    /// - Parameter context: The UIViewRepresentable context
    /// - Returns: A UIView containing the preview layer or placeholder
    func makeUIView(context: Context) -> UIView {
        let makeUIViewStartTime = Date()
        let view = UIView()
        view.backgroundColor = .black

        let sessionId = session != nil ? "\(Unmanaged.passUnretained(session!).toOpaque())" : "nil"
        print("⏱️ [CameraPreview] makeUIView called - sessionId: \(sessionId), isRunning: \(session?.isRunning ?? false), bounds: \(view.bounds)")

        // Show placeholder only if no session available
        if session == nil {
            let label = UILabel()
            label.text = "Starting Camera..."
            label.textColor = .white
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            label.tag = 999 // Tag for easy removal
            view.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            print("⏱️ [CameraPreview] makeUIView showing placeholder")
        }

        // Create preview layer on main thread if session is available
        if let session = session {
            print("⏱️ [CameraPreview] makeUIView has session, creating preview layer on main thread")

            let layerCreationStartTime = Date()
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            let layerCreationTime = Date().timeIntervalSince(layerCreationStartTime)

            // Remove placeholder
            view.subviews.first(where: { $0.tag == 999 })?.removeFromSuperview()

            // Add preview layer
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            context.coordinator.layer = preview
            context.coordinator.parentView = view

            // Set initial orientation
            context.coordinator.setInitialOrientation()

            let totalTime = Date().timeIntervalSince(makeUIViewStartTime)
            print("⏱️ [CameraPreview] ✅ Preview layer created and added")
            print("⏱️ [CameraPreview] ⏱️  Layer creation: \(String(format: "%.3f", layerCreationTime))s")
            print("⏱️ [CameraPreview] ⏱️  makeUIView total: \(String(format: "%.3f", totalTime))s")
        } else {
            print("⏱️ [CameraPreview] makeUIView waiting for session to be ready")
        }

        return view
    }

    /// Update the UIView when SwiftUI triggers a refresh
    ///
    /// This method handles:
    /// - Updating the preview layer frame to match new view bounds
    /// - Creating the preview layer if session becomes available after initial creation
    /// - Maintaining the parent view reference in the Coordinator
    ///
    /// - Parameters:
    ///   - uiView: The UIView to update
    ///   - context: The UIViewRepresentable context with Coordinator
    func updateUIView(_ uiView: UIView, context: Context) {
        let updateStartTime = Date()
        print("⏱️ [CameraPreview] updateUIView called - hasLayer: \(context.coordinator.layer != nil), hasSession: \(session != nil), bounds: \(uiView.bounds)")

        // Update preview layer frame if it exists
        if let layer = context.coordinator.layer {
            let oldFrame = layer.frame
            layer.frame = uiView.bounds
            print("⏱️ [CameraPreview] updateUIView updated layer frame from \(oldFrame) to \(uiView.bounds)")
        }

        // If we now have a session but didn't before, create preview layer on main thread
        if let session = self.session, context.coordinator.layer == nil {
            print("⏱️ [CameraPreview] updateUIView session became available, creating preview layer on main thread")

            let layerCreationStartTime = Date()
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            let layerCreationTime = Date().timeIntervalSince(layerCreationStartTime)

            // Remove placeholder if it exists
            uiView.subviews.first(where: { $0.tag == 999 })?.removeFromSuperview()

            // Add preview layer
            preview.frame = uiView.bounds
            uiView.layer.addSublayer(preview)
            context.coordinator.layer = preview
            context.coordinator.parentView = uiView

            // Set initial orientation
            context.coordinator.setInitialOrientation()

            let totalTime = Date().timeIntervalSince(updateStartTime)
            print("⏱️ [CameraPreview] ✅ updateUIView preview layer created")
            print("⏱️ [CameraPreview] ⏱️  Layer creation: \(String(format: "%.3f", layerCreationTime))s")
            print("⏱️ [CameraPreview] ⏱️  updateUIView total: \(String(format: "%.3f", totalTime))s")
        }

        // Always update parent view reference
        context.coordinator.parentView = uiView
    }

    /// Create the Coordinator for managing preview layer and orientation
    ///
    /// - Returns: A new Coordinator instance
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Coordinator class that manages orientation changes and preview layer updates.
    ///
    /// This class:
    /// - Observes device orientation changes via NotificationCenter
    /// - Updates the preview layer frame using screen dimensions (not view bounds)
    /// - Updates the preview layer orientation to match device orientation
    /// - Maintains weak reference to parent view to prevent retain cycles
    ///
    /// - Important: Frame calculation uses screen dimensions to avoid race conditions with view bounds
    class Coordinator {
        /// The AVCaptureVideoPreviewLayer being managed
        var layer: AVCaptureVideoPreviewLayer?

        /// Weak reference to the parent UIView to prevent retain cycles
        weak var parentView: UIView?

        /// Orientation change observer token
        private var orientationObserver: NSObjectProtocol?

        /// Initialize and begin observing orientation changes
        init() {
            // Observe orientation changes
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updatePreviewOrientation()
                // Also update frame on orientation change
                self?.updateLayerFrame()
            }
        }

        /// Clean up orientation observer
        deinit {
            if let observer = orientationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        /// Update the preview layer frame based on screen dimensions and orientation.
        ///
        /// This method uses UIScreen.main.bounds instead of view.bounds because view.bounds
        /// may not have updated yet when the orientation notification fires. A small delay
        /// (0.05s) ensures the frame update happens after the rotation animation begins.
        ///
        /// - Note: Uses CATransaction to disable implicit animations for crisp updates
        func updateLayerFrame() {
            guard let previewLayer = layer, let view = parentView else {
                print("⏱️ [Coordinator] updateLayerFrame - layer or view nil")
                return
            }

            // Use a small delay to let the view bounds update after rotation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                guard let view = view, let previewLayer = self?.layer else { return }

                // Get the correct frame based on screen dimensions and orientation
                let screenBounds = UIScreen.main.bounds
                let deviceOrientation = UIDevice.current.orientation

                let newFrame: CGRect
                if deviceOrientation.isLandscape {
                    // In landscape, width should be the larger dimension
                    let width = max(screenBounds.width, screenBounds.height)
                    let height = min(screenBounds.width, screenBounds.height)
                    newFrame = CGRect(x: 0, y: 0, width: width, height: height)
                } else {
                    // In portrait, height should be the larger dimension
                    let width = min(screenBounds.width, screenBounds.height)
                    let height = max(screenBounds.width, screenBounds.height)
                    newFrame = CGRect(x: 0, y: 0, width: width, height: height)
                }

                let oldFrame = previewLayer.frame
                CATransaction.begin()
                CATransaction.setDisableActions(true) // Disable implicit animations
                previewLayer.frame = newFrame
                CATransaction.commit()
                print("⏱️ [Coordinator] ✅ Updated layer frame from \(oldFrame) to \(newFrame) (deviceOrientation: \(deviceOrientation.rawValue), screen: \(screenBounds))")
            }
        }

        /// Set the initial orientation of the preview layer.
        ///
        /// This is called once when the preview layer is first created. It determines
        /// the correct orientation either from the device orientation or screen dimensions.
        ///
        /// - Note: If device orientation is unknown, falls back to screen dimensions
        func setInitialOrientation() {
            let startTime = Date()
            guard let previewLayer = layer else {
                print("⏱️ [Coordinator] setInitialOrientation - no layer available")
                return
            }

            let deviceOrientation = UIDevice.current.orientation
            let videoOrientation: AVCaptureVideoOrientation

            // Handle initial orientation, defaulting to portrait if unknown
            if deviceOrientation.isValidInterfaceOrientation {
                videoOrientation = videoOrientationFromDeviceOrientation(deviceOrientation)
            } else {
                // Check if we're in landscape based on screen dimensions
                if UIScreen.main.bounds.width > UIScreen.main.bounds.height {
                    videoOrientation = .landscapeRight
                } else {
                    videoOrientation = .portrait
                }
            }

            // Set initial preview layer orientation
            if let connection = previewLayer.connection {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = videoOrientation
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("⏱️ [Coordinator] ✅ Set initial preview layer orientation to: \(videoOrientation.rawValue) (\(String(format: "%.3f", elapsed))s)")
                }
            }
        }

        /// Update the preview layer orientation when device orientation changes.
        ///
        /// This method is called automatically when orientation change notifications fire.
        /// It updates the AVCaptureConnection's videoOrientation to match the device.
        private func updatePreviewOrientation() {
            let startTime = Date()
            guard let previewLayer = layer else { return }

            let deviceOrientation = UIDevice.current.orientation

            // Only handle valid orientations
            guard deviceOrientation.isValidInterfaceOrientation else { return }

            // Update preview layer orientation
            if let connection = previewLayer.connection {
                if connection.isVideoOrientationSupported {
                    let videoOrientation = videoOrientationFromDeviceOrientation(deviceOrientation)
                    connection.videoOrientation = videoOrientation
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("⏱️ [Coordinator] ✅ Updated preview layer orientation to: \(videoOrientation.rawValue) (\(String(format: "%.3f", elapsed))s)")
                }
            }
        }

        /// Convert UIDeviceOrientation to AVCaptureVideoOrientation.
        ///
        /// Note the counterintuitive mapping for landscape orientations:
        /// - Device landscape left → Video landscape right
        /// - Device landscape right → Video landscape left
        ///
        /// This compensates for the camera sensor's physical orientation.
        ///
        /// - Parameter deviceOrientation: The current device orientation
        /// - Returns: The corresponding video orientation for AVCapture
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
    }
}
