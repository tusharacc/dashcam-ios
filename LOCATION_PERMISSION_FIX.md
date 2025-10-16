# Fix Location Permission - Get "While Using App" Option

The "When I Share" option appears because the wrong location permission is being requested. Here's how to fix it:

## ❌ Current Issue:
- Settings only shows "Never" and "When I Share"
- Missing "While Using App" option

## ✅ Solution:

### 1. Check Your Info.plist
Make sure you have **ONLY** this location permission entry:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This dashcam app needs location access while recording to embed GPS coordinates and speed data in videos for safety and legal purposes.</string>
```

### 2. Remove These If Present:
**Delete these keys if they exist in your Info.plist:**

```xml
<!-- REMOVE THESE - they cause "When I Share" option -->
<key>NSLocationUsageDescription</key>
<key>NSLocationTemporaryUsageDescriptionDictionary</key>
<key>NSLocationDefaultAccuracyReduced</key>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<key>NSLocationAlwaysUsageDescription</key>
```

### 3. Steps to Fix:

1. **Open Xcode**
2. **Select your target** → Info tab
3. **Find "Custom iOS Target Properties"**
4. **Look for location-related keys**
5. **Keep ONLY**: `Privacy - Location When In Use Usage Description`
6. **Delete any others** related to location

### 4. Alternative - Edit Info.plist File Directly:

1. **Right-click Info.plist** → Open As → Source Code
2. **Find all `<key>` entries containing "Location"**
3. **Keep only** `NSLocationWhenInUseUsageDescription`
4. **Delete the rest**

### 5. Reset Permissions:

1. **Delete the app** from your device
2. **Clean build** (Cmd+Shift+K)
3. **Build and run** again
4. **Grant permission** when prompted

### 6. Verify Result:

After the fix, Settings should show:
- ✅ **Never**
- ✅ **While Using App** ← This is what you want!

## Why This Happens:

- `NSLocationUsageDescription` (deprecated) → "When I Share"
- `NSLocationWhenInUseUsageDescription` → "While Using App"
- Multiple location keys → Confuses iOS permission system

## Test:

After fixing, you should see GPS coordinates in the top-right overlay instead of "GPS..."