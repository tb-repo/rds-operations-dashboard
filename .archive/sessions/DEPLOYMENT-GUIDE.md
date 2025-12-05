# Complete Deployment Guide - RDS Operations Dashboard

**Last Updated:** 2025-11-15  
**Target:** Personal AWS Account + GitHub Repository  
**CI/CD:** GitHub Actions (Free)

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Part 1: Git Setup and GitHub Sync](#part-1-git-setup-and-github-sync)
3. [Part 2: AWS Account Setup](#part-2-aws-account-setup)
4. [Part 3: GitHub Actions CI/CD Setup](#part-3-github-actions-cicd-setup)
5. [Part 4: Deploy Infrastructure with CDK](#part-4-deploy-infrastructure-with-cdk)
6. [Part 5: Deploy Frontend](#part-5-deploy-frontend)
7. [Part 6: Testing and Verification](#part-6-testing-and-verification)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Software Requirements
- [x] Git installed (check: `git --version`)
- [x] Node.js 18+ installed (check: `node --version`)
- [x] Python 3.11+ installed (check: `python --version`)
- [x] AWS CLI installed (check: `aws --version`)
- [x] AWS CDK installed (check: `cdk --version`)

### Accounts Required
- [x] GitHub account with access to your repo
- [x] AWS account (root access)
- [x] GitHub Personal Access Token (for Actions)

---

## Part 1: Git Setup and GitHub Sync

### Step 1.1: Initialize Git Repository (if not already done)

```powershell
# Navigate to your project root
cd rds-operations-dashboard

# Check if git is already initialized
git status

# If not initialized, run:
git init
```

### Step 1.2: Create .gitignore File

Create a comprehensive `.gitignore` file:

```powershell
# Create .gitignore in project root
```

I'll create this file for you with proper exclusions.

### Step 1.3: Configure Git

```powershell
# Set your Git identity
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Verify configuration
git config --list
```

### Step 1.4: Add Remote Repository

```powershell
# Add your GitHub repository as remote
git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git

# Verify remote
git remote -v
```

### Step 1.5: Initial Commit and Push

```powershell
# Stage all files
git add .

# Create initial commit
git commit -m "Initial commit: RDS Operations Dashboard"

# Push to GitHub (main branch)
git branch -M main
git push -u origin main
```

**Note:** If the repository already has content, you may need to pull first:
```powershell
git pull origin main --allow-unrelated-histories
```

---

## Part 2: AWS Account Setup

### Step 2.1: Install and Configure AWS CLI

```powershell
# Install AWS CLI (if not installed)
# Download from: https://aws.amazon.com/cli/

# Configure AWS credentials
aws configure

# Enter when prompted:
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Key]
# Default region name: ap-southeast-1
# Default output format: json
```

### Step 2.2: Create IAM User for Deployment (Recommended)

**⚠️ IMPORTANT:** Don't use root credentials for deployment!

1. **Go to AWS Console → IAM → Users → Create User**
   - Username: `rds-dashboard-deployer`
   - Access type: Programmatic access

2. **Attach Policies:**
   - `AdministratorAccess` (for initial setup, restrict later)
   - Or create custom policy with these permissions:
     - CloudFormation (full)
     - Lambda (full)
     - DynamoDB (full)
     - S3 (full)
     - API Gateway (full)
     - CloudWatch (full)
     - IAM (limited to role creation)
     - EventBridge (full)

3. **Save Credentials:**
   - Access Key ID
   - Secret Access Key
   - Store these securely!

### Step 2.3: Configure AWS Profile

```powershell
# Configure a named profile for this project
aws configure --profile rds-dashboard

# Test the profile
aws sts get-caller-identity --profile rds-dashboard
```

### Step 2.4: Bootstrap AWS CDK

```powershell
# Bootstrap CDK in your AWS account (one-time setup)
cd infrastructure

# Install CDK globally if not installed
npm install -g aws-cdk

# Bootstrap CDK
cdk bootstrap aws://YOUR_ACCOUNT_ID/ap-southeast-1 --profile rds-dashboard

# Replace YOUR_ACCOUNT_ID with your actual AWS account ID
# Get it with: aws sts get-caller-identity --profile rds-dashboard --query Account --output text
```

---

## Part 3: GitHub Actions CI/CD Setup

### Step 3.1: Create GitHub Secrets

1. **Go to GitHub Repository → Settings → Secrets and variables → Actions**

2. **Add the following secrets:**
   - `AWS_ACCESS_KEY_ID`: Your IAM user access key
   - `AWS_SECRET_ACCESS_KEY`: Your IAM user secret key
   - `AWS_REGION`: `ap-southeast-1`
   - `AWS_ACCOUNT_ID`: Your AWS account ID

### Step 3.2: Create GitHub Actions Workflow

I'll create the workflow files for you in `.github/workflows/`

### Step 3.3: Enable GitHub Actions

1. Go to **Repository → Actions**
2. Enable workflows if prompted
3. Workflows will trigger on push to `main` branch

---

## Part 4: Deploy Infrastructure with CDK

### Step 4.1: Install Dependencies

```powershell
# Navigate to infrastructure directory
cd infrastructure

# Install Node.js dependencies
npm install

# Install Python dependencies for Lambda functions
cd ../lambda
pip install -r requirements.txt -t .
cd ../infrastructure
```

### Step 4.2: Configure Environment Variables

Create `infrastructure/.env` file:

```env
AWS_ACCOUNT_ID=123456789012
AWS_REGION=ap-southeast-1
ENVIRONMENT=dev
SNS_EMAIL=your-email@example.com
```

### Step 4.3: Review CDK Stacks

```powershell
# List all stacks
cdk list --profile rds-dashboard

# Expected output:
# RdsDashboard-IAM-Stack
# RdsDashboard-Data-Stack
# RdsDashboard-Compute-Stack
# RdsDashboard-API-Stack
# RdsDashboard-Orchestration-Stack
# RdsDashboard-Monitoring-Stack
```

### Step 4.4: Synthesize CloudFormation Templates

```powershell
# Generate CloudFormation templates
cdk synth --profile rds-dashboard

# Review the generated templates in cdk.out/
```

### Step 4.5: Deploy Stacks (Manual First Time)

```powershell
# Deploy all stacks in order
cdk deploy --all --profile rds-dashboard --require-approval never

# Or deploy one by one:
cdk deploy RdsDashboard-IAM-Stack --profile rds-dashboard
cdk deploy RdsDashboard-Data-Stack --profile rds-dashboard
cdk deploy RdsDashboard-Compute-Stack --profile rds-dashboard
cdk deploy RdsDashboard-API-Stack --profile rds-dashboard
cdk deploy RdsDashboard-Orchestration-Stack --profile rds-dashboard
cdk deploy RdsDashboard-Monitoring-Stack --profile rds-dashboard
```

**Expected Duration:** 10-15 minutes

### Step 4.6: Save Stack Outputs

After deployment, save these outputs:
```powershell
# Get API Gateway URL
aws cloudformation describe-stacks \
  --stack-name RdsDashboard-API-Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
  --output text \
  --profile rds-dashboard

# Get API Key
aws cloudformation describe-stacks \
  --stack-name RdsDashboard-API-Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiKey`].OutputValue' \
  --output text \
  --profile rds-dashboard

# Get S3 Bucket Name
aws cloudformation describe-stacks \
  --stack-name RdsDashboard-Data-Stack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text \
  --profile rds-dashboard
```

---

## Part 5: Deploy Frontend

### Step 5.1: Configure Frontend Environment

```powershell
cd frontend

# Create .env file
cp .env.example .env

# Edit .env with your API Gateway details
# VITE_API_BASE_URL=https://xxxxx.execute-api.ap-southeast-1.amazonaws.com/prod
# VITE_API_KEY=your-api-key-from-step-4.6
```

### Step 5.2: Install Frontend Dependencies

```powershell
npm install
```

### Step 5.3: Test Frontend Locally

```powershell
# Start development server
npm run dev

# Open browser to http://localhost:3000
# Verify API connection works
```

### Step 5.4: Build Frontend for Production

```powershell
# Build production bundle
npm run build

# Output will be in dist/ directory
```

### Step 5.5: Deploy Frontend to S3

**Option A: Manual Deployment**

```powershell
# Create S3 bucket for frontend
aws s3 mb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --region ap-southeast-1 --profile rds-dashboard

# Enable static website hosting
aws s3 website s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID \
  --index-document index.html \
  --error-document index.html \
  --profile rds-dashboard

# Upload build files
aws s3 sync dist/ s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --delete --profile rds-dashboard

# Make bucket public (for testing)
aws s3api put-bucket-policy \
  --bucket rds-dashboard-frontend-YOUR_ACCOUNT_ID \
  --policy file://bucket-policy.json \
  --profile rds-dashboard
```

**Option B: CDK Deployment (Recommended)**

I'll create a frontend stack for you.

### Step 5.6: Access Frontend

```powershell
# Get website URL
aws s3api get-bucket-website \
  --bucket rds-dashboard-frontend-YOUR_ACCOUNT_ID \
  --profile rds-dashboard

# URL format: http://rds-dashboard-frontend-YOUR_ACCOUNT_ID.s3-website-ap-southeast-1.amazonaws.com
```

---

## Part 6: Testing and Verification

### Step 6.1: Create Test RDS Instance

```powershell
# Create a small test RDS instance
aws rds create-db-instance \
  --db-instance-identifier test-rds-dashboard \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username testadmin \
  --master-user-password TestPassword123! \
  --allocated-storage 20 \
  --backup-retention-period 7 \
  --tags Key=Environment,Value=Development Key=Application,Value=TestApp \
  --profile rds-dashboard
```

### Step 6.2: Trigger Discovery Lambda

```powershell
# Manually invoke discovery Lambda
aws lambda invoke \
  --function-name RdsDashboard-Discovery \
  --profile rds-dashboard \
  response.json

# Check response
cat response.json
```

### Step 6.3: Verify Data in DynamoDB

```powershell
# Check rds_inventory table
aws dynamodb scan \
  --table-name rds_inventory \
  --profile rds-dashboard \
  --max-items 5
```

### Step 6.4: Test API Endpoints

```powershell
# Get API URL and Key from Step 4.6
$API_URL = "https://xxxxx.execute-api.ap-southeast-1.amazonaws.com/prod"
$API_KEY = "your-api-key"

# Test instances endpoint
curl -H "x-api-key: $API_KEY" "$API_URL/instances"

# Test health endpoint
curl -H "x-api-key: $API_KEY" "$API_URL/health"

# Test costs endpoint
curl -H "x-api-key: $API_KEY" "$API_URL/costs"
```

### Step 6.5: Test Frontend Dashboard

1. Open frontend URL in browser
2. Verify dashboard loads
3. Check that test RDS instance appears
4. Verify charts render correctly
5. Test filtering and search
6. Test instance detail page

### Step 6.6: Monitor CloudWatch Logs

```powershell
# View discovery Lambda logs
aws logs tail /aws/lambda/RdsDashboard-Discovery --follow --profile rds-dashboard

# View health monitor logs
aws logs tail /aws/lambda/RdsDashboard-HealthMonitor --follow --profile rds-dashboard
```

---

## Troubleshooting

### Issue: CDK Bootstrap Fails

**Solution:**
```powershell
# Ensure you have admin permissions
aws sts get-caller-identity --profile rds-dashboard

# Try with explicit trust
cdk bootstrap --trust YOUR_ACCOUNT_ID --profile rds-dashboard
```

### Issue: Lambda Functions Not Deploying

**Solution:**
```powershell
# Check Lambda package size
cd lambda
du -sh *

# If too large, remove unnecessary files
# Ensure requirements.txt only has needed packages
```

### Issue: API Gateway Returns 403

**Solution:**
- Verify API key is correct
- Check CORS configuration in API Gateway
- Verify Lambda has correct permissions

### Issue: Frontend Can't Connect to API

**Solution:**
- Check `.env` file has correct API URL and key
- Verify CORS is enabled on API Gateway
- Check browser console for errors
- Test API directly with curl first

### Issue: No RDS Instances Showing

**Solution:**
```powershell
# Manually trigger discovery
aws lambda invoke \
  --function-name RdsDashboard-Discovery \
  --profile rds-dashboard \
  response.json

# Check DynamoDB
aws dynamodb scan --table-name rds_inventory --profile rds-dashboard

# Check CloudWatch logs for errors
aws logs tail /aws/lambda/RdsDashboard-Discovery --profile rds-dashboard
```

### Issue: GitHub Actions Failing

**Solution:**
- Verify all secrets are set correctly
- Check AWS credentials have necessary permissions
- Review workflow logs in GitHub Actions tab
- Ensure CDK is bootstrapped in target account

---

## Cost Optimization Tips

1. **Use AWS Free Tier:**
   - Lambda: 1M requests/month free
   - DynamoDB: 25GB storage free
   - CloudWatch: 10 custom metrics free
   - S3: 5GB storage free

2. **Set Budget Alerts:**
```powershell
aws budgets create-budget \
  --account-id YOUR_ACCOUNT_ID \
  --budget file://budget.json \
  --profile rds-dashboard
```

3. **Enable Cost Explorer:**
   - Go to AWS Console → Cost Management → Cost Explorer
   - Enable and review daily costs

4. **Clean Up Test Resources:**
```powershell
# Delete test RDS instance when done
aws rds delete-db-instance \
  --db-instance-identifier test-rds-dashboard \
  --skip-final-snapshot \
  --profile rds-dashboard
```

---

## Next Steps After Deployment

1. **Set Up Cross-Account Access:**
   - Follow `docs/cross-account-setup.md`
   - Deploy cross-account roles in target accounts

2. **Configure Monitoring:**
   - Set up SNS email subscriptions
   - Configure CloudWatch alarms
   - Review monitoring dashboard

3. **Security Hardening:**
   - Replace API key with Cognito authentication
   - Restrict S3 bucket access
   - Enable CloudTrail logging
   - Review IAM policies (least privilege)

4. **Performance Testing:**
   - Run load tests on API
   - Monitor Lambda cold starts
   - Optimize DynamoDB queries

5. **Documentation:**
   - Document your specific configuration
   - Create runbooks for common operations
   - Train team members

---

## Support and Resources

- **AWS Documentation:** https://docs.aws.amazon.com/
- **CDK Documentation:** https://docs.aws.amazon.com/cdk/
- **GitHub Actions:** https://docs.github.com/actions
- **Project Issues:** https://github.com/tb-repo/rds-operations-dashboard/issues

---

## Cleanup (When Done Testing)

```powershell
# Destroy all CDK stacks
cdk destroy --all --profile rds-dashboard

# Delete S3 buckets (must be empty first)
aws s3 rm s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --recursive --profile rds-dashboard
aws s3 rb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --profile rds-dashboard

# Delete test RDS instances
aws rds delete-db-instance \
  --db-instance-identifier test-rds-dashboard \
  --skip-final-snapshot \
  --profile rds-dashboard
```

---

**Good luck with your deployment! 🚀**
