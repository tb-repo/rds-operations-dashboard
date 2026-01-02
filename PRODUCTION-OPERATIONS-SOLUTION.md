# Production Operations Solution

**Issue:** 403/500 errors when attempting operations on production RDS instances  
**Root Cause:** System designed to block operations on production instances for safety  
**Solution:** Enable production operations with configurable safeguards

---

## Understanding the Issue

The RDS Operations Dashboard was originally designed with a safety mechanism that **blocks all operations on production instances** to prevent accidental changes. This is why you're seeing:

- **403 errors**: "Authorization denied: Production instance protection"
- **500 errors**: Health endpoint failures when trying to access production instances

The system classifies instances based on their `Environment` AWS tag:
- `Environment: Production` → Operations blocked
- `Environment: Development/Test/Staging` → Operations allowed

## The Solution

Since this is a **production application** (not about environment classification), we've implemented a solution that allows production operations with configurable safeguards.

### What Changed

1. **Configuration-Based Control**
   - Added `enable_production_operations` flag in `config/dashboard-config.json`
   - When enabled, allows operations on production instances
   - When disabled, maintains original blocking behavior

2. **Tiered Operation Safety**
   - **Safe operations** (always allowed on production):
     - `create_snapshot` - Creates backups
     - `modify_backup_window` - Changes backup timing
     - `enable_storage_autoscaling` - Prevents storage issues
   
   - **Risky operations** (require admin + confirmation):
     - `reboot` / `reboot_instance` - Requires admin privileges + confirmation
     - `stop_instance` / `start_instance` - Requires admin privileges + confirmation
     - `modify_storage` - Requires admin privileges

3. **Additional Safeguards**
   - Admin privileges required for risky operations
   - Explicit confirmation parameter required for destructive operations
   - All operations logged to audit trail
   - Enhanced logging for production operations

## How to Enable Production Operations

### Quick Enable (Recommended)

Run the automated script:

```powershell
cd rds-operations-dashboard
.\enable-production-operations.ps1
```

This script will:
1. Update the configuration file
2. Deploy the operations Lambda with new config
3. Update the BFF environment variable
4. Verify all changes

### Manual Enable

If you prefer manual steps:

#### Step 1: Update Configuration

Edit `config/dashboard-config.json`:

```json
{
  "operations": {
    "enable_production_operations": true,
    "require_admin_for_risky_operations": true,
    "require_confirmation_for_destructive_operations": true,
    "safe_production_operations": [
      "create_snapshot",
      "modify_backup_window",
      "enable_storage_autoscaling"
    ],
    "risky_production_operations": [
      "reboot",
      "reboot_instance",
      "stop_instance",
      "start_instance",
      "modify_storage"
    ]
  }
}
```

#### Step 2: Deploy Operations Lambda

```powershell
# Deploy the compute stack (includes operations Lambda)
cdk deploy RDSDashboardComputeStack --require-approval never
```

#### Step 3: Update BFF Environment

```powershell
# Get BFF function name
$bffFunction = aws lambda list-functions --query 'Functions[?contains(FunctionName, `rds-dashboard-bff`)].FunctionName' --output text

# Update environment variable
aws lambda update-function-configuration `
  --function-name $bffFunction `
  --environment "Variables={ENABLE_PRODUCTION_OPERATIONS=true}"
```

#### Step 4: Verify

```powershell
# Test that operations work
.\test-instance-operations.ps1 -InstanceId database-1
```

## Using Production Operations

### Safe Operations (No Extra Steps)

These operations work immediately on production instances:

```bash
# Create snapshot
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "instance_id": "database-1",
    "operation": "create_snapshot",
    "parameters": {
      "snapshot_id": "prod-snapshot-2025-12-19"
    }
  }'

# Modify backup window
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "instance_id": "database-1",
    "operation": "modify_backup_window",
    "parameters": {
      "backup_window": "03:00-04:00"
    }
  }'
```

### Risky Operations (Require Admin + Confirmation)

For operations like reboot or stop, you need:
1. **Admin privileges** (Admin or DBA Cognito group)
2. **Confirmation parameter** (`confirm_production: true`)

```bash
# Reboot production instance (requires admin + confirmation)
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "instance_id": "database-1",
    "operation": "reboot_instance",
    "parameters": {
      "confirm_production": true,
      "force_failover": false
    }
  }'

# Stop production instance (requires admin + confirmation)
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "instance_id": "database-1",
    "operation": "stop_instance",
    "parameters": {
      "confirm_production": true
    }
  }'
```

### Error Responses

If you try a risky operation without proper authorization:

```json
{
  "error": "Forbidden",
  "message": "Operation 'reboot_instance' on production instance requires admin privileges",
  "code": "PRODUCTION_PROTECTED"
}
```

If you forget the confirmation parameter:

```json
{
  "error": "Forbidden",
  "message": "Production reboot_instance requires 'confirm_production': true parameter",
  "code": "PRODUCTION_PROTECTED"
}
```

## Security Safeguards

Even with production operations enabled, the system maintains multiple layers of protection:

### 1. Role-Based Access Control
- Only users in `Admin` or `DBA` Cognito groups can perform risky operations
- Regular users can only perform safe operations

### 2. Explicit Confirmation
- Destructive operations require `confirm_production: true` parameter
- Prevents accidental operations from scripts or automation

### 3. Audit Trail
- All operations logged with:
  - User identity
  - Timestamp
  - Operation type
  - Parameters
  - Result (success/failure)
- 90-day retention in DynamoDB

### 4. Enhanced Logging
- Production operations generate WARNING-level logs
- Easy to monitor and alert on production changes
- CloudWatch Logs integration

### 5. Operation Classification
- Clear separation between safe and risky operations
- Configurable operation lists
- Can be customized per organization needs

## Configuration Options

### Disable Production Operations

To revert to blocking all production operations:

```json
{
  "operations": {
    "enable_production_operations": false
  }
}
```

Then redeploy:

```powershell
cdk deploy RDSDashboardComputeStack --require-approval never
```

### Customize Operation Lists

Add or remove operations from safe/risky lists:

```json
{
  "operations": {
    "safe_production_operations": [
      "create_snapshot",
      "modify_backup_window",
      "enable_storage_autoscaling",
      "modify_parameter_group"  // Add custom operation
    ],
    "risky_production_operations": [
      "reboot",
      "stop_instance",
      "start_instance"
      // Removed "modify_storage" - now considered safe
    ]
  }
}
```

### Disable Admin Requirement

To allow all authenticated users to perform risky operations:

```json
{
  "operations": {
    "require_admin_for_risky_operations": false
  }
}
```

**⚠️ Warning:** This reduces security. Only do this if you have other access controls in place.

### Disable Confirmation Requirement

To remove the confirmation parameter requirement:

```json
{
  "operations": {
    "require_confirmation_for_destructive_operations": false
  }
}
```

**⚠️ Warning:** This increases risk of accidental operations.

## Monitoring and Auditing

### View Audit Logs

```powershell
# Query DynamoDB audit table
aws dynamodb scan --table-name audit-log-prod \
  --filter-expression "contains(operation, :op)" \
  --expression-attribute-values '{":op":{"S":"reboot"}}'

# View CloudWatch Logs
aws logs tail /aws/lambda/rds-operations --follow
```

### Set Up Alerts

Create CloudWatch alarms for production operations:

```bash
# Alert on production reboots
aws cloudwatch put-metric-alarm \
  --alarm-name production-reboot-alert \
  --alarm-description "Alert when production instance is rebooted" \
  --metric-name ProductionOperations \
  --namespace DBMRDSDashboard \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold
```

### Dashboard Metrics

The system tracks:
- `ProductionOperationCount` - Total production operations
- `RiskyOperationCount` - Risky operations performed
- `SafeOperationCount` - Safe operations performed
- `OperationFailureRate` - Failed operations percentage

## Troubleshooting

### Issue: Still Getting 403 Errors

**Check 1: Configuration**
```powershell
# Verify config is updated
cat config/dashboard-config.json | grep enable_production_operations
```

**Check 2: Lambda Deployment**
```powershell
# Check Lambda environment
aws lambda get-function-configuration --function-name rds-operations \
  --query 'Environment.Variables'
```

**Check 3: BFF Environment**
```powershell
# Check BFF environment
aws lambda get-function-configuration --function-name rds-dashboard-bff \
  --query 'Environment.Variables.ENABLE_PRODUCTION_OPERATIONS'
```

### Issue: "Admin Privileges Required"

Your user needs to be in the `Admin` or `DBA` Cognito group:

```powershell
# Add user to Admin group
aws cognito-idp admin-add-user-to-group \
  --user-pool-id YOUR_USER_POOL_ID \
  --username user@example.com \
  --group-name Admin
```

### Issue: "Confirmation Required"

Add the confirmation parameter to your request:

```json
{
  "instance_id": "database-1",
  "operation": "reboot_instance",
  "parameters": {
    "confirm_production": true  // ← Add this
  }
}
```

## Best Practices

1. **Start with Safe Operations**
   - Test with snapshots and backup window changes first
   - Verify audit logging is working
   - Confirm monitoring is in place

2. **Use Confirmation Parameters**
   - Always include `confirm_production: true` for risky operations
   - This prevents accidental operations from scripts

3. **Monitor Audit Logs**
   - Set up CloudWatch alarms for production operations
   - Review audit logs regularly
   - Investigate any unexpected operations

4. **Limit Admin Access**
   - Only grant Admin/DBA group membership to trusted users
   - Use temporary access for contractors
   - Review group membership quarterly

5. **Test in Non-Production First**
   - Always test operations on dev/test instances first
   - Verify the operation works as expected
   - Then apply to production with confirmation

6. **Document Changes**
   - Keep a change log of production operations
   - Document why each operation was performed
   - Include rollback procedures

## Related Documentation

- [Troubleshooting 403/500 Errors](./TROUBLESHOOTING-403-500-ERRORS.md)
- [Environment Classification Guide](./docs/environment-classification.md)
- [Operations Service Documentation](./docs/operations-service.md)
- [BFF Security Guide](./docs/bff-security-guide.md)

---

**Document Version:** 1.0.0  
**Last Updated:** 2025-12-19  
**Maintained By:** DBA Team
