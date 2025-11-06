# Lock Screen Controls Setup

The dashcam app supports lock screen controls so you can stop/start recording without unlocking your phone.

## Required Setup in Xcode

To enable lock screen controls, you MUST enable **Background Modes** in Xcode:

### Steps:

1. **Open Xcode** and load the dashcam project

2. **Select the dashcam target**:
   - In the left sidebar, click on the blue `dashcam` project icon
   - In the main panel, select the `dashcam` target (under TARGETS)

3. **Go to "Signing & Capabilities" tab**:
   - Click on the "Signing & Capabilities" tab at the top

4. **Add Background Modes capability**:
   - Click the "+ Capability" button
   - Search for "Background Modes"
   - Double-click to add it

5. **Enable Audio background mode**:
   - In the Background Modes section that appears, check the box for:
     - ✅ **Audio, AirPlay, and Picture in Picture**

6. **Build and run** the app on your iPhone

## How It Works

Once background audio mode is enabled:

### When Recording:
- Lock your iPhone
- You'll see **"Dashcam Recording"** on the lock screen
- Subtitle: **"Tap pause to stop"**
- Tap the **⏸ pause button** to stop recording

### When Not Recording:
- Lock your iPhone
- You'll see **"Dashcam"** on the lock screen
- Subtitle: **"Tap play to record"**
- Tap the **▶️ play button** to start recording

### Also Works In:
- Control Center (swipe down from top-right)
- CarPlay (if connected)
- Bluetooth headset controls

## Troubleshooting

### Lock screen controls not appearing?

1. **Check background mode is enabled**:
   - Go back to step 5 above and verify "Audio, AirPlay, and Picture in Picture" is checked

2. **Make sure recording has started**:
   - The controls only appear after you start recording in the app
   - Or after the app is running and audio session is active

3. **Check Xcode console**:
   Look for these messages:
   ```
   ✅ Audio session activated for lock screen controls
   ✅ Lock screen controls configured (play, pause, toggle)
   🔒 Lock screen info updated: Recording active
   🔒 Pause command enabled, play command disabled
   ```

4. **Restart the app**:
   - Force quit the app
   - Rebuild and reinstall from Xcode
   - Start recording
   - Lock the screen

### Controls appear but don't work?

Check Xcode console for messages like:
```
🔒 Lock screen pause button tapped
```

If you see the message, the command is working. If not, there may be an issue with the MPRemoteCommandCenter setup.

## Technical Details

The lock screen controls work by:
1. **AVAudioSession**: Configured with `.playAndRecord` category and `.mixWithOthers` option
2. **MPRemoteCommandCenter**: Handles play/pause/toggle commands
3. **MPNowPlayingInfoCenter**: Displays "Now Playing" info on lock screen
4. **Background Mode**: "Audio" mode keeps the app's audio session active

The app activates the audio session immediately on launch, even before recording starts, so the lock screen controls are ready to use.
