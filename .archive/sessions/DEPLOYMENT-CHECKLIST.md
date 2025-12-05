# Deployment Checklist

Use this checklist to ensure a smooth deployment of the RDS Operations Dashboard.

## Pre-Deployment Checklist

### Local Environment Setup
- [ ] Git installed and configured
  ```powershell
  git --version
  git config --global user.name "Your Name"
  git config --global user.email "your@email.com"
  ```

- [ ] Node.js 18+ installed
  ```powershell
  node --version  # Should be v18.x or higher
  npm --version
  ```

- [ ] Python 3.11+ installed
  ```powershell
  python --version  # Should be 3.11.x or higher
  pip --version
  ```

- [ ] AWS CLI installed and configured
  ```powershell
  aws --version
  aws configure  # Enter your credentials
  aws sts get-caller-identity  # Verify access
  ```

- [ ] AWS CDK installed globally
  ```powershell
  npm install -g aws-cdk
  cdk --version  # Should be 2.x
  ```

### AWS Account Setup
- [ ] AWS account created
- [ ] IAM user created with admin permissions (don't use root!)
- [ ] Access key and secret key generated
- [ ] AWS CLI configured with credentials
- [ ] Account ID noted: `_________________`
- [ ] Region selected: `ap-southeast-1` (or your preferred region)

### GitHub Setup
- [ ] GitHub account created
- [ ] Repository created: `https://github.com/tb-repo/rds-operations-dashboard`
- [ ] Repository is accessible
- [ ] Personal Access Token generated (if needed)

## Deployment Steps

### Phase 1: Git and GitHub Setup (5 minutes)

- [ ] Navigate to project directory
  ```powershell
  cd rds-operations-dashboard
  ```

- [ ] Initialize Git (if needed)
  ```powershell
  git init
  ```

- [ ] Add remote repository
  ```powershell
  git remote add origin https://github.com/tb-repo/rds-operations-dashboard.git
  ```

- [ ] Create initial commit
  ```powershell
  git add .
  git commit -m "Initial commit: RDS Operations Dashboard"
  ```

- [ ] Push to GitHub
  ```powershell
  git push -u origin main
  ```

- [ ] Verify code is on GitHub (check repository in browser)

### Phase 2: AWS CDK Bootstrap (2 minutes)

- [ ] Get AWS Account ID
  ```powershell
  aws sts get-caller-identity --query Account --output text
  ```
  Account ID: `_________________`

- [ ] Bootstrap CDK
  ```powershell
  cd infrastructure
  cdk bootstrap aws://YOUR_ACCOUNT_ID/ap-southeast-1
  ```

- [ ] Verify bootstrap succeeded (check for success message)

### Phase 3: Install Dependencies (3 minutes)

- [ ] Install infrastructure dependencies
  ```powershell
  cd infrastructure
  npm install
  ```

- [ ] Install Lambda dependencies
  ```powershell
  cd ../lambda
  pip install -r requirements.txt -t .
  ```

- [ ] Install frontend dependencies
  ```powershell
  cd ../frontend
  npm install
  ```

- [ ] Verify all installations succeeded (no errors)

### Phase 4: Deploy Infrastructure (10-15 minutes)

- [ ] Navigate to infrastructure directory
  ```powershell
  cd ../infrastructure
  ```

- [ ] Synthesize CDK stacks
  ```powershell
  cdk synth --all
  ```

- [ ] Review synthesized templates (optional)
  ```powershell
  ls cdk.out/
  ```

- [ ] Deploy all stacks
  ```powershell
  cdk deploy --all --require-approval never
  ```

- [ ] Wait for deployment to complete (10-15 minutes)

- [ ] Verify all stacks deployed successfully

- [ ] Get API Gateway URL
  ```powershell
  aws cloudformation describe-stacks --stack-name RdsDashboard-API-Stack --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' --output text
  ```
  API URL: `_________________`

- [ ] Get API Key
  ```powershell
  aws cloudformation describe-stacks --stack-name RdsDashboard-API-Stack --query 'Stacks[0].Outputs[?OutputKey==`ApiKey`].OutputValue' --output text
  ```
  API Key: `_________________`

- [ ] Save these values securely!

### Phase 5: Deploy Frontend (5 minutes)

- [ ] Navigate to frontend directory
  ```powershell
  cd ../frontend
  ```

- [ ] Create .env file
  ```powershell
  cp .env.example .env
  ```

- [ ] Edit .env with API URL and Key
  ```
  VITE_API_BASE_URL=YOUR_API_URL
  VITE_API_KEY=YOUR_API_KEY
  ```

- [ ] Build frontend
  ```powershell
  npm run build
  ```

- [ ] Verify build succeeded (check dist/ directory)

- [ ] Create S3 bucket
  ```powershell
  aws s3 mb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --region ap-southeast-1
  ```

- [ ] Enable static website hosting
  ```powershell
  aws s3 website s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --index-document index.html
  ```

- [ ] Upload files to S3
  ```powershell
  aws s3 sync dist/ s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --delete
  ```

- [ ] Make bucket public
  ```powershell
  aws s3api put-bucket-policy --bucket rds-dashboard-frontend-YOUR_ACCOUNT_ID --policy file://bucket-policy.json
  ```

- [ ] Get website URL
  ```
  http://rds-dashboard-frontend-YOUR_ACCOUNT_ID.s3-website-ap-southeast-1.amazonaws.com
  ```
  Website URL: `_________________`

### Phase 6: GitHub Actions Setup (5 minutes)

- [ ] Go to GitHub repository → Settings → Secrets and variables → Actions

- [ ] Add secret: `AWS_ACCESS_KEY_ID`
  Value: `_________________`

- [ ] Add secret: `AWS_SECRET_ACCESS_KEY`
  Value: `_________________`

- [ ] Add secret: `AWS_REGION`
  Value: `ap-southeast-1`

- [ ] Add secret: `AWS_ACCOUNT_ID`
  Value: `_________________`

- [ ] Add secret: `VITE_API_BASE_URL` (optional, for frontend workflow)
  Value: `_________________`

- [ ] Add secret: `VITE_API_KEY` (optional, for frontend workflow)
  Value: `_________________`

- [ ] Verify all secrets are added

- [ ] Push a commit to trigger workflows
  ```powershell
  git add .
  git commit -m "Configure GitHub Actions"
  git push
  ```

- [ ] Go to Actions tab and verify workflows run successfully

## Post-Deployment Verification

### Test Infrastructure

- [ ] Create test RDS instance
  ```powershell
  aws rds create-db-instance \
    --db-instance-identifier test-dashboard \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username admin \
    --master-user-password TestPass123! \
    --allocated-storage 20 \
    --tags Key=Environment,Value=Development
  ```

- [ ] Wait 5-10 minutes for RDS instance to be available

- [ ] Manually trigger discovery Lambda
  ```powershell
  aws lambda invoke --function-name RdsDashboard-Discovery response.json
  cat response.json
  ```

- [ ] Verify instance appears in DynamoDB
  ```powershell
  aws dynamodb scan --table-name rds_inventory --max-items 5
  ```

### Test API Endpoints

- [ ] Test instances endpoint
  ```powershell
  curl -H "x-api-key: YOUR_API_KEY" "YOUR_API_URL/instances"
  ```

- [ ] Test health endpoint
  ```powershell
  curl -H "x-api-key: YOUR_API_KEY" "YOUR_API_URL/health"
  ```

- [ ] Test costs endpoint
  ```powershell
  curl -H "x-api-key: YOUR_API_KEY" "YOUR_API_URL/costs"
  ```

- [ ] Test compliance endpoint
  ```powershell
  curl -H "x-api-key: YOUR_API_KEY" "YOUR_API_URL/compliance"
  ```

- [ ] Verify all endpoints return valid JSON

### Test Frontend

- [ ] Open website URL in browser

- [ ] Verify dashboard loads without errors

- [ ] Check browser console for errors (F12)

- [ ] Verify summary cards show data

- [ ] Verify charts render correctly

- [ ] Navigate to Instances page

- [ ] Verify test RDS instance appears in list

- [ ] Click on instance to view details

- [ ] Verify instance detail page loads

- [ ] Navigate to Costs page

- [ ] Verify cost data displays

- [ ] Navigate to Compliance page

- [ ] Verify compliance checks display

- [ ] Test search and filter functionality

- [ ] Test refresh button

### Monitor CloudWatch

- [ ] Go to CloudWatch → Log groups

- [ ] Check logs for each Lambda function:
  - [ ] `/aws/lambda/RdsDashboard-Discovery`
  - [ ] `/aws/lambda/RdsDashboard-HealthMonitor`
  - [ ] `/aws/lambda/RdsDashboard-CostAnalyzer`
  - [ ] `/aws/lambda/RdsDashboard-ComplianceChecker`
  - [ ] `/aws/lambda/RdsDashboard-QueryHandler`

- [ ] Verify no errors in logs

- [ ] Go to CloudWatch → Dashboards

- [ ] Verify RDS Dashboard exists and shows metrics

## Security Hardening (Post-Deployment)

- [ ] Review IAM roles and policies (least privilege)

- [ ] Enable CloudTrail logging

- [ ] Set up AWS Config rules

- [ ] Enable GuardDuty (optional)

- [ ] Review S3 bucket policies

- [ ] Enable MFA for AWS account

- [ ] Rotate access keys regularly

- [ ] Consider replacing API key with Cognito

- [ ] Enable HTTPS for frontend (CloudFront)

- [ ] Review security group rules

## Cost Optimization

- [ ] Set up AWS Budget alerts
  ```powershell
  aws budgets create-budget --account-id YOUR_ACCOUNT_ID --budget file://budget.json
  ```

- [ ] Enable Cost Explorer

- [ ] Review and optimize Lambda memory settings

- [ ] Review DynamoDB capacity mode (on-demand vs provisioned)

- [ ] Set up S3 lifecycle policies

- [ ] Review CloudWatch Logs retention

- [ ] Delete test resources when not needed

## Documentation

- [ ] Document your specific configuration

- [ ] Update README with your details

- [ ] Create runbooks for common operations

- [ ] Document troubleshooting steps

- [ ] Share access with team members

## Ongoing Maintenance

- [ ] Set up monitoring alerts

- [ ] Schedule regular security reviews

- [ ] Plan for updates and patches

- [ ] Monitor costs weekly

- [ ] Review logs for errors

- [ ] Test disaster recovery procedures

## Cleanup (When Done Testing)

- [ ] Delete test RDS instance
  ```powershell
  aws rds delete-db-instance --db-instance-identifier test-dashboard --skip-final-snapshot
  ```

- [ ] Destroy CDK stacks
  ```powershell
  cd infrastructure
  cdk destroy --all
  ```

- [ ] Delete S3 buckets
  ```powershell
  aws s3 rm s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID --recursive
  aws s3 rb s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID
  ```

- [ ] Delete CloudWatch log groups (optional)

- [ ] Remove GitHub secrets (if decommissioning)

## Notes and Issues

Use this space to track any issues or notes during deployment:

```
Date: ___________
Issue: 
Resolution:

Date: ___________
Issue:
Resolution:
```

## Support

If you encounter issues:
1. Check `DEPLOYMENT-GUIDE.md` for detailed instructions
2. Review `TROUBLESHOOTING.md` for common issues
3. Check CloudWatch logs for errors
4. Review GitHub Actions logs
5. Create an issue in the GitHub repository

---

**Deployment Date:** ___________  
**Deployed By:** ___________  
**AWS Account ID:** ___________  
**Region:** ___________  
**Website URL:** ___________  
**API URL:** ___________
