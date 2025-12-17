# Deploy Frontend Changes

## Changes Made

1. ✅ **Renamed Application**: "RDS Operations Dashboard" → "RDS Command Hub"
2. ✅ **Fixed Trigger Discovery Button**: Implemented actual API call to `/api/discovery/trigger`
3. ✅ **Fixed Refresh Button**: Already working, refreshes dashboard data

## What You Need to Deploy

The frontend code changes are in your local files but NOT deployed to AWS yet. You need to:

1. Build the React app
2. Upload to S3
3. Invalidate CloudFront cache

## Deployment Steps

### Option 1: Automated Script (Recommended)

```powershell
cd rds-operations-dashboard/frontend
npm run build
```

Then get your S3 bucket name and CloudFront distribution ID:

```powershell
# Get S3 bucket name
aws cloudformation describe-stacks --stack-name RDSDashboard-Frontend --query 'Stacks[0].Outputs[?OutputKey==`FrontendBucketName`].OutputValue' --output text

# Get CloudFront distribution ID
aws cloudformation describe-stacks --stack-name RDSDashboard-Frontend --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' --output text
```

Then deploy:

```powershell
# Replace with your actual bucket name
$bucketName = "YOUR_BUCKET_NAME"
$distributionId = "YOUR_DISTRIBUTION_ID"

# Upload to S3
aws s3 sync dist/ s3://$bucketName/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*"
```

### Option 2: Manual Steps

1. **Build the frontend**:
   ```powershell
   cd rds-operations-dashboard/frontend
   npm install  # If not already done
   npm run build
   ```

2. **Find your S3 bucket**:
   ```powershell
   aws s3 ls | Select-String "rds-dashboard-frontend"
   ```

3. **Upload files**:
   ```powershell
   aws s3 sync dist/ s3://YOUR-BUCKET-NAME/ --delete
   ```

4. **Find CloudFront distribution**:
   ```powershell
   aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`RDS Dashboard Frontend`].Id' --output text
   ```

5. **Invalidate cache**:
   ```powershell
   aws cloudfront create-invalidation --distribution-id YOUR-DIST-ID --paths "/*"
   ```

6. **Wait 2-3 minutes** for CloudFront invalidation to complete

7. **Test**: Visit your CloudFront URL and hard-refresh (Ctrl+F5)

## After Deployment

Once deployed, you'll see:

1. **Application Name**: "RDS Command Hub" in header and login page
2. **Trigger Discovery Button**: Click to manually trigger RDS discovery
3. **Refresh Button**: Click to refresh dashboard data from API

## About the "Missing" 2nd Account

You mentioned not seeing a 2nd account or 3rd RDS instance. Here's what's actually configured:

### Your Current Setup

**Account 876595225096** (Your actual account):
- ✅ `tb-pg-db1` (PostgreSQL 18.1) in ap-southeast-1 - STOPPED
- ✅ `database-1` (MySQL 8.0.43) in eu-west-2 - STOPPED

**Placeholder Accounts** (Not real, configured for testing):
- ❌ Account `123456789012` - AccessDenied (doesn't exist or no access)
- ❌ Account `234567890123` - AccessDenied (doesn't exist or no access)

### Why You Only See 2 Instances

Discovery is working correctly! You have:
- **1 AWS account** (876595225096)
- **2 RDS instances** in that account
- **2 regions** with instances (ap-southeast-1, eu-west-2)

The placeholder accounts (123456789012, 234567890123) are configured in your CDK but don't actually exist or aren't accessible, which is why discovery skips them.

### To Add Real Cross-Account Discovery

If you want to discover RDS instances from other AWS accounts:

1. **Get the account IDs** of the accounts you want to monitor
2. **Update CDK configuration**:
   ```typescript
   // In infrastructure/bin/app.ts
   const targetAccounts = [
     '876595225096',  // Your current account
     'REAL_ACCOUNT_ID_2',  // Replace with real account ID
     'REAL_ACCOUNT_ID_3',  // Replace with real account ID
   ];
   ```
3. **Deploy cross-account roles** in those accounts using `infrastructure/cross-account-role.yaml`
4. **Redeploy infrastructure**: `cdk deploy --all`

## Verification

After deployment, verify the changes:

```powershell
# Check if files are in S3
aws s3 ls s3://YOUR-BUCKET-NAME/ --recursive | Select-String "index.html"

# Check CloudFront invalidation status
aws cloudfront get-invalidation --distribution-id YOUR-DIST-ID --id INVALIDATION-ID
```

## Troubleshooting

### Buttons Still Not Working

1. **Hard refresh**: Press Ctrl+F5 in browser
2. **Clear browser cache**: Settings → Clear browsing data
3. **Check console**: F12 → Console tab for errors
4. **Verify deployment**: Check S3 bucket has latest files

### "Trigger Discovery" Returns Error

1. **Check permissions**: User must have `trigger_discovery` permission (DBA or Admin group)
2. **Check BFF**: Ensure BFF Lambda is running
3. **Check logs**: `aws logs tail /aws/lambda/rds-dashboard-bff --follow`

### No Instances Showing

1. **Trigger discovery manually**: Click "Trigger Discovery" button
2. **Wait 10 seconds**: Discovery takes a few seconds
3. **Click Refresh**: Refresh the dashboard data
4. **Check DynamoDB**: Verify instances are in `rds-inventory-prod` table

## Summary

- ✅ Application renamed to "RDS Command Hub"
- ✅ Trigger Discovery button implemented
- ✅ Refresh button working
- ⏳ **NEXT STEP**: Deploy frontend to see changes
- ℹ️ You have 2 RDS instances in 1 account (this is correct)
