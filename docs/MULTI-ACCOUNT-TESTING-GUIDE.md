# Multi-Account and Multi-Region Testing Guide

## Current Configuration

Your dashboard is currently configured to discover RDS instances across:

### Enabled Regions (4 regions)
1. **ap-southeast-1** (Singapore) - Priority 1
2. **eu-west-2** (London) - Priority 2
3. **ap-south-1** (Mumbai) - Priority 3
4. **us-east-1** (N. Virginia) - Priority 4

### Target Accounts (2 enabled)
1. **123456789012** (Production) - ✅ Enabled
2. **234567890123** (Development) - ✅ Enabled
3. **345678901234** (Staging) - ❌ Disabled

## AWS Organizations Setup

### Yes, You Can Create AWS Organizations!

Creating an AWS Organization is the **recommended approach** for testing multi-account functionality. Here's why:

**Benefits:**
- Centralized billing and management
- Easy account creation (no credit card needed for member accounts)
- Consolidated CloudTrail and Config
- Service Control Policies (SCPs) for governance
- Cost allocation tags across accounts

**Steps to Create AWS Organization:**

```bash
# 1. Enable AWS Organizations in your management account
aws organizations create-organization --feature-set ALL

# 2. Create a new member account
aws organizations create-account \
  --email "rds-dashboard-test@yourdomain.com" \
  --account-name "RDS-Dashboard-Test" \
  --role-name "OrganizationAccountAccessRole"

# 3. Check account creation status
aws organizations describe-create-account-status \
  --create-account-request-id <request-id>

# 4. Once created, get the account ID
aws organizations list-accounts
```

## Setting Up Cross-Account Access

### Option 1: Using AWS Organizations (Recommended)

When you create an account via Organizations, it automatically creates an `OrganizationAccountAccessRole` that you can use.

**In the NEW account:**

```bash
# Switch to the new account
aws sts assume-role \
  --role-arn "arn:aws:iam::<NEW_ACCOUNT_ID>:role/OrganizationAccountAccessRole" \
  --role-session-name "setup-cross-account"

# Create the cross-account role
aws cloudformation create-stack \
  --stack-name RDSDashboard-CrossAccount \
  --template-body file://cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=876595225096 \
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 \
  --capabilities CAPABILITY_NAMED_IAM
```

### Option 2: Manual Setup (Without Organizations)

If you prefer not to use Organizations, you can create a standalone AWS account and set up cross-account access manually.

## VPC Configuration for Testing

### Should You Create a VPC or Use Default?

**For Testing: Use Default VPC** ✅

The default VPC is perfect for testing because:
- Already configured with internet gateway
- Has default subnets in each AZ
- Security groups are pre-configured
- No additional networking setup needed
- **The dashboard will work seamlessly with default VPC**

**For Production: Create Custom VPC** 🏗️

For production, you should create a custom VPC with:
- Private subnets for RDS instances
- Public subnets for NAT gateways
- VPC endpoints for AWS services
- Proper security group rules

### Creating Test RDS Instances

Here's a script to create test RDS instances in multiple regions:

```bash
# Create test RDS instance in ap-southeast-1
aws rds create-db-instance \
  --db-instance-identifier test-rds-singapore \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --master-username testadmin \
  --master-user-password "TestPassword123!" \
  --allocated-storage 20 \
  --region ap-southeast-1 \
  --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard

# Create test RDS instance in eu-west-2
aws rds create-db-instance \
  --db-instance-identifier test-rds-london \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --master-username testadmin \
  --master-user-password "TestPassword123!" \
  --allocated-storage 20 \
  --region eu-west-2 \
  --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard

# Create test RDS instance in ap-south-1
aws rds create-db-instance \
  --db-instance-identifier test-rds-mumbai \
  --db-instance-class db.t4g.micro \
  --engine mysql \
  --master-username testadmin \
  --master-user-password "TestPassword123!" \
  --allocated-storage 20 \
  --region ap-south-1 \
  --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard

# Create test RDS instance in us-east-1
aws rds create-db-instance \
  --db-instance-identifier test-rds-virginia \
  --db-instance-class db.t4g.micro \
  --engine mariadb \
  --master-username testadmin \
  --master-user-password "TestPassword123!" \
  --allocated-storage 20 \
  --region us-east-1 \
  --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard
```

## Complete Setup Script

I'll create a comprehensive setup script for you:

```powershell
# setup-multi-account-test.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$NewAccountId,
    
    [Parameter(Mandatory=$false)]
    [string]$NewAccountEmail = "rds-test@yourdomain.com"
)

Write-Host "Setting up multi-account testing for RDS Dashboard..." -ForegroundColor Cyan

# Step 1: Update configuration
Write-Host "`n1. Updating dashboard configuration..." -ForegroundColor Yellow
$config = Get-Content "config/dashboard-config.json" | ConvertFrom-Json
$config.cross_account.target_accounts += @{
    account_id = $NewAccountId
    account_name = "Test-Account"
    enabled = $true
}
$config | ConvertTo-Json -Depth 10 | Set-Content "config/dashboard-config.json"

# Step 2: Create cross-account role in new account
Write-Host "`n2. Creating cross-account role in new account..." -ForegroundColor Yellow
Write-Host "Please run this command in the NEW account:" -ForegroundColor Cyan
Write-Host @"
aws cloudformation create-stack \
  --stack-name RDSDashboard-CrossAccount \
  --template-body file://infrastructure/cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=876595225096 \
    ParameterKey=ExternalId,ParameterValue=rds-dashboard-unique-id-12345 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1
"@

# Step 3: Create test RDS instances
Write-Host "`n3. Creating test RDS instances in multiple regions..." -ForegroundColor Yellow
$regions = @("ap-southeast-1", "eu-west-2", "ap-south-1", "us-east-1")

foreach ($region in $regions) {
    Write-Host "Creating test instance in $region..." -ForegroundColor Gray
    $instanceName = "test-rds-$region"
    
    # Note: Run this in the NEW account
    Write-Host "aws rds create-db-instance --db-instance-identifier $instanceName --db-instance-class db.t4g.micro --engine postgres --master-username testadmin --master-user-password 'TestPassword123!' --allocated-storage 20 --region $region --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard"
}

# Step 4: Trigger discovery
Write-Host "`n4. Triggering discovery..." -ForegroundColor Yellow
Write-Host "Run this after RDS instances are created (takes ~10 minutes):"
Write-Host ".\run-discovery.ps1"

Write-Host "`nSetup complete! Next steps:" -ForegroundColor Green
Write-Host "1. Wait for RDS instances to be available (~10 minutes)"
Write-Host "2. Run discovery: .\run-discovery.ps1"
Write-Host "3. Check dashboard for instances from all regions and accounts"
}
```

## Testing Checklist

### Pre-Testing
- [ ] AWS Organization created (optional but recommended)
- [ ] New test account created
- [ ] Cross-account role deployed in new account
- [ ] Configuration updated with new account ID

### Region Testing
- [ ] Create RDS instance in ap-southeast-1 (Singapore)
- [ ] Create RDS instance in eu-west-2 (London)
- [ ] Create RDS instance in ap-south-1 (Mumbai)
- [ ] Create RDS instance in us-east-1 (N. Virginia)

### Discovery Testing
- [ ] Run discovery manually
- [ ] Verify all regions are scanned
- [ ] Verify all accounts are scanned
- [ ] Check for any access errors in logs

### Dashboard Verification
- [ ] All instances appear in dashboard
- [ ] Correct account ID displayed
- [ ] Correct region displayed
- [ ] Environment classification works
- [ ] Cost data available for all instances
- [ ] Compliance checks run for all instances

## Troubleshooting

### Common Issues

**1. Access Denied Errors**
```bash
# Check if role exists in target account
aws iam get-role \
  --role-name RDSDashboardCrossAccountRole \
  --profile <target-account-profile>

# Verify trust policy
aws iam get-role \
  --role-name RDSDashboardCrossAccountRole \
  --query 'Role.AssumeRolePolicyDocument' \
  --profile <target-account-profile>
```

**2. No Instances Discovered**
```bash
# Check if RDS instances exist
aws rds describe-db-instances --region ap-southeast-1

# Check discovery Lambda logs
aws logs tail /aws/lambda/rds-discovery --follow
```

**3. Wrong Account ID in Dashboard**
- Ensure `AWS_ACCOUNT_ID` environment variable is set in Lambda
- Check that discovery is using correct credentials

## Cost Considerations

**Estimated Monthly Costs for Testing:**

- **4 RDS db.t4g.micro instances**: ~$50/month ($12.50 each)
- **Lambda executions**: ~$1/month
- **DynamoDB**: ~$2/month
- **CloudWatch Logs**: ~$1/month
- **Data transfer**: ~$2/month

**Total: ~$56/month**

**Cost Optimization Tips:**
1. Stop RDS instances when not testing (saves ~70%)
2. Delete instances after testing
3. Use RDS Free Tier if available (750 hours/month)
4. Set up billing alerts

## Cleanup Script

```bash
# Delete test RDS instances
aws rds delete-db-instance \
  --db-instance-identifier test-rds-singapore \
  --skip-final-snapshot \
  --region ap-southeast-1

aws rds delete-db-instance \
  --db-instance-identifier test-rds-london \
  --skip-final-snapshot \
  --region eu-west-2

aws rds delete-db-instance \
  --db-instance-identifier test-rds-mumbai \
  --skip-final-snapshot \
  --region ap-south-1

aws rds delete-db-instance \
  --db-instance-identifier test-rds-virginia \
  --skip-final-snapshot \
  --region us-east-1

# Remove test account from configuration
# (Edit config/dashboard-config.json manually)

# Close AWS account (if using Organizations)
aws organizations close-account --account-id <TEST_ACCOUNT_ID>
```

## Next Steps

1. **Create AWS Organization** (recommended)
2. **Create test account** via Organizations
3. **Deploy cross-account role** in test account
4. **Create test RDS instances** in multiple regions
5. **Run discovery** and verify results
6. **Test operations** (start/stop/reboot) across accounts
7. **Verify cost tracking** across accounts
8. **Test compliance checks** across accounts

## Summary

**Answers to Your Questions:**

1. **Can you create AWS Organization?** 
   - ✅ Yes! Highly recommended for testing

2. **Which regions are enabled?**
   - ap-southeast-1 (Singapore)
   - eu-west-2 (London)
   - ap-south-1 (Mumbai)
   - us-east-1 (N. Virginia)

3. **Should you create VPC or use default?**
   - ✅ Use default VPC for testing
   - 🏗️ Create custom VPC for production
   - The app works seamlessly with both

4. **Will the app work seamlessly?**
   - ✅ Yes! The app is designed for multi-account/multi-region
   - Just ensure cross-account roles are properly configured
   - Default VPC is perfectly fine for testing

The dashboard is fully ready for multi-account and multi-region testing!
