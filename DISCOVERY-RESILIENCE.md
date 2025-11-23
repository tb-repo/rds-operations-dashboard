# Discovery Lambda Resilience Enhancement

## Overview

The Discovery Lambda has been enhanced with comprehensive error isolation to ensure that failures in individual accounts or regions never impact the overall Lambda execution or other successful discoveries.

## Key Resilience Features

### 1. **Multi-Level Error Isolation**

```
Lambda Handler
├── Account 1 (Success) ✓
├── Account 2 (Failed) ✗ → Logged, but doesn't stop execution
├── Account 3 (Success) ✓
    ├── Region us-east-1 (Success) ✓
    ├── Region eu-west-1 (Failed) ✗ → Logged, but doesn't stop execution
    └── Region ap-southeast-1 (Success) ✓
```

Each level is completely isolated:
- **Account-level failures** don't impact other accounts
- **Region-level failures** don't impact other regions in the same account
- **Instance-level failures** don't impact other instances in the same region

### 2. **Never-Fail Guarantee**

The Lambda is designed to **ALWAYS return HTTP 200** unless there's a catastrophic failure (e.g., out of memory, DynamoDB completely unavailable).

**Success Criteria:**
- ✓ Lambda returns 200 even if some accounts fail
- ✓ Lambda returns 200 even if all cross-account discoveries fail (as long as current account succeeds)
- ✓ Lambda returns 200 even if some regions are inaccessible
- ✓ Lambda returns 200 even if persistence fails (errors are logged)

**Only returns 500 when:**
- Cannot determine current AWS account identity
- Complete system failure (extremely rare)

### 3. **Comprehensive Error Reporting**

Every error includes:
- **Type**: Category of error (e.g., `cross_account_access`, `region_not_enabled`)
- **Severity**: `low`, `medium`, `high`, or `critical`
- **Error Message**: Detailed description
- **Remediation**: Actionable steps to fix the issue
- **Context**: Account ID, region, timestamp

Example error structure:
```json
{
  "account_id": "123456789012",
  "region": "us-east-1",
  "type": "cross_account_access",
  "severity": "high",
  "error": "AccessDenied: User is not authorized to perform: sts:AssumeRole",
  "remediation": "Create IAM role 'RDSDiscoveryRole' in account 123456789012...",
  "timestamp": "2025-11-20T10:30:00Z"
}
```

### 4. **Intelligent Error Analysis**

The Lambda automatically analyzes errors and provides specific remediation:

| Error Type | Remediation Provided |
|------------|---------------------|
| **Cross-Account Access Denied** | Detailed trust policy example with correct ExternalId |
| **Region Not Enabled** | Instructions to enable region or remove from TARGET_REGIONS |
| **Invalid Credentials** | Check Lambda execution role permissions |
| **Rate Limiting** | Automatic retry on next scheduled run |
| **Timeout** | Increase Lambda timeout configuration |

### 5. **Parallel Execution with Isolation**

- Uses `ThreadPoolExecutor` for parallel region scanning (4 workers)
- Each region runs in isolated thread
- Thread failures don't propagate to other threads
- Timeout protection (60 seconds per region)

### 6. **Graceful Degradation**

The Lambda degrades gracefully when components fail:

```
Configuration Load Failed
  ↓
Use Minimal Config (current account only)
  ↓
Continue Discovery

Region Detection Failed
  ↓
Use Fallback Regions (ap-southeast-1)
  ↓
Continue Discovery

Cross-Account Validation Failed
  ↓
Skip That Account, Log Error
  ↓
Continue with Other Accounts

Persistence Failed
  ↓
Log Error, Return Discovery Results
  ↓
Lambda Still Succeeds
```

## Implementation Details

### Function Hierarchy

```
lambda_handler()                    [Never throws, always returns 200]
  └── discover_all_instances()      [Never throws, catches all errors]
      └── discover_account_instances()  [Never throws, returns (instances, errors)]
          └── discover_region_instances()  [Throws on failure, caught by parent]
              └── extract_instance_metadata()  [Never throws, returns minimal data on error]
```

### Error Handling Strategy

1. **Outer Functions** (handler, discover_all_instances): Never throw, always return valid results
2. **Middle Functions** (discover_account_instances): Never throw, collect errors in list
3. **Inner Functions** (discover_region_instances): Throw to signal failure, caught by parent
4. **Leaf Functions** (extract_instance_metadata): Never throw, return minimal data on error

### Key Code Patterns

**Pattern 1: Try-Catch with Continue**
```python
for account_id in target_accounts:
    try:
        # Discover account
        instances, errors = discover_account_instances(...)
        all_instances.extend(instances)
    except Exception as e:
        # Log error, add to error list, CONTINUE to next account
        errors.append(analyze_error(e))
        continue  # Don't break the loop
```

**Pattern 2: Always Return Valid Data**
```python
def discover_all_instances(config):
    try:
        # ... discovery logic ...
    except Exception as e:
        # Even on catastrophic error, return valid structure
        errors.append({'error': str(e)})
    
    # ALWAYS return valid dict
    return {
        'total_instances': len(instances),
        'instances': instances,
        'errors': errors,
        # ... other fields ...
    }
```

**Pattern 3: Nested Error Handling**
```python
try:
    # Outer operation
    try:
        # Inner operation that might fail
        result = risky_operation()
    except Exception as inner_error:
        # Handle inner error, use fallback
        result = fallback_value
        warnings.append(inner_error)
    
    # Continue with result (either real or fallback)
    process(result)
except Exception as outer_error:
    # Handle outer error
    errors.append(outer_error)
```

## Testing Resilience

Run the resilience test:
```powershell
.\test-discovery-resilience.ps1
```

This validates:
- ✓ Lambda returns 200 even with errors
- ✓ Errors have proper structure with remediation
- ✓ Discovery timestamp is recorded
- ✓ Execution status is set
- ✓ Success rate is calculated

## Monitoring

### CloudWatch Metrics

The Lambda publishes these metrics:
- `DiscoverySuccess`: 1 if any instances discovered, 0 otherwise
- `InstancesDiscovered`: Total count
- `AccountsScanned`: Successfully scanned accounts
- `AccountsFailed`: Failed accounts
- `ErrorCount`: Total errors encountered

### CloudWatch Logs

Structured logging provides:
- **INFO**: Successful operations, summary statistics
- **WARNING**: Non-critical failures (region not enabled, cross-account skipped)
- **ERROR**: Critical failures (account discovery failed, persistence failed)

Example log query:
```
fields @timestamp, level, message, account_id, region, error_type
| filter level = "ERROR"
| sort @timestamp desc
```

## Best Practices

### 1. **Monitor Error Trends**
- Set up CloudWatch alarms for `ErrorCount > 0`
- Review errors weekly to identify systemic issues
- Track success rate over time

### 2. **Review Remediation Steps**
- Errors include actionable remediation
- Follow remediation steps to fix root causes
- Update cross-account roles as needed

### 3. **Validate Cross-Account Setup**
- Test cross-account access before adding to TARGET_ACCOUNTS
- Use provided trust policy examples
- Verify ExternalId matches configuration

### 4. **Handle Region Failures**
- Remove disabled regions from TARGET_REGIONS
- Enable required regions in AWS Console
- Consider region-specific IAM permissions

## Success Metrics

### Current Behavior
- ✓ Lambda succeeds even if 50% of accounts fail
- ✓ Lambda succeeds even if 80% of regions fail
- ✓ Individual instance extraction failures don't stop discovery
- ✓ Persistence failures don't fail the Lambda
- ✓ Metrics publishing failures don't fail the Lambda

### Expected Outcomes
- **High Availability**: Discovery continues despite partial failures
- **Visibility**: All errors are logged with remediation steps
- **Reliability**: Lambda never fails due to external account issues
- **Maintainability**: Clear error messages guide troubleshooting

## Troubleshooting

### Scenario 1: No Instances Discovered
**Check:**
1. Review errors in Lambda response
2. Verify current account has RDS instances
3. Check Lambda execution role has `rds:DescribeDBInstances` permission
4. Verify TARGET_REGIONS includes regions with instances

### Scenario 2: Cross-Account Discovery Failing
**Check:**
1. Review error remediation in Lambda response
2. Verify cross-account role exists in target account
3. Check trust policy includes correct ExternalId
4. Verify role has RDS describe permissions

### Scenario 3: Some Regions Failing
**Check:**
1. Review region-specific errors
2. Verify regions are enabled in account
3. Check if regions require opt-in
4. Remove disabled regions from TARGET_REGIONS

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Lambda Handler                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Try-Catch Wrapper (Never Fails)                       │  │
│  │  ├─ Load Config (with fallback)                       │  │
│  │  ├─ Discover All Instances (never throws)             │  │
│  │  ├─ Persist Results (with error handling)             │  │
│  │  ├─ Publish Metrics (best effort)                     │  │
│  │  └─ Send Notifications (best effort)                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│              Always Returns HTTP 200                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              Discover All Instances                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ For Each Account (isolated):                          │  │
│  │   Try:                                                 │  │
│  │     ├─ Validate Access (skip if fails)                │  │
│  │     ├─ Discover Account Instances                     │  │
│  │     └─ Collect Results                                │  │
│  │   Catch:                                               │  │
│  │     └─ Log Error, Add to Error List, CONTINUE         │  │
│  └───────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│         Returns (instances, errors) - Never Throws           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│           Discover Account Instances                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ThreadPoolExecutor (4 workers):                        │  │
│  │   For Each Region (parallel, isolated):               │  │
│  │     Try:                                               │  │
│  │       └─ Discover Region Instances                    │  │
│  │     Catch:                                             │  │
│  │       └─ Log Error, Add to Error List, CONTINUE       │  │
│  └───────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│         Returns (instances, errors) - Never Throws           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│            Discover Region Instances                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ For Each Instance (isolated):                         │  │
│  │   Try:                                                 │  │
│  │     └─ Extract Instance Metadata                      │  │
│  │   Catch:                                               │  │
│  │     └─ Log Warning, SKIP Instance, CONTINUE           │  │
│  └───────────────────────────────────────────────────────┘  │
│                           ↓                                  │
│    Returns instances list OR Throws (caught by parent)       │
└─────────────────────────────────────────────────────────────┘
```

## Conclusion

The Discovery Lambda is now highly resilient and will continue to discover RDS instances across all accessible accounts and regions, even when some accounts or regions fail. All failures are logged with actionable remediation steps, ensuring visibility and maintainability.

**Key Takeaway**: Individual account or region failures are expected and handled gracefully. The Lambda will always succeed as long as it can discover instances in at least one account/region.
