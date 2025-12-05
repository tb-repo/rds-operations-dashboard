# Discovery Lambda - Quick Reference Guide

## What Changed?

The Discovery Lambda now has **bulletproof error isolation** - failures in one account or region never impact other accounts/regions or the overall Lambda execution.

## Key Behaviors

### ✓ What Works Now

1. **Account Isolation**: If Account A fails, Accounts B and C still get discovered
2. **Region Isolation**: If us-east-1 fails, ap-southeast-1 still gets discovered
3. **Instance Isolation**: If one instance has bad metadata, others still get processed
4. **Always Succeeds**: Lambda returns HTTP 200 even with partial failures
5. **Detailed Errors**: Every error includes remediation steps

### ✓ Example Scenarios

**Scenario 1: Cross-Account Role Missing**
```
Result: ✓ Lambda succeeds
- Current account: Discovered successfully
- Account 123456789012: Skipped with error
- Error includes: Trust policy example to fix
```

**Scenario 2: Region Not Enabled**
```
Result: ✓ Lambda succeeds
- us-east-1: Discovered successfully
- eu-north-1: Skipped with error
- Error includes: Instructions to enable region
```

**Scenario 3: All Cross-Accounts Fail**
```
Result: ✓ Lambda succeeds
- Current account: Discovered successfully
- All other accounts: Skipped with errors
- Dashboard shows current account instances
```

## Response Structure

```json
{
  "statusCode": 200,
  "body": {
    "total_instances": 15,
    "accounts_attempted": 3,
    "accounts_scanned": 2,
    "regions_scanned": 6,
    "execution_status": "completed_with_errors",
    "errors": [
      {
        "account_id": "123456789012",
        "type": "cross_account_access",
        "severity": "high",
        "error": "AccessDenied...",
        "remediation": "Create IAM role..."
      }
    ],
    "warnings": [
      {
        "type": "region_not_enabled",
        "severity": "low",
        "message": "Region eu-north-1 not enabled"
      }
    ]
  }
}
```

## Error Types & Remediation

| Error Type | Severity | What It Means | How to Fix |
|------------|----------|---------------|------------|
| `cross_account_access` | High | Can't access target account | Create/fix IAM role with trust policy |
| `region_not_enabled` | Low | Region not enabled in account | Enable region or remove from config |
| `invalid_credentials` | Critical | AWS credentials invalid | Check Lambda execution role |
| `rate_limit` | Medium | Too many API calls | Wait for next run (automatic) |
| `timeout` | Medium | Operation took too long | Increase Lambda timeout |
| `permissions` | High | Missing IAM permissions | Add RDS describe permissions |

## Testing

### Quick Test
```powershell
# Test the Lambda
.\test-discovery-resilience.ps1
```

### Validate Code
```powershell
# Validate resilience patterns
python validate-discovery-resilience.py
```

### Check Logs
```bash
# View recent errors
aws logs tail /aws/lambda/RDSDiscoveryFunction-prod --follow --filter-pattern "ERROR"
```

## Monitoring

### CloudWatch Metrics
- `DiscoverySuccess`: 1 = success, 0 = complete failure
- `InstancesDiscovered`: Total instances found
- `AccountsScanned`: Successfully scanned accounts
- `ErrorCount`: Total errors (non-zero is OK!)

### Alarms to Set Up
```bash
# Alert if NO accounts scanned (critical)
AccountsScanned = 0

# Alert if error rate > 50% (warning)
ErrorCount / AccountsAttempted > 0.5
```

## Common Questions

### Q: Lambda shows errors but returned 200. Is this OK?
**A:** Yes! This is expected. Errors mean some accounts/regions failed, but others succeeded. The Lambda only fails (500) if it can't discover ANYTHING.

### Q: How do I know if cross-account discovery is working?
**A:** Check the response:
- `accounts_attempted > 1`: Cross-account is configured
- `accounts_scanned = accounts_attempted`: All working
- `accounts_scanned < accounts_attempted`: Some failed (check errors)

### Q: What if all cross-account discoveries fail?
**A:** Lambda still succeeds! It will discover the current account and log errors for cross-accounts with remediation steps.

### Q: Should I be concerned about errors?
**A:** Depends on severity:
- **Low**: Informational (region not enabled) - safe to ignore
- **Medium**: Temporary (rate limit, timeout) - will resolve
- **High**: Needs attention (access denied) - follow remediation
- **Critical**: Urgent (invalid credentials) - fix immediately

## Configuration

### Environment Variables
```bash
# Required
INVENTORY_TABLE=rds-inventory-prod

# Optional (for cross-account)
TARGET_ACCOUNTS=["123456789012", "234567890123"]
CROSS_ACCOUNT_ROLE_NAME=RDSDiscoveryRole
EXTERNAL_ID=your-external-id

# Optional (for regions)
TARGET_REGIONS=["us-east-1", "ap-southeast-1", "eu-west-1"]
```

### Cross-Account Setup
1. Create role in target account: `RDSDiscoveryRole`
2. Add trust policy with ExternalId
3. Attach policy with `rds:Describe*` permissions
4. Add account to `TARGET_ACCOUNTS`

## Troubleshooting

### No Instances Found
1. Check errors in response
2. Verify current account has RDS instances
3. Check Lambda role has `rds:DescribeDBInstances`
4. Verify regions are correct

### Cross-Account Not Working
1. Review error remediation in response
2. Verify role exists in target account
3. Check trust policy has correct ExternalId
4. Test role assumption manually

### High Error Rate
1. Review error types and severities
2. Fix high/critical errors first
3. Check if regions need to be enabled
4. Verify IAM permissions are correct

## Architecture

```
┌─────────────────────────────────────────┐
│         Lambda Handler                  │
│  ┌───────────────────────────────────┐  │
│  │ Never Fails (Always Returns 200)  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│      Discover All Instances             │
│  ┌───────────────────────────────────┐  │
│  │ For Each Account (Isolated)       │  │
│  │   ├─ Account A ✓                  │  │
│  │   ├─ Account B ✗ (logged)         │  │
│  │   └─ Account C ✓                  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│    Discover Account Instances           │
│  ┌───────────────────────────────────┐  │
│  │ For Each Region (Parallel)        │  │
│  │   ├─ us-east-1 ✓                  │  │
│  │   ├─ eu-west-1 ✗ (logged)         │  │
│  │   └─ ap-southeast-1 ✓             │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│     Discover Region Instances           │
│  ┌───────────────────────────────────┐  │
│  │ For Each Instance (Isolated)      │  │
│  │   ├─ Instance 1 ✓                 │  │
│  │   ├─ Instance 2 ✗ (skipped)       │  │
│  │   └─ Instance 3 ✓                 │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Success Criteria

✓ Lambda returns 200 even with errors
✓ Errors include actionable remediation
✓ Account failures don't stop other accounts
✓ Region failures don't stop other regions
✓ Instance failures don't stop other instances
✓ Detailed logging for troubleshooting
✓ Metrics published for monitoring

## Next Steps

1. **Deploy**: Deploy the updated Lambda
2. **Test**: Run `test-discovery-resilience.ps1`
3. **Monitor**: Check CloudWatch for errors
4. **Fix**: Follow remediation steps for any errors
5. **Verify**: Confirm all accounts/regions are discovered

## Support

- **Documentation**: See `DISCOVERY-RESILIENCE.md` for detailed architecture
- **Logs**: Check CloudWatch Logs for detailed error traces
- **Metrics**: Monitor CloudWatch Metrics for trends
- **Errors**: All errors include remediation steps in response
