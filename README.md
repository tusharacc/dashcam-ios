# 🚗 Dashcam iOS App

A professional-grade iOS dashcam application with intelligent features for safe driving and automatic incident recording.

## ✨ Features

### 🎥 **Smart Recording**
- **Loop Recording**: Continuous 5-minute segments with automatic storage management
- **Auto-Start**: Automatically begins recording when connected to your car via CarPlay or Bluetooth
- **Emergency Protection**: Impact detection automatically protects important footage
- **Dual Camera Support**: Switch between front and rear cameras
- **Seamless Orientation**: Instant rotation support with optimized camera preview (portrait/landscape)

### 🌍 **GPS & Location**
- **Real-time GPS Tracking**: Embeds coordinates and speed in video overlay
- **Location Metadata**: GPS data stored with video files
- **Speed Display**: Shows current driving speed on video overlay
- **Timestamp Overlay**: Date and time burned into video footage

### ☁️ **Cloud Backup**
- **Automatic Upload**: Videos uploaded to Google Cloud Storage when online
- **Smart Compression**: Reduces file sizes before upload
- **3-Month Retention**: Automatic cleanup of old cloud files
- **Priority Queue**: Emergency recordings uploaded first

### 🎤 **Voice Control**
- **Hands-free Operation**: Control recording with voice commands
- **Supported Commands**:
  - "Start recording" / "Stop recording"
  - "Switch camera"
  - "Emergency" (protects current recording)
  - "Status" (reads system status aloud)

### 🔋 **Smart Monitoring**
- **Battery Optimization**: Monitors battery level and adjusts operation
- **Temperature Protection**: Automatically stops recording if device overheats
- **System Health**: Real-time monitoring of device performance
- **Connection Status**: Shows car, network, and system connectivity

### 📊 **Observability & Logging**
- **Comprehensive Logging**: Real-time monitoring with Google Cloud integration
- **In-App Log Viewer**: Search, filter, and analyze logs directly in the app
- **Performance Tracking**: Monitor orientation changes, recording events, and system metrics
- **Cost-Optimized Cloud Logging**: Smart batching and sampling to minimize costs
- **Local Log Storage**: Automatic rotation with 7-day retention and 50MB limit
- **Export Functionality**: Share logs for debugging and support

### 🚨 **Safety Features**
- **Impact Detection**: G-sensor detects accidents and protects footage
- **Emergency Mode**: One-touch activation for incident recording
- **Automatic Cleanup**: Manages storage to prevent device overflow
- **Background Operation**: Continues recording when app is backgrounded

## 📱 Requirements

- **iOS 15.0+**
- **iPhone with camera**
- **Storage**: Minimum 2GB free space (8GB recommended)
- **Permissions**: Camera, Microphone, Location, Speech Recognition

## 🚀 Installation

1. **Clone the repository**
   ```bash
   git clone [repository-url]
   cd dashcam
   ```

2. **Open in Xcode**
   ```bash
   open dashcam.xcodeproj
   ```

3. **Configure permissions in Info.plist**
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

4. **Build and run** on your device

## ⚙️ Setup & Configuration

### 📡 **Google Cloud Storage** (Required for Cloud Backup)

**Quick Setup:**
1. **Project**: `my-dashcam-472908` (pre-configured)
2. **Create bucket**: `dashcam-storage-bucket` (or your preferred name)
3. **Enable APIs**: Cloud Storage API
4. **Create service account** with Storage Object Creator role
5. **Download JSON key** and load it in app settings

**Detailed Setup Guide:** See [GOOGLE_CLOUD_SETUP.md](GOOGLE_CLOUD_SETUP.md) for complete instructions.

**In the App:**
1. Settings → Google Cloud Storage
2. Enter bucket name
3. Tap "Select Service Account Key" → choose downloaded JSON file
4. Tap "Save Cloud Settings"

### 🚗 **Car Integration**
- Connect your iPhone to CarPlay or car's Bluetooth
- Enable "Auto-start when car connects" in Settings
- The app will automatically start recording when connected

### 🎙️ **Voice Commands**
- Grant microphone and speech recognition permissions
- Tap the microphone button to activate listening
- Speak commands clearly for best recognition

### 📊 **Observability Setup**
- Access Settings → Logging & Observability for configuration
- Configure Google Cloud Logging for remote monitoring (optional)
- Adjust sample rates (10%-100%) to control logging costs
- Enable debug mode for detailed diagnostic information
- Use in-app log viewer to monitor real-time system performance

## 🎮 Usage

### **Basic Operation**
1. **Launch the app** - Camera preview appears instantly
2. **Tap record button** - Begins recording (red circle icon)
3. **Toggle loop mode** - Switch between continuous and single recording
4. **Rotate device** - UI and video seamlessly adapt to portrait/landscape orientation
5. **Access settings** - Tap gear icon for configuration
6. **View logs** - Settings → Logging & Observability → View Logs

### **Voice Commands**
- **"Start recording"** - Begins loop recording
- **"Stop recording"** - Stops current recording
- **"Switch camera"** - Changes between front/rear camera
- **"Emergency"** - Marks current recording as protected
- **"Status"** - Speaks battery, connection, and recording status

### **Emergency Mode**
- **Automatic**: G-sensor detects impacts and protects footage
- **Manual**: Say "Emergency" or use emergency button
- **Protected files**: Won't be deleted during storage cleanup

## 📊 System Indicators

### **Status Lights**
- 🟢 **Green**: Normal operation, good battery, connected
- 🟡 **Yellow**: Warning state, moderate battery, searching GPS
- 🔴 **Red**: Critical state, low battery, overheating
- 🔵 **Blue**: Car connected, voice listening active

### **Main Dashboard**
- **Battery percentage**: Shows current battery level
- **Online status**: Indicates internet connectivity
- **Car connection**: Shows when connected to vehicle
- **Recording indicator**: Flashing red dot when recording
- **Log status**: Real-time logging and monitoring indicators

## 🗂️ File Management

### **Local Storage**
- **Location**: iOS temporary directory
- **Format**: .mov files with H.264 compression
- **Naming**: `dashcam_[timestamp]_seg[number].mov`
- **Automatic cleanup**: Removes oldest files when storage limit reached

### **Cloud Storage** (if configured)
- **Upload**: Automatic when online
- **Retention**: 3 months (configurable)
- **Priority**: Emergency files uploaded first
- **Compression**: Reduced quality for storage efficiency

## 🔧 Troubleshooting

### **Recording Issues**
- **No recording**: Check camera permissions
- **Audio missing**: Grant microphone permission
- **Storage full**: Increase storage limit in settings or delete old files
- **Wrong orientation**: Videos and preview automatically adapt to device orientation

### **Voice Commands Not Working**
- Grant speech recognition permission
- Ensure microphone access is enabled
- Speak clearly and avoid background noise
- Check that voice listening is activated (blue microphone icon)

### **Auto-Start Not Working**
- Verify CarPlay or Bluetooth connection to car
- Enable "Auto-start when car connects" in settings
- Check that the car audio system is properly paired

### **Cloud Upload Issues**
- Verify internet connection
- Check Google Cloud Storage configuration
- Ensure sufficient cloud storage quota
- Review upload queue in settings

### **Logging and Monitoring Issues**
- **No logs visible**: Check if logging is enabled in Settings → Logging & Observability
- **Cloud logs not uploading**: Verify Google Cloud Logging API credentials
- **High logging costs**: Reduce sample rate or disable non-essential log categories
- **Log viewer crashes**: Clear local logs or reduce log retention period

## 🛡️ Privacy & Security

- **Local Processing**: All analysis done on device
- **Optional Cloud**: Cloud storage is completely optional
- **No Tracking**: App doesn't collect personal data
- **Secure Storage**: Files encrypted with iOS security
- **Permission Control**: You control all data access

## 🏗️ Technical Highlights

### **Orientation Optimization**
The app features advanced orientation handling with zero lag:
- **Persistent Camera Preview**: Single AVCaptureSession maintained across orientation changes
- **Smart Frame Calculation**: Preview layer dimensions calculated from screen bounds rather than view bounds
- **Main Thread Optimization**: All AVCaptureVideoPreviewLayer operations on main thread for instant updates
- **Video Recording Orientation**: Automatically updates AVCaptureConnection orientation for correct video output
- **UI Adaptation**: Conditional overlays switch instantly without recreating camera preview

## 🔮 Future Enhancements

- **Night Mode**: Enhanced low-light recording
- **Privacy Zones**: Automatic recording pause in sensitive locations
- **Advanced Analytics**: Traffic pattern recognition
- **Multiple Camera Support**: Front and rear simultaneous recording
- **Backup Redundancy**: Multiple cloud provider support
- **Advanced Logging**: Machine learning-powered log analysis and anomaly detection
- **Real-time Alerts**: Push notifications for critical system events

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📞 Support

- **Issues**: Report bugs or request features via GitHub Issues
- **Documentation**: See CLAUDE.md for development guidance
- **Updates**: Check releases for latest features and fixes

---

**⚠️ Important**: Always ensure your device is properly mounted and the app doesn't obstruct your view while driving. Follow local laws regarding recording devices in vehicles.