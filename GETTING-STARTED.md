# Getting Started - Your Complete Guide

Welcome! This guide will help you deploy the RDS Operations Dashboard to your AWS account and set up automated deployments via GitHub Actions.

## 📋 What You'll Need

- **GitHub Account**: Your personal repo at `https://github.com/tb-repo/rds-operations-dashboard`
- **AWS Account**: Fresh AWS account with root access
- **15-30 minutes**: For initial setup and deployment

## 🚀 Three Ways to Deploy

### Option 1: Automated Script (Easiest - 15 minutes)

Perfect for quick deployment with minimal manual steps.

```powershell
# Run the automated setup script
.\setup.ps1 -AwsAccountId YOUR_ACCOUNT_ID -AwsRegion ap-southeast-1
```

This script will:
- ✅ Check prerequisites
- ✅ Configure Git
- ✅ Bootstrap AWS CDK
- ✅ Install all dependencies
- ✅ Deploy infrastructure
- ✅ Deploy frontend
- ✅ Provide you with URLs

**Follow this guide:** `QUICK-START.md`

### Option 2: Step-by-Step Manual (Recommended - 30 minutes)

Best for understanding each step and customizing your deployment.

**Follow this guide:** `DEPLOYMENT-GUIDE.md`

This comprehensive guide covers:
1. Git setup and GitHub sync
2. AWS account configuration
3. GitHub Actions CI/CD setup
4. Infrastructure deployment with CDK
5. Frontend deployment to S3
6. Testing and verification
7. Troubleshooting

### Option 3: GitHub Actions Only (Advanced)

For automated deployments on every push to main branch.

**Follow this guide:** `DEPLOYMENT-GUIDE.md` → Part 3

## 📚 Documentation Structure

```
rds-operations-dashboard/
├── GETTING-STARTED.md          ← You are here! Start here
├── QUICK-START.md              ← 15-minute quick deployment
├── DEPLOYMENT-GUIDE.md         ← Comprehensive step-by-step guide
├── DEPLOYMENT-CHECKLIST.md     ← Printable checklist
├── setup.ps1                   ← Automated setup script
├── README.md                   ← Project overview
├── TASK-10-SUMMARY.md          ← Frontend implementation details
└── docs/
    ├── deployment.md           ← Deployment scenarios
    ├── cross-account-setup.md  ← Multi-account configuration
    └── api-documentation.md    ← API reference
```

## 🎯 Recommended Path for Beginners

1. **Read this file** (you're doing it! ✅)
2. **Check prerequisites** below
3. **Follow QUICK-START.md** for fastest deployment
4. **Use DEPLOYMENT-CHECKLIST.md** to track progress
5. **Refer to DEPLOYMENT-GUIDE.md** if you need details

## ✅ Prerequisites Check

Before starting, ensure you have:

### Software Installed

```powershell
# Check Git
git --version
# Expected: git version 2.x.x

# Check Node.js
node --version
# Expected: v18.x.x or higher

# Check Python
python --version
# Expected: Python 3.11.x or higher

# Check AWS CLI
aws --version
# Expected: aws-cli/2.x.x

# Check AWS CDK
cdk --version
# Expected: 2.x.x
```

### If Missing, Install:

**Git:** https://git-scm.com/downloads  
**Node.js:** https://nodejs.org/ (LTS version)  
**Python:** https://www.python.org/downloads/  
**AWS CLI:** https://aws.amazon.com/cli/  
**AWS CDK:** `npm install -g aws-cdk`

### AWS Account Setup

1. **Create AWS Account** (if you haven't)
   - Go to https://aws.amazon.com/
   - Click "Create an AWS Account"
   - Follow the signup process

2. **Create IAM User** (Don't use root!)
   - Go to AWS Console → IAM → Users
   - Create user: `rds-dashboard-deployer`
   - Attach policy: `AdministratorAccess` (for initial setup)
   - Generate access key and secret key
   - **Save these credentials securely!**

3. **Configure AWS CLI**
   ```powershell
   aws configure
   # Enter: Access Key ID
   # Enter: Secret Access Key
   # Enter: Default region (ap-southeast-1)
   # Enter: Default output format (json)
   ```

4. **Verify Access**
   ```powershell
   aws sts get-caller-identity
   # Should show your account ID and user ARN
   ```

### GitHub Setup

1. **Verify Repository Access**
   - Go to https://github.com/tb-repo/rds-operations-dashboard
   - Ensure you can view and push to the repo

2. **Generate Personal Access Token** (if needed)
   - GitHub → Settings → Developer settings → Personal access tokens
   - Generate new token with `repo` scope
   - Save the token securely

## 🏃 Quick Start (Choose Your Path)

### Path A: I Want It Running NOW! (15 min)

```powershell
# 1. Get your AWS Account ID
aws sts get-caller-identity --query Account --output text

# 2. Run automated setup
cd rds-operations-dashboard
.\setup.ps1 -AwsAccountId YOUR_ACCOUNT_ID

# 3. Wait for completion and open the provided URL
```

### Path B: I Want to Understand Each Step (30 min)

1. Open `DEPLOYMENT-GUIDE.md`
2. Follow Part 1: Git Setup (5 min)
3. Follow Part 2: AWS Setup (5 min)
4. Follow Part 4: Deploy Infrastructure (10 min)
5. Follow Part 5: Deploy Frontend (5 min)
6. Follow Part 6: Testing (5 min)

### Path C: I Want Automated CI/CD (45 min)

1. Complete Path B first
2. Open `DEPLOYMENT-GUIDE.md` → Part 3
3. Set up GitHub Actions secrets
4. Push code to trigger automated deployment

## 🎓 What You'll Get

After deployment, you'll have:

### Infrastructure (AWS)
- ✅ Lambda functions for RDS discovery, health monitoring, cost analysis
- ✅ DynamoDB tables for data storage
- ✅ API Gateway for REST API
- ✅ S3 bucket for reports and frontend
- ✅ CloudWatch monitoring and alarms
- ✅ EventBridge rules for automation

### Frontend (React Dashboard)
- ✅ Dashboard overview with charts
- ✅ Instance list with search and filters
- ✅ Instance detail with performance metrics
- ✅ Cost analysis with recommendations
- ✅ Compliance dashboard with violations

### CI/CD (GitHub Actions)
- ✅ Automated infrastructure deployment
- ✅ Automated frontend deployment
- ✅ Automated testing on pull requests

## 💰 Cost Estimate

**Expected Monthly Cost: $2-10**

Breakdown:
- Lambda: Free tier (1M requests/month)
- DynamoDB: Free tier (25GB storage)
- API Gateway: ~$3.50 per million requests
- S3: ~$0.50 (1GB storage)
- CloudWatch: Free tier (10 metrics)
- Data Transfer: ~$0.50

**Tips to Stay in Free Tier:**
- Use on-demand DynamoDB
- Keep Lambda memory at 256MB
- Delete test RDS instances when not needed
- Set up budget alerts

## 🆘 Need Help?

### Common Issues

**"CDK bootstrap failed"**
→ Check AWS credentials: `aws sts get-caller-identity`

**"npm install failed"**
→ Update Node.js to v18+: `node --version`

**"Frontend shows errors"**
→ Check `.env` file has correct API URL and key

**"No instances showing"**
→ Create a test RDS instance and wait 5 minutes

### Where to Get Help

1. **Check Troubleshooting Section**
   - `DEPLOYMENT-GUIDE.md` → Troubleshooting

2. **Review Logs**
   ```powershell
   # Check Lambda logs
   aws logs tail /aws/lambda/RdsDashboard-Discovery --follow
   ```

3. **Check GitHub Actions**
   - Go to repository → Actions tab
   - Review workflow logs

4. **Create an Issue**
   - https://github.com/tb-repo/rds-operations-dashboard/issues

## 📖 Next Steps After Deployment

1. **Create Test RDS Instance**
   ```powershell
   aws rds create-db-instance \
     --db-instance-identifier test-dashboard \
     --db-instance-class db.t3.micro \
     --engine postgres \
     --master-username admin \
     --master-user-password TestPass123! \
     --allocated-storage 20
   ```

2. **Wait 5-10 Minutes**
   - RDS instance needs time to provision

3. **Open Dashboard**
   - Go to your frontend URL
   - Verify instance appears

4. **Explore Features**
   - View instance details
   - Check cost analysis
   - Review compliance status

5. **Set Up Monitoring**
   - Configure SNS email alerts
   - Review CloudWatch dashboard

6. **Add More Accounts** (Optional)
   - Follow `docs/cross-account-setup.md`
   - Deploy cross-account roles

## 🔒 Security Best Practices

Before going to production:

- [ ] Replace API key with AWS Cognito authentication
- [ ] Enable HTTPS for frontend (use CloudFront)
- [ ] Restrict S3 bucket access
- [ ] Enable CloudTrail logging
- [ ] Review IAM policies (least privilege)
- [ ] Enable MFA on AWS account
- [ ] Rotate access keys regularly
- [ ] Set up AWS Config rules

## 🧹 Cleanup (When Done Testing)

```powershell
# Delete test RDS instance
aws rds delete-db-instance --db-instance-identifier test-dashboard --skip-final-snapshot

# Destroy all infrastructure
cd infrastructure
cdk destroy --all

# Delete S3 buckets
aws s3 rm s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --recursive
aws s3 rb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID
```

## 🎉 Ready to Start?

Choose your path:

1. **Quick & Easy**: Open `QUICK-START.md` and run `setup.ps1`
2. **Step-by-Step**: Open `DEPLOYMENT-GUIDE.md` and follow along
3. **Checklist**: Print `DEPLOYMENT-CHECKLIST.md` and check off items

**Good luck! You've got this! 🚀**

---

**Questions?** Create an issue on GitHub  
**Found a bug?** Submit a pull request  
**Want to contribute?** Check CONTRIBUTING.md (if available)
