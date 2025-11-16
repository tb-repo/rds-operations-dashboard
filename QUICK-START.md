# Quick Start Guide - 15 Minutes to Deployment

This guide will get your RDS Operations Dashboard deployed to AWS in ~15 minutes.

## Prerequisites Checklist

- [ ] Git installed
- [ ] Node.js 18+ installed
- [ ] Python 3.11+ installed
- [ ] AWS CLI installed and configured
- [ ] AWS CDK installed (`npm install -g aws-cdk`)
- [ ] GitHub account with repo access
- [ ] AWS account with admin access

## Step 1: Git Setup (2 minutes)

```powershell
# Navigate to project
cd rds-operations-dashboard

# Initialize git (if needed)
git init

# Configure git
git config user.name "Your Name"
git config user.email "your.email@example.com"

# Add remote
git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git

# Initial commit
git add .
git commit -m "Initial commit: RDS Operations Dashboard"
git push -u origin main
```

## Step 2: AWS Setup (3 minutes)

```powershell
# Configure AWS CLI
aws configure
# Enter: Access Key, Secret Key, Region (ap-southeast-1), Format (json)

# Get your AWS Account ID
aws sts get-caller-identity --query Account --output text

# Bootstrap CDK (replace YOUR_ACCOUNT_ID)
cd infrastructure
cdk bootstrap aws://YOUR_ACCOUNT_ID/ap-southeast-1
```

## Step 3: Deploy Infrastructure (8 minutes)

```powershell
# Install dependencies
npm install

# Install Python dependencies
cd ../lambda
pip install -r requirements.txt -t .
cd ../infrastructure

# Deploy all stacks
cdk deploy --all --require-approval never

# Save the outputs (API URL and API Key)
```

## Step 4: Deploy Frontend (2 minutes)

```powershell
cd ../frontend

# Install dependencies
npm install

# Create .env file
echo "VITE_API_BASE_URL=YOUR_API_URL_FROM_STEP_3" > .env
echo "VITE_API_KEY=YOUR_API_KEY_FROM_STEP_3" >> .env

# Build
npm run build

# Deploy to S3
aws s3 mb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --region ap-southeast-1
aws s3 website s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --index-document index.html
aws s3 sync dist/ s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --delete

# Make public
aws s3api put-bucket-policy --bucket rds-dashboard-frontend-YOUR_ACCOUNT_ID --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::rds-dashboard-frontend-YOUR_ACCOUNT_ID/*"
  }]
}'
```

## Step 5: Test (1 minute)

```powershell
# Open frontend URL
# http://rds-dashboard-frontend-YOUR_ACCOUNT_ID.s3-website-ap-southeast-1.amazonaws.com

# Create test RDS instance
aws rds create-db-instance \
  --db-instance-identifier test-dashboard \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password TestPass123! \
  --allocated-storage 20

# Wait 5 minutes, then check dashboard
```

## Step 6: Setup GitHub Actions (Optional)

1. Go to GitHub repo → Settings → Secrets
2. Add secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` = `ap-southeast-1`
   - `AWS_ACCOUNT_ID`
3. Push code to trigger deployment

## Done! 🎉

Your dashboard is now live at:
`http://rds-dashboard-frontend-YOUR_ACCOUNT_ID.s3-website-ap-southeast-1.amazonaws.com`

## Next Steps

- Review `DEPLOYMENT-GUIDE.md` for detailed instructions
- Set up cross-account access for multiple AWS accounts
- Configure monitoring and alerts
- Add authentication (Cognito)

## Troubleshooting

**CDK Deploy Fails:**
```powershell
# Check AWS credentials
aws sts get-caller-identity

# Ensure CDK is bootstrapped
cdk bootstrap
```

**Frontend Shows Errors:**
- Verify `.env` has correct API URL and key
- Check browser console for CORS errors
- Test API directly: `curl -H "x-api-key: YOUR_KEY" YOUR_API_URL/instances`

**No Instances Showing:**
```powershell
# Manually trigger discovery
aws lambda invoke --function-name RdsDashboard-Discovery response.json
cat response.json
```

## Cleanup

```powershell
# Destroy everything
cdk destroy --all
aws s3 rm s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --recursive
aws s3 rb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID
aws rds delete-db-instance --db-instance-identifier test-dashboard --skip-final-snapshot
```
