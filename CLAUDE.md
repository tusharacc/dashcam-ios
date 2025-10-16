# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive SwiftUI-based iOS dashcam application with professional-grade features including loop recording, cloud storage, GPS tracking, incident detection, voice commands, and battery/thermal monitoring. The app automatically starts recording when connected to a car and provides continuous background operation.

## Architecture

The app follows a service-oriented architecture with multiple singleton services:

### Core Services
- **CameraService**: Core recording functionality with loop recording and incident detection
- **CloudStorageService**: Automatic upload queue with Google Cloud Storage integration
- **AutoStartService**: Car connectivity detection (CarPlay/Bluetooth) and auto-recording
- **VoiceCommandService**: Speech recognition for hands-free control
- **SystemMonitorService**: Battery and thermal monitoring with safety protections
- **ObservabilityService**: Comprehensive logging and monitoring with Google Cloud integration

### UI Components
- **ContentView**: Main dashboard with camera preview, controls, and status indicators
- **VideoOverlayView**: Real-time timestamp and GPS overlay on video feed
- **SettingsView**: Comprehensive settings and system status monitoring
- **CameraPreview**: UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
- **LogViewerView**: In-app log viewing and analytics interface
- **LogAnalyticsView**: Log analytics dashboard with error rates and category breakdowns

Key architectural patterns:
- Singleton pattern for all services to maintain global state
- SwiftUI + UIKit integration via UIViewRepresentable
- ObservableObject protocol for reactive UI updates
- Background task processing for uploads and monitoring

## Development Commands

### Building and Running
```bash
# Open project in Xcode
open dashcam.xcodeproj

# Build from command line
xcodebuild -project dashcam.xcodeproj -scheme dashcam build

# Run tests
xcodebuild test -project dashcam.xcodeproj -scheme dashcam -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Testing
The project uses Swift Testing framework (not XCTest):
- Test files: `dashcamTests/dashcamTests.swift`, `dashcamUITests/dashcamUITests.swift`
- Use `@Test` annotation instead of XCTest's `func test...`
- Use `#expect(...)` for assertions instead of XCTAssert

## Key Features

### Loop Recording System (CameraService.swift:112)
- Automatic 5-minute video segments with seamless transitions
- Smart storage management (8GB default limit)
- Automatic cleanup of oldest files
- Emergency file protection for incident recordings

### Cloud Integration (CloudStorageService.swift:28)
- Automatic upload queue with priority system
- Network-aware uploading (WiFi/cellular detection)
- Video compression before upload
- 3-month retention with automatic lifecycle management
- Background upload processing

### Auto-Start Functionality (AutoStartService.swift:35)
- CarPlay and Bluetooth connectivity detection
- Automatic recording start/stop based on car connection
- Background audio session management
- User-configurable auto-start settings

### Voice Commands (VoiceCommandService.swift:45)
Supported commands:
- "Start recording" / "Stop recording"
- "Switch camera" / "Flip camera"
- "Emergency" / "Incident" (marks current recording as protected)
- "Status" (speaks system status)

### Motion Detection (CameraService.swift:192)
- CoreMotion accelerometer monitoring
- Impact detection with configurable G-force threshold (2.5G default)
- Automatic emergency file protection on impact
- Real-time motion data processing

### GPS Integration (VideoOverlayView.swift:18)
- Real-time location tracking with CoreLocation
- Speed monitoring and display
- GPS coordinates embedded in video overlay
- Location-based features (future: privacy zones)

### System Monitoring (SystemMonitorService.swift:45)
- Battery level and charging state monitoring
- Thermal state monitoring with recording protection
- Low power mode detection
- Automatic recording stops on overheating

### Observability & Logging (ObservabilityService.swift:13)
- Google Cloud Logging integration with cost optimization
- Local file storage with automatic rotation (50MB limit, 7-day retention)
- Batching and sampling for cost control (10 logs per batch, 5-minute intervals)
- Network-aware logging (queue when offline, send when online)
- In-app log viewer with search, filtering, and analytics
- Performance tracking and error monitoring
- iOS system logging integration with os.log
- Export functionality for debugging and support

## Required Permissions

Add these to Info.plist:
```xml
<key>NSCameraUsageDescription</key>
<string>Required for dashcam video recording</string>
<key>NSMicrophoneUsageDescription</key>
<string>Required for audio recording and voice commands</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Required for GPS data in recordings</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Required for voice commands</string>
```

## Configuration

### Google Cloud Storage Setup
1. Create Google Cloud project and storage bucket
2. Configure lifecycle policy for 3-month retention
3. Set bucket name and project ID in SettingsView
4. Add service account credentials (implementation needed)

### Storage Management
- Default: 8GB local storage limit
- Videos saved as: `dashcam_[timestamp]_seg[N].mov`
- Location: `FileManager.default.temporaryDirectory`
- Emergency files protected from auto-deletion

### Voice Commands
- Requires microphone and speech recognition permissions
- English language support (configurable)
- Hands-free operation for driving safety

## File Structure

```
dashcam/
├── dashcamApp.swift              # Main app entry point with service initialization
├── ContentView.swift             # Main dashboard UI with camera preview and controls
├── CameraPreview.swift           # UIViewRepresentable for AVCaptureVideoPreviewLayer
├── VideoOverlayView.swift        # Real-time timestamp and GPS overlay component
├── SettingsView.swift            # Settings and system status monitoring UI
├── LogViewerView.swift           # In-app log viewing and analytics interface
├── ObservabilityService.swift   # Comprehensive logging and monitoring service
└── Services/
    ├── CameraService.swift       # Core camera recording with loop recording
    ├── CloudStorageService.swift # Upload queue and Google Cloud integration
    ├── AutoStartService.swift    # Car connectivity detection and auto-recording
    ├── VoiceCommandService.swift # Speech recognition and voice commands
    └── SystemMonitorService.swift # Battery and thermal monitoring
```

## Implementation Status

✅ **Completed Features:**
- Loop recording with automatic segmentation (5-min segments)
- Storage management with cleanup and emergency file protection
- Car connectivity detection (CarPlay/Bluetooth) with auto-start
- Motion detection and impact sensing (CoreMotion)
- GPS location tracking and speed monitoring
- Video overlays with timestamp and GPS data
- Cloud upload queue with network awareness
- Voice command recognition and TTS responses
- Battery and thermal monitoring with safety shutdowns
- Comprehensive settings UI with system status
- Real-time status indicators on main dashboard
- **Observability & Logging System:**
  - Google Cloud Logging integration with cost optimization
  - Local log storage with automatic rotation and retention
  - In-app log viewer with search, filtering, and analytics
  - Performance tracking and error monitoring
  - Network-aware log batching and sampling
  - iOS system logging integration
  - Export functionality for debugging support

🔧 **Setup Required:**
- iOS permissions configuration in Info.plist
- Google Cloud Storage credentials integration
- Google Cloud Logging API credentials configuration
- Background processing capabilities in Xcode
- Physical device testing for full functionality

⚠️ **Known Issues:**
- Orientation change delays still present (logged for analysis via ObservabilityService)
- Google Cloud authentication setup needed for cloud logging functionality

## Development Notes

- All services use @Published properties for SwiftUI reactivity
- ObservableObject pattern ensures UI updates automatically
- Singleton services maintain global state across app lifecycle
- Background processing configured for continuous operation
- Thermal monitoring prevents device damage from overheating
- Network monitoring optimizes upload scheduling
- CarPlay integration for automotive use cases
- Voice commands designed for hands-free driving safety
- Emergency file protection system for incident recordings
- Smart storage cleanup prevents device storage overflow
- **Observability System:**
  - Cost-optimized logging with batching (10 logs per batch, 5-minute intervals)
  - Local logs stored in app Documents directory with 7-day retention
  - Sampling rates configurable (0.1-1.0) for cost control
  - Network-aware: queues logs when offline, sends when online
  - Critical logs (crashes/errors) bypass sampling and are sent immediately
  - In-app log viewer accessible via Settings > Logging & Observability