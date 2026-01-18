# Deploy Cross-Account Role via AWS Console

**Date:** January 16, 2026  
**Account:** 817214535871  
**Method:** AWS Console (Recommended due to CLI permission constraints)

## Why AWS Console?

Your `sec_prg_user` account lacks CloudFormation CLI permissions, but you can deploy via the AWS Console which uses different permission paths.

## Prerequisites

- ✅ Access to AWS Console for account **817214535871**
- ✅ IAM permissions to create CloudFormation stacks
- ✅ IAM permissions to create IAM roles (or admin access)

## Step-by-Step Instructions

### Step 1: Prepare the Template File

The CloudFormation template is already in your project:
```
rds-operations-dashboard/infrastructure/cross-account-role.yaml
```

### Step 2: Log into AWS Console

1. Open your browser
2. Go to: https://console.aws.amazon.com/
3. Sign in with credentials for account **817214535871**
4. Verify you're in the correct account (check top-right corner)

### Step 3: Navigate to CloudFormation

**Option A - Direct Link:**
- Go to: https://ap-southeast-1.console.aws.amazon.com/cloudformation/

**Option B - Search:**
- Click the search bar at the top
- Type "CloudFormation"
- Click on "CloudFormation" service

### Step 4: Create Stack

1. Click the **"Create stack"** button
2. Select **"With new resources (standard)"**
3. Under "Prepare template", ensure **"Template is ready"** is selected
4. Under "Specify template", select **"Upload a template file"**
5. Click **"Choose file"**
6. Navigate to and select: `infrastructure/cross-account-role.yaml`
7. Click **"Next"**

### Step 5: Specify Stack Details

**Stack name:**
```
rds-dashboard-cross-account-role
```

**Parameters:**

| Parameter | Value | Description |
|-----------|-------|-------------|
| ManagementAccountId | `876595225096` | The account where RDS Dashboard is deployed |
| ExternalId | `rds-dashboard-unique-external-id` | Security token for role assumption |
| RoleName | `RDSDashboardCrossAccountRole` | Name of the IAM role to create |

Click **"Next"**

### Step 6: Configure Stack Options

1. **Tags** (optional but recommended):
   - Key: `Project`, Value: `RDS-Operations-Dashboard`
   - Key: `Environment`, Value: `Production`
   - Key: `ManagedBy`, Value: `CloudFormation`

2. **Permissions** (leave default)

3. **Stack failure options** (leave default)

4. Click **"Next"**

### Step 7: Review and Create

1. **Review all settings** carefully:
   - Stack name: `rds-dashboard-cross-account-role`
   - ManagementAccountId: `876595225096`
   - ExternalId: `rds-dashboard-unique-external-id`
   - RoleName: `RDSDashboardCrossAccountRole`

2. **Acknowledge IAM resources:**
   - ✅ Check the box: **"I acknowledge that AWS CloudFormation might create IAM resources with custom names"**

3. Click **"Submit"**

### Step 8: Monitor Stack Creation

1. You'll be redirected to the stack details page
2. Watch the **"Events"** tab for progress
3. Status will show: `CREATE_IN_PROGRESS`
4. Wait 2-3 minutes for completion
5. Status will change to: `CREATE_COMPLETE` ✅

**If stack creation fails:**
- Check the "Events" tab for error messages
- Common issues:
  - Insufficient IAM permissions
  - Role name already exists
  - Invalid parameter values

### Step 9: Verify Stack Outputs

1. Click on the **"Outputs"** tab
2. You should see:
   - **RoleArn**: `arn:aws:iam::817214535871:role/RDSDashboardCrossAccountRole`
   - **RoleName**: `RDSDashboardCrossAccountRole`
   - **ManagementAccountId**: `876595225096`
   - **ExternalId**: `rds-dashboard-unique-external-id`
   - **TestAssumeRoleCommand**: Command to test the role

## Verification

After successful deployment, verify the role works:

### Option 1: PowerShell Script (Recommended)

```powershell
cd rds-operations-dashboard
./scripts/verify-cross-account-role-simple.ps1
```

Expected output:
```
✅ SUCCESS! Cross-account role is working!
```

### Option 2: AWS CLI Manual Test

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::817214535871:role/RDSDashboardCrossAccountRole \
  --role-session-name test \
  --external-id rds-dashboard-unique-external-id
```

Expected: JSON response with temporary credentials

## Trigger Discovery

Once the role is verified, trigger discovery to find instances:

```powershell
# Trigger discovery Lambda
aws lambda invoke `
  --function-name rds-discovery-prod `
  --region ap-southeast-1 `
  response.json

# Check response
cat response.json
```

Wait 2-3 minutes, then refresh your dashboard:
- URL: https://d2qvaswtmn22om.cloudfront.net
- All 3 instances should now be visible

## Troubleshooting

### Issue: "Access Denied" when creating stack

**Solution:**
- Verify you have IAM permissions to create CloudFormation stacks
- Verify you have IAM permissions to create IAM roles
- Contact your AWS administrator for necessary permissions

### Issue: "Role already exists"

**Solution:**
- The role may have been created previously
- Check IAM console: https://console.aws.amazon.com/iam/
- Navigate to Roles → Search for "RDSDashboardCrossAccountRole"
- If it exists, verify its trust policy and permissions match the template

### Issue: Stack creation fails with "Invalid parameter"

**Solution:**
- Double-check all parameter values
- Ensure ManagementAccountId is exactly: `876595225096`
- Ensure ExternalId is exactly: `rds-dashboard-unique-external-id`
- Ensure RoleName is exactly: `RDSDashboardCrossAccountRole`

### Issue: Role created but assumption fails

**Solution:**
1. Check trust policy in IAM console
2. Verify it allows account `876595225096`
3. Verify external ID matches: `rds-dashboard-unique-external-id`
4. Run diagnostic: `./scripts/diagnose-cross-account-discovery.ps1`

## What This Role Does

The cross-account role provides:

### Permissions
- ✅ **RDS Operations**: Start, stop, reboot instances
- ✅ **RDS Read**: Describe and list all RDS resources
- ✅ **CloudWatch**: Metrics and monitoring data
- ✅ **Cost Explorer**: Cost tracking and forecasting
- ✅ **EC2 Network**: VPC and security group information
- ✅ **Read-Only Access**: General AWS resource visibility

### Security
- 🔒 **Trust Policy**: Only account 876595225096 can assume
- 🔒 **External ID**: Prevents confused deputy attacks
- 🔒 **Session Duration**: 15-minute sessions
- 🔒 **Audit Trail**: All actions logged in CloudTrail

## Success Criteria

After deployment, you should have:

- ✅ CloudFormation stack: `CREATE_COMPLETE`
- ✅ IAM role exists: `RDSDashboardCrossAccountRole`
- ✅ Role assumption test: Success
- ✅ Discovery finds instances in secondary account
- ✅ Dashboard shows all 3 instances

## Next Steps

After successful deployment:

1. ✅ Verify role with verification script
2. ✅ Trigger discovery Lambda
3. ✅ Wait 2-3 minutes for discovery to complete
4. ✅ Refresh dashboard and verify all instances visible
5. ✅ Test operations on cross-account instances
6. ✅ Complete Phase 2 and Phase 3 of critical fixes

## Estimated Time

- **Stack creation**: 2-3 minutes
- **Verification**: 1-2 minutes
- **Discovery**: 2-3 minutes
- **Total**: 5-10 minutes

## Support

If you encounter issues:

1. Check CloudFormation Events tab for error details
2. Run diagnostic script: `./scripts/diagnose-cross-account-discovery.ps1`
3. Check CloudWatch Logs: `/aws/lambda/rds-discovery-prod`
4. Review IAM role in console to verify trust policy

---

**Ready to proceed?** Follow the steps above to deploy the cross-account role via AWS Console.
