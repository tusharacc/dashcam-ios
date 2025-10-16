# Google Cloud Storage Setup Guide

This guide will help you set up Google Cloud Storage for your dashcam app with project ID `my-dashcam-472908`.

## Prerequisites

- Google Cloud account
- Access to Google Cloud Console
- Project ID: `my-dashcam-472908` (already configured in the app)

## Step 1: Enable APIs

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project `my-dashcam-472908`
3. Navigate to **APIs & Services** > **Library**
4. Enable the following APIs:
   - **Cloud Storage API**
   - **Cloud Storage JSON API**

## Step 2: Create Storage Bucket

1. Go to **Cloud Storage** > **Buckets**
2. Click **Create Bucket**
3. Configure the bucket:
   - **Name**: `dashcam-storage-bucket` (or your preferred name)
   - **Location Type**: Choose based on your needs:
     - `Region` for lowest latency (single region)
     - `Multi-region` for highest availability
   - **Storage Class**: `Standard` (for frequent access)
   - **Access Control**: `Uniform` (recommended)

## Step 3: Set Up Lifecycle Management

1. In your bucket, go to **Lifecycle**
2. Click **Add Rule**
3. Configure automatic deletion:
   - **Condition**: Age
   - **Days**: `90` (3 months)
   - **Action**: Delete object

This will automatically delete videos older than 3 months to save storage costs.

## Step 4: Create Service Account

1. Go to **IAM & Admin** > **Service Accounts**
2. Click **Create Service Account**
3. Fill in details:
   - **Name**: `dashcam-uploader`
   - **Description**: `Service account for dashcam video uploads`
4. Click **Create and Continue**
5. Grant roles:
   - **Storage Object Creator** (to upload files)
   - **Storage Object Viewer** (to read file metadata)
6. Click **Done**

## Step 5: Generate Service Account Key

1. Find your service account in the list
2. Click on the service account name
3. Go to **Keys** tab
4. Click **Add Key** > **Create New Key**
5. Choose **JSON** format
6. Click **Create**
7. **Important**: Save the downloaded JSON file securely

## Step 6: Configure the App

1. Open the dashcam app on your iOS device
2. Go to **Settings** (gear icon)
3. In the **Google Cloud Storage** section:
   - **Project ID**: Should show `my-dashcam-472908` (pre-configured)
   - **Bucket Name**: Enter your bucket name (e.g., `dashcam-storage-bucket`)
   - **Service Account**: Tap **Select Service Account Key**
   - Choose the JSON file you downloaded in Step 5
4. Tap **Save Cloud Settings**

## Step 7: Test Upload

1. Record a short test video
2. Check that the upload status shows activity
3. Verify in Google Cloud Console:
   - Go to your bucket
   - Look for files in `dashcam/YYYY/MM/DD/` folders

## Bucket Structure

Your videos will be organized as:
```
dashcam-storage-bucket/
└── dashcam/
    └── 2024/
        └── 12/
            └── 22/
                ├── dashcam_1703251200_seg0.mov
                ├── dashcam_1703251500_seg1.mov
                └── dashcam_1703251800_seg2.mov
```

## Cost Estimation

**Storage Costs** (US regions):
- Standard Storage: ~$0.02/GB/month
- For 8GB of videos: ~$0.16/month
- With 3-month retention: ~$0.48/month maximum

**Network Costs**:
- Upload to Cloud Storage: Free
- Download (if needed): ~$0.12/GB

**Operations**:
- Upload operations: $0.005 per 1,000 operations
- Delete operations: Free

## Security Best Practices

1. **Service Account Key**:
   - Store securely on device
   - Never share or commit to version control
   - Rotate periodically (every 90 days recommended)

2. **Bucket Permissions**:
   - Use uniform bucket-level access
   - Grant minimum required permissions
   - Monitor access logs

3. **Network**:
   - App uses HTTPS for all uploads
   - Consider VPN for additional security

## Troubleshooting

### Upload Failures
- Check internet connectivity
- Verify service account permissions
- Ensure bucket exists and is accessible
- Check Cloud Storage quotas

### Authentication Issues
- Re-download service account key
- Verify JSON file format
- Check service account has correct roles

### Storage Issues
- Monitor bucket storage usage
- Check lifecycle policies are working
- Verify automatic deletion of old files

## Monitoring

1. **Cloud Console Dashboard**:
   - Monitor storage usage
   - Track upload operations
   - View access logs

2. **App Status**:
   - Check upload queue in settings
   - Monitor network connectivity indicator
   - Review app logs for errors

## Support

- **Google Cloud Support**: [Google Cloud Support](https://cloud.google.com/support)
- **Documentation**: [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- **Pricing**: [Cloud Storage Pricing](https://cloud.google.com/storage/pricing)

---

**⚠️ Important Notes:**
- Keep your service account key secure
- Monitor your Google Cloud billing
- Test with small files first
- Consider data retention laws in your region