# Discovery Lambda Resilience - Deployment Checklist

## Pre-Deployment Validation

### ✓ Code Validation
- [x] Run syntax validation
  ```powershell
  python validate-discovery-resilience.py
  ```
  **Expected:** All checks pass ✓

- [x] Check diagnostics
  ```powershell
  # No syntax errors in handler.py
  ```
  **Expected:** No diagnostics found ✓

- [x] Review changes
  - [x] lambda_handler() enhanced with error isolation
  - [x] discover_all_instances() never throws
  - [x] discover_account_instances() never throws
  - [x] discover_region_instances() has error handling
  - [x] extract_instance_metadata() never throws

### ✓ Documentation Review
- [x] DISCOVERY-RESILIENCE.md - Detailed architecture
- [x] DISCOVERY-QUICK-REFERENCE.md - Quick reference guide
- [x] RESILIENCE-IMPLEMENTATION-SUMMARY.md - Implementation summary
- [x] docs/discovery-resilience-flow.md - Visual flow diagrams

### ✓ Test Scripts Ready
- [x] test-discovery-resilience.ps1 - PowerShell test script
- [x] validate-discovery-resilience.py - Python validation script

## Deployment Steps

### Step 1: Backup Current Version
```powershell
# Backup current Lambda code
aws lambda get-function --function-name RDSDiscoveryFunction-prod --query 'Code.Location' --output text | Out-File backup-url.txt

# Download current version
$url = Get-Content backup-url.txt
Invoke-WebRequest -Uri $url -OutFile "lambda-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
```

**Status:** [ ] Complete

### Step 2: Deploy Infrastructure
```powershell
cd rds-operations-dashboard/infrastructure

# Deploy compute stack (includes Lambda)
npx cdk deploy RDSComputeStack-prod --require-approval never
```

**Status:** [ ] Complete

**Expected Output:**
- ✓ Lambda function updated
- ✓ No errors during deployment
- ✓ Stack status: UPDATE_COMPLETE

### Step 3: Verify Deployment
```powershell
# Check Lambda version
aws lambda get-function --function-name RDSDiscoveryFunction-prod --query 'Configuration.LastModified'

# Check Lambda environment
aws lambda get-function-configuration --function-name RDSDiscoveryFunction-prod
```

**Status:** [ ] Complete

**Verify:**
- [ ] LastModified timestamp is recent
- [ ] Environment variables are correct
- [ ] Timeout is adequate (300s recommended)
- [ ] Memory is adequate (512MB recommended)

## Post-Deployment Testing

### Test 1: Invoke Lambda
```powershell
cd rds-operations-dashboard
.\test-discovery-resilience.ps1
```

**Status:** [ ] Complete

**Expected Results:**
- [ ] Lambda returns HTTP 200
- [ ] total_instances >= 0
- [ ] accounts_attempted >= 1
- [ ] accounts_scanned >= 1
- [ ] Errors have proper structure (if any)
- [ ] Execution status is set
- [ ] Discovery timestamp is present

### Test 2: Check CloudWatch Logs
```powershell
# View recent logs
aws logs tail /aws/lambda/RDSDiscoveryFunction-prod --follow --since 5m
```

**Status:** [ ] Complete

**Verify:**
- [ ] Structured logging is working
- [ ] No unexpected errors
- [ ] Success metrics logged
- [ ] Error details logged (if any)

### Test 3: Check DynamoDB
```powershell
# Check inventory table
aws dynamodb scan --table-name rds-inventory-prod --select COUNT
```

**Status:** [ ] Complete

**Verify:**
- [ ] Instances are being persisted
- [ ] Count matches discovery results
- [ ] Timestamps are recent

### Test 4: Check CloudWatch Metrics
```powershell
# Check custom metrics
aws cloudwatch get-metric-statistics `
  --namespace RDSDashboard `
  --metric-name InstancesDiscovered `
  --start-time (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
  --period 3600 `
  --statistics Sum
```

**Status:** [ ] Complete

**Verify:**
- [ ] Metrics are being published
- [ ] Values are reasonable
- [ ] No gaps in data

## Monitoring Setup

### CloudWatch Alarms

#### Alarm 1: No Accounts Scanned (Critical)
```powershell
aws cloudwatch put-metric-alarm `
  --alarm-name "RDS-Discovery-NoAccountsScanned" `
  --alarm-description "Alert when discovery finds no accounts" `
  --metric-name AccountsScanned `
  --namespace RDSDashboard `
  --statistic Sum `
  --period 900 `
  --evaluation-periods 1 `
  --threshold 1 `
  --comparison-operator LessThanThreshold `
  --treat-missing-data notBreaching
```

**Status:** [ ] Complete

#### Alarm 2: High Error Rate (Warning)
```powershell
aws cloudwatch put-metric-alarm `
  --alarm-name "RDS-Discovery-HighErrorRate" `
  --alarm-description "Alert when error rate exceeds 50%" `
  --metric-name ErrorCount `
  --namespace RDSDashboard `
  --statistic Sum `
  --period 900 `
  --evaluation-periods 2 `
  --threshold 5 `
  --comparison-operator GreaterThanThreshold `
  --treat-missing-data notBreaching
```

**Status:** [ ] Complete

#### Alarm 3: Lambda Failures (Critical)
```powershell
aws cloudwatch put-metric-alarm `
  --alarm-name "RDS-Discovery-LambdaFailures" `
  --alarm-description "Alert on Lambda execution failures" `
  --metric-name Errors `
  --namespace AWS/Lambda `
  --dimensions Name=FunctionName,Value=RDSDiscoveryFunction-prod `
  --statistic Sum `
  --period 300 `
  --evaluation-periods 1 `
  --threshold 1 `
  --comparison-operator GreaterThanOrEqualToThreshold
```

**Status:** [ ] Complete

### Log Insights Queries

#### Query 1: Error Summary
```sql
fields @timestamp, level, message, account_id, region, error_type
| filter level = "ERROR"
| stats count() by error_type
| sort count desc
```

**Status:** [ ] Saved to CloudWatch Insights

#### Query 2: Success Rate
```sql
fields accounts_scanned, accounts_attempted
| filter accounts_attempted > 0
| stats latest(accounts_scanned) / latest(accounts_attempted) * 100 as success_rate
```

**Status:** [ ] Saved to CloudWatch Insights

#### Query 3: Discovery Performance
```sql
fields @timestamp, total_instances, accounts_scanned, regions_scanned, @duration
| sort @timestamp desc
| limit 20
```

**Status:** [ ] Saved to CloudWatch Insights

## Rollback Plan

### If Issues Occur

#### Option 1: Rollback Lambda Code
```powershell
# Restore from backup
aws lambda update-function-code `
  --function-name RDSDiscoveryFunction-prod `
  --zip-file fileb://lambda-backup-YYYYMMDD-HHmmss.zip
```

#### Option 2: Rollback CDK Stack
```powershell
cd rds-operations-dashboard/infrastructure

# Rollback to previous version
npx cdk deploy RDSComputeStack-prod --rollback
```

#### Option 3: Disable Lambda
```powershell
# Disable EventBridge trigger
aws events disable-rule --name RDSDiscoverySchedule-prod
```

## Validation Checklist

### Functional Validation
- [ ] Lambda executes successfully
- [ ] Instances are discovered
- [ ] Errors are handled gracefully
- [ ] Persistence works
- [ ] Metrics are published

### Resilience Validation
- [ ] Account failures don't stop Lambda
- [ ] Region failures don't stop Lambda
- [ ] Instance failures don't stop Lambda
- [ ] Lambda always returns 200 (unless catastrophic)
- [ ] Errors include remediation steps

### Performance Validation
- [ ] Execution time is reasonable (< 5 minutes)
- [ ] Memory usage is acceptable (< 512MB)
- [ ] No timeouts
- [ ] Parallel execution works

### Monitoring Validation
- [ ] CloudWatch Logs show structured logging
- [ ] CloudWatch Metrics are published
- [ ] Alarms are configured
- [ ] Log Insights queries work

## Communication

### Team Notification
```
Subject: Discovery Lambda Resilience Enhancement Deployed

The Discovery Lambda has been enhanced with comprehensive error isolation:

✓ Account failures are isolated
✓ Region failures are isolated
✓ Instance failures are isolated
✓ Lambda always succeeds (returns 200)
✓ All errors include remediation steps

Key Changes:
- Multi-level error handling
- Graceful degradation
- Detailed error reporting
- Success rate tracking

Documentation:
- Quick Reference: DISCOVERY-QUICK-REFERENCE.md
- Detailed Architecture: DISCOVERY-RESILIENCE.md
- Visual Flow: docs/discovery-resilience-flow.md

Testing:
- Run: .\test-discovery-resilience.ps1
- Validate: python validate-discovery-resilience.py

Monitoring:
- CloudWatch Alarms configured
- Log Insights queries saved
- Metrics dashboard updated

Questions? See documentation or contact [your-name]
```

**Status:** [ ] Sent

## Sign-Off

### Deployment Completed By
- Name: ___________________________
- Date: ___________________________
- Time: ___________________________

### Validation Completed By
- Name: ___________________________
- Date: ___________________________
- Time: ___________________________

### Approved By
- Name: ___________________________
- Date: ___________________________
- Time: ___________________________

## Notes

### Deployment Notes
```
[Add any notes about the deployment process]
```

### Issues Encountered
```
[Document any issues and how they were resolved]
```

### Follow-Up Actions
```
[List any follow-up actions needed]
```

## Success Criteria

- [x] Code validated and tested
- [ ] Deployment successful
- [ ] Post-deployment tests pass
- [ ] Monitoring configured
- [ ] Team notified
- [ ] Documentation updated
- [ ] Sign-off obtained

## Status: [ ] READY FOR DEPLOYMENT

---

**Deployment Date:** _______________
**Deployment Status:** _______________
**Rollback Required:** [ ] Yes [ ] No
