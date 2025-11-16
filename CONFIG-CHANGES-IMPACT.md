# Configuration Changes Impact Analysis

**Date:** 2025-11-12  
**Changes Made:** Project name, team names, email, CloudWatch namespace

## Changes Summary

| Field | Old Value | New Value |
|-------|-----------|-----------|
| **Project Tag** | RDSDashboard | DBMRDSDashboard |
| **CostCenter Tag** | DBA-Team | DBM-Team |
| **Owner Tag** | DBA-Team | DBM-Team |
| **CloudWatch Namespace** | RDSDashboard | DBMRDSDashboard |
| **SNS Email** | dba-team@company.com | postgresql.support@idp.com |

## Impact Assessment

### ✅ No Code Changes Required

All your changes are configuration values only. The code is designed to read these values dynamically, so **no code modifications are needed**.

### 1. CloudWatch Namespace ⚠️ Action Required

**Change:** `RDSDashboard` → `DBMRDSDashboard`

**Impact:**
- Lambda functions will publish metrics to new namespace `DBMRDSDashboard`
- Old metrics in `RDSDashboard` namespace will stop being updated
- Historical metrics remain in old namespace

**What Happens:**
```
Before Deployment:
  Namespace: RDSDashboard
  Metrics: InstancesDiscovered, AccountsScanned, etc.

After Deployment:
  Namespace: DBMRDSDashboard (new)
  Metrics: InstancesDiscovered, AccountsScanned, etc. (fresh start)
  
  Old namespace: RDSDashboard (no longer updated)
```

**Action Required:**
1. **CloudWatch Dashboards:** Update any dashboards to use `DBMRDSDashboard` namespace
2. **CloudWatch Alarms:** Update alarms to monitor new namespace
3. **Historical Data:** Old metrics remain accessible in `RDSDashboard` namespace

**Example - Update Alarm:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name rds-discovery-failure \
  --namespace DBMRDSDashboard \
  --metric-name DiscoverySuccess \
  --comparison-operator LessThanThreshold \
  --threshold 1 \
  --evaluation-periods 2 \
  --period 3600
```

### 2. Resource Tags ✅ Automatic

**Changes:**
- `Project: RDSDashboard` → `Project: DBMRDSDashboard`
- `CostCenter: DBA-Team` → `CostCenter: DBM-Team`
- `Owner: DBA-Team` → `Owner: DBM-Team`

**Impact:**
- **New Resources:** Will be tagged with new values automatically
- **Existing Resources:** Keep old tags (CDK doesn't update tags by default)
- **Cost Reports:** New resources will appear under `DBM-Team` cost center

**What Happens:**
```
New DynamoDB tables, Lambda functions, S3 buckets:
  Tags: {
    Project: DBMRDSDashboard,
    CostCenter: DBM-Team,
    Owner: DBM-Team
  }

Existing resources (if any):
  Tags: {
    Project: RDSDashboard,      (unchanged)
    CostCenter: DBA-Team,        (unchanged)
    Owner: DBA-Team              (unchanged)
  }
```

**Action Required (Optional):**
If you want to update tags on existing resources:

```bash
# List resources with old tags
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=RDSDashboard

# Update tags (example for DynamoDB table)
aws dynamodb tag-resource \
  --resource-arn arn:aws:dynamodb:ap-southeast-1:ACCOUNT:table/rds-inventory-prod \
  --tags Key=Project,Value=DBMRDSDashboard \
         Key=CostCenter,Value=DBM-Team \
         Key=Owner,Value=DBM-Team
```

### 3. SNS Email ✅ Action Required

**Change:** `dba-team@company.com` → `postgresql.support@idp.com`

**Impact:**
- SNS topic will be created/updated with new email subscription
- New email will receive subscription confirmation
- Old email will stop receiving alerts

**What Happens:**
```
1. CDK creates/updates SNS topic
2. SNS sends confirmation email to: postgresql.support@idp.com
3. Email must be confirmed to receive alerts
4. Old email (dba-team@company.com) is removed
```

**Action Required:**
1. **After deployment**, check email: `postgresql.support@idp.com`
2. Click "Confirm subscription" link in email
3. Verify alerts are being received

**Test Alert:**
```bash
# Send test notification
aws sns publish \
  --topic-arn arn:aws:sns:ap-southeast-1:ACCOUNT:rds-dashboard-alerts-prod \
  --subject "Test Alert" \
  --message "Testing SNS subscription for postgresql.support@idp.com"
```

### 4. Stack Names ✅ No Impact

**Good News:** Stack names are defined in code, not config file.

**Stack Names Remain:**
- `RDSDashboard-Data-prod`
- `RDSDashboard-IAM-prod`
- `RDSDashboard-Compute-prod`

These won't change, which is good because changing stack names would require recreating resources.

### 5. Resource Names ✅ No Impact

**Resource Names Use Environment Variable:**
- DynamoDB tables: `rds-inventory-prod`, `metrics-cache-prod`, etc.
- Lambda functions: `rds-discovery-prod`, etc.
- S3 bucket: `rds-dashboard-data-{account-id}-prod`

These are defined in code and won't change based on config file.

## Deployment Steps

### 1. Review Changes
```bash
# Verify config file
cat config/dashboard-config.json | jq .

# Check for validation errors
cd infrastructure
npm run build
```

### 2. Deploy Infrastructure
```bash
cd infrastructure

# See what will change
cdk diff

# Deploy all stacks
cdk deploy --all

# Or deploy specific stack
cdk deploy RDSDashboard-Compute-prod
```

### 3. Confirm SNS Subscription
```bash
# Check email: postgresql.support@idp.com
# Click confirmation link
```

### 4. Update CloudWatch (If Needed)

**If you have existing CloudWatch dashboards:**
```bash
# Update dashboard to use new namespace
aws cloudwatch put-dashboard \
  --dashboard-name RDS-Operations \
  --dashboard-body file://dashboard-config.json
```

**If you have existing CloudWatch alarms:**
```bash
# List existing alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix rds-

# Update each alarm to use new namespace
aws cloudwatch put-metric-alarm \
  --alarm-name <alarm-name> \
  --namespace DBMRDSDashboard \
  ...
```

### 5. Verify Deployment
```bash
# Check Lambda environment variables
aws lambda get-function-configuration \
  --function-name rds-discovery-prod \
  --query 'Environment.Variables'

# Should show:
# CLOUDWATCH_NAMESPACE: DBMRDSDashboard

# Invoke Lambda to test
aws lambda invoke \
  --function-name rds-discovery-prod \
  --payload '{}' \
  response.json

# Check CloudWatch Logs
aws logs tail /aws/lambda/rds-discovery-prod --follow

# Verify metrics in new namespace
aws cloudwatch list-metrics \
  --namespace DBMRDSDashboard
```

## Cost Impact

### ✅ No Additional Costs

Your changes don't add any new resources or increase usage:
- CloudWatch namespace change: No cost impact (same number of metrics)
- Tag changes: No cost impact (tags are free)
- SNS email change: No cost impact (same number of notifications)

### Cost Allocation

**Before:**
```
Cost Center: DBA-Team
  - All RDS Dashboard resources
```

**After:**
```
Cost Center: DBM-Team
  - New resources only
  
Cost Center: DBA-Team
  - Existing resources (until tags updated)
```

## Rollback Plan

If you need to revert changes:

### 1. Revert Config File
```bash
cd config
git checkout HEAD~1 dashboard-config.json
```

### 2. Redeploy
```bash
cd infrastructure
cdk deploy --all
```

### 3. Reconfirm Old Email
```bash
# Old email will receive new confirmation
# Click link to reactivate
```

## Testing Checklist

After deployment, verify:

- [ ] Lambda functions deployed successfully
- [ ] Environment variables updated with new namespace
- [ ] SNS subscription confirmed (check email)
- [ ] Test notification received at new email
- [ ] Metrics appearing in new CloudWatch namespace
- [ ] Discovery Lambda runs successfully
- [ ] No errors in CloudWatch Logs
- [ ] Tags applied to new resources
- [ ] Cost allocation showing new cost center (for new resources)

## Summary

### ✅ Safe to Deploy

Your changes are **safe and won't break any code**. The configuration system is designed to handle these changes dynamically.

### Action Items

1. **Deploy:** `cdk deploy --all`
2. **Confirm Email:** Check `postgresql.support@idp.com` and confirm SNS subscription
3. **Update CloudWatch (Optional):** Update dashboards/alarms to use `DBMRDSDashboard` namespace
4. **Update Tags (Optional):** Update tags on existing resources if needed

### No Action Required

- ✅ Code changes: None needed
- ✅ Lambda functions: Will pick up new config automatically
- ✅ Resource names: Unchanged
- ✅ Stack names: Unchanged

## Questions?

If you have any concerns:
1. Check CloudWatch Logs: `/aws/lambda/rds-discovery-prod`
2. Review CDK diff output: `cdk diff`
3. Test in dev environment first (if available)

**Your changes are good to go! 🚀**
