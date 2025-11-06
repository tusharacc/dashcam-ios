# Dashcam Upload Status Check

## Step 1: Check Settings
On your iPhone in the Dashcam app:
1. Settings → Google Cloud Storage
2. Verify:
   - ✅ Bucket Name: `my-dashcam-storage`
   - ✅ Service Account configured (green checkmark)
3. Tap **"Test Connection"**
   - Should show: ✅ "Connection successful"

## Step 2: Check Logs
1. Settings → Logging & Observability → **View Logs**
2. Search for: `Upload` or `GCS`
3. Look for recent entries from yesterday

## Common Issues & Solutions

### Issue 1: "Service account key not configured"
**Fix:** Re-select the JSON service account file in Settings

### Issue 2: "Upload failed with status: 403" 
**Fix:** Service account needs Storage Object Creator role in Google Cloud

### Issue 3: "Bucket 'my-dashcam-storage' does not exist"
**Fix:** Verify bucket name in Google Cloud Console matches app settings

### Issue 4: Videos queued but not uploading
**Check:**
- Network connectivity (WiFi preferred)
- Settings → Upload queue status
- Battery level (uploads pause on low battery)

