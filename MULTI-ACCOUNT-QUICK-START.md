# Multi-Account Testing - Quick Start Guide

## TL;DR - Quick Setup

### Current Configuration
- **Enabled Regions**: 4 (Singapore, London, Mumbai, Virginia)
- **Enabled Accounts**: 2 (Production, Development)
- **VPC**: Default VPC works perfectly ✅

### 3-Step Setup

```powershell
# Step 1: Create AWS Organization and new account
.\scripts\setup-multi-account-test.ps1 `
  -CreateOrganization `
  -NewAccountEmail "rds-test@yourdomain.com"

# Step 2: Deploy cross-account role in new account
aws cloudformation create-stack \
  --stack-name RDSDashboard-CrossAccount \
  --template-body file://infrastructure/cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=876595225096 \
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1 \
  --profile <new-account-profile>

# Step 3: Create test RDS instances and run discovery
.\run-discovery.ps1
```

## Answers to Your Questions

### 1. Can I create AWS Organization?
**YES!** ✅ Highly recommended for testing.

**Benefits:**
- No credit card needed for member accounts
- Centralized billing
- Easy account management
- Automatic cross-account role creation

**Create Organization:**
```bash
aws organizations create-organization --feature-set ALL
```

### 2. Which regions are enabled?
Your dashboard currently scans **4 regions**:

| Region | Name | Priority | Status |
|--------|------|----------|--------|
| ap-southeast-1 | Singapore | 1 | ✅ Enabled |
| eu-west-2 | London | 2 | ✅ Enabled |
| ap-south-1 | Mumbai | 3 | ✅ Enabled |
| us-east-1 | N. Virginia | 4 | ✅ Enabled |

**To add more regions**, edit `config/dashboard-config.json`:
```json
{
  "region": "ap-northeast-1",
  "region_name": "Tokyo",
  "enabled": true,
  "priority": 5
}
```

### 3. Should I create VPC or use default?
**Use Default VPC for Testing** ✅

**Why default VPC is perfect:**
- Already configured with internet gateway
- Has subnets in each AZ
- Security groups pre-configured
- **The app works seamlessly with it**
- No additional setup needed

**For Production:**
- Create custom VPC with private subnets
- Use VPC endpoints for AWS services
- Implement proper security groups

### 4. Will the app work seamlessly?
**YES!** ✅ The app is designed for multi-account/multi-region.

**What works automatically:**
- Discovery across all enabled regions
- Discovery across all enabled accounts
- Cost tracking per account/region
- Compliance checks per account
- Operations (start/stop/reboot) across accounts

**What you need to ensure:**
- Cross-account role exists in each target account
- Role has correct trust policy and permissions
- Account IDs are in configuration

## Test RDS Instance Creation

### Quick Test (1 instance per region)

```bash
# Singapore
aws rds create-db-instance \
  --db-instance-identifier test-singapore \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password "Test123!" \
  --allocated-storage 20 \
  --region ap-southeast-1

# London
aws rds create-db-instance \
  --db-instance-identifier test-london \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --master-username admin \
  --master-user-password "Test123!" \
  --allocated-storage 20 \
  --region eu-west-2

# Mumbai
aws rds create-db-instance \
  --db-instance-identifier test-mumbai \
  --db-instance-class db.t4g.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password "Test123!" \
  --allocated-storage 20 \
  --region ap-south-1

# Virginia
aws rds create-db-instance \
  --db-instance-identifier test-virginia \
  --db-instance-class db.t4g.micro \
  --engine mariadb \
  --master-username admin \
  --master-user-password "Test123!" \
  --allocated-storage 20 \
  --region us-east-1
```

**Cost**: ~$50/month for 4 instances

## Verification

### 1. Check Cross-Account Access
```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::<NEW_ACCOUNT_ID>:role/RDSDashboardCrossAccountRole" \
  --role-session-name test \
  --external-id "rds-dashboard-unique-id-12345"
```

### 2. List RDS Instances
```bash
# In new account
aws rds describe-db-instances --region ap-southeast-1
```

### 3. Run Discovery
```powershell
.\run-discovery.ps1
```

### 4. Check Dashboard
- Open: https://d2iqvvvqxqvqxq.cloudfront.net
- Login with your credentials
- Verify instances from all regions appear
- Check account IDs are correct

## Troubleshooting

### Issue: Access Denied
**Solution**: Verify cross-account role exists and has correct trust policy

```bash
# Check role
aws iam get-role --role-name RDSDashboardCrossAccountRole

# Check trust policy
aws iam get-role \
  --role-name RDSDashboardCrossAccountRole \
  --query 'Role.AssumeRolePolicyDocument'
```

### Issue: No Instances Discovered
**Solution**: Check if instances are in enabled regions

```bash
# List all RDS instances
aws rds describe-db-instances --region ap-southeast-1

# Check discovery logs
aws logs tail /aws/lambda/rds-discovery --follow
```

### Issue: Wrong Account ID
**Solution**: Ensure `AWS_ACCOUNT_ID` environment variable is set in Lambda

```bash
aws lambda get-function-configuration \
  --function-name rds-discovery \
  --query 'Environment.Variables.AWS_ACCOUNT_ID'
```

## Cost Optimization

### Free Tier
- 750 hours/month of db.t2.micro (or db.t3.micro)
- 20 GB storage
- 20 GB backup storage

### Stop Instances When Not Testing
```bash
# Stop all test instances
aws rds stop-db-instance --db-instance-identifier test-singapore --region ap-southeast-1
aws rds stop-db-instance --db-instance-identifier test-london --region eu-west-2
aws rds stop-db-instance --db-instance-identifier test-mumbai --region ap-south-1
aws rds stop-db-instance --db-instance-identifier test-virginia --region us-east-1
```

**Savings**: ~70% cost reduction when stopped

### Delete After Testing
```bash
# Delete all test instances
aws rds delete-db-instance \
  --db-instance-identifier test-singapore \
  --skip-final-snapshot \
  --region ap-southeast-1
```

## Summary

✅ **Yes, create AWS Organization** - Best for testing
✅ **4 regions enabled** - Singapore, London, Mumbai, Virginia
✅ **Use default VPC** - Works perfectly for testing
✅ **App works seamlessly** - Designed for multi-account/multi-region

**Next Steps:**
1. Run setup script: `.\scripts\setup-multi-account-test.ps1`
2. Create test RDS instances
3. Run discovery: `.\run-discovery.ps1`
4. Verify in dashboard

**Need Help?**
- See: `docs/MULTI-ACCOUNT-TESTING-GUIDE.md` for detailed guide
- See: `docs/cross-account-setup.md` for cross-account configuration
- See: `NEW-ACCOUNT-CHECKLIST.md` for deployment checklist
