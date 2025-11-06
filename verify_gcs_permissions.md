# Verify Google Cloud Storage Permissions

Since you're in Google Cloud Console, check these:

## 1. Verify Bucket Exists
1. Go to: https://console.cloud.google.com/storage/browser?project=my-dashcam-472908
2. Look for bucket: `my-dashcam-storage`
3. Check if any videos are there (folder: `dashcam/YYYY/MM/DD/`)

## 2. Check Service Account Permissions
1. Go to: https://console.cloud.google.com/storage/browser/my-dashcam-storage?project=my-dashcam-472908
2. Click **PERMISSIONS** tab
3. Find: `dashcam-uploader@my-dashcam-472908.iam.gserviceaccount.com`
4. Should have role: **Storage Object Creator** or **Storage Admin**

## 3. If Service Account Missing Permissions:
```bash
# Add Storage Object Creator role
1. Click "GRANT ACCESS"
2. Principal: dashcam-uploader@my-dashcam-472908.iam.gserviceaccount.com
3. Role: Storage Object Creator
4. Click "SAVE"
```

## 4. Test Upload Manually
Try uploading a test file to verify permissions:
```bash
# From terminal (if gcloud CLI available):
echo "test" > test.txt
gcloud storage cp test.txt gs://my-dashcam-storage/test/test.txt
```

