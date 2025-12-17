# Cross-Account Access Fix

## Problem
All backend Lambda functions were attempting to assume a cross-account IAM role (`RDSDashboardCrossAccountRole`) even when accessing RDS instances in the same AWS account. This caused 500 Internal Server Error responses for:
- Health metrics endpoint (`/api/health/{instanceId}`)
- Operations endpoint (`/api/operations`)
- Other backend services

## Root Cause
The Lambda functions check if `account_id` from the RDS inventory matches `os.environ.get('AWS_ACCOUNT_ID')` to determine whether cross-account access is needed. Since the `AWS_ACCOUNT_ID` environment variable was not set, it always returned `None`, causing the code to attempt cross-account role assumption even for same-account resources.

## Solution
Added `AWS_ACCOUNT_ID=876595225096` environment variable to all production Lambda functions:

- ✅ rds-health-monitor-prod
- ✅ rds-operations-prod  
- ✅ rds-discovery-prod
- ✅ rds-query-handler-prod
- ✅ rds-cloudops-generator-prod
- ✅ rds-compliance-checker-prod
- ✅ rds-cost-analyzer-prod

## Testing
After applying this fix:

1. **Refresh your browser** - Clear cache if needed
2. **Navigate to Instances page** - Should load without errors
3. **Click on an instance** - Health metrics should display
4. **Try Start/Stop operations** - Should work without 500 errors

## Code Reference
The fix allows this logic in `lambda/shared/aws_clients.py` to work correctly:

```python
if account_id == os.environ.get('AWS_ACCOUNT_ID'):
    # Same account - use direct access
    cw_client = AWSClients.get_cloudwatch_client(region=region)
else:
    # Cross-account - assume role
    cw_client = AWSClients.get_cloudwatch_client(
        region=region,
        account_id=account_id,
        role_name=config.cross_account.role_name,
        external_id=config.cross_account.external_id
    )
```

## Date Fixed
December 7, 2025

## Related Issues
- 500 errors on instance detail page
- Health metrics not loading
- Operations (start/stop/reboot) failing
