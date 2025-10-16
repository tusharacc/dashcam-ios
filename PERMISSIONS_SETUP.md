# Required iOS Permissions Setup

For the dashcam app to work properly on iPhone 15 with iOS 18, you need to add these permissions to your `Info.plist` file.

## How to Add Permissions

1. **Open your Xcode project**
2. **Find Info.plist** in the project navigator (or Target → Info → Custom iOS Target Properties)
3. **Add these entries:**

### Required Permissions:

```xml
<!-- Camera Access -->
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to record dashcam videos while driving.</string>

<!-- Microphone Access -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio with dashcam videos and for voice commands.</string>

<!-- Location Access - CRITICAL: Use this exact key -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>This dashcam app needs location access while recording to embed GPS coordinates and speed data in videos for safety and legal purposes.</string>

<!-- DO NOT ADD THIS - it causes "When I Share" option -->
<!-- <key>NSLocationUsageDescription</key> -->

<!-- Make sure you DON'T have these keys that cause sharing permission -->
<!-- <key>NSLocationTemporaryUsageDescriptionDictionary</key> -->
<!-- <key>NSLocationDefaultAccuracyReduced</key> -->

<!-- Speech Recognition -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app uses speech recognition for hands-free voice commands while driving.</string>

<!-- Background Modes (for continuous recording) -->
<key>UIBackgroundModes</key>
<array>
    <string>background-audio</string>
    <string>background-processing</string>
</array>
```

## Alternative: Add via Xcode Interface

1. **Select your target** in Xcode
2. **Go to Info tab**
3. **Add these keys with descriptions:**

| Key | Value |
|-----|-------|
| `Privacy - Camera Usage Description` | This app needs camera access to record dashcam videos while driving. |
| `Privacy - Microphone Usage Description` | This app needs microphone access to record audio with dashcam videos and for voice commands. |
| `Privacy - Location When In Use Usage Description` | This app needs location access to embed GPS coordinates and speed in dashcam recordings. |
| `Privacy - Speech Recognition Usage Description` | This app uses speech recognition for hands-free voice commands while driving. |

## Background Modes

1. **Go to Signing & Capabilities**
2. **Add Background Modes capability**
3. **Check these options:**
   - Audio, AirPlay, and Picture in Picture
   - Background processing

## Testing

After adding permissions:
1. **Clean build** (Cmd+Shift+K)
2. **Delete app** from device
3. **Build and run** again
4. **Grant permissions** when prompted

This should fix the camera preview issue on iOS 18!