# Disaster Recovery Runbook

**Document Version:** 1.0.0  
**Last Updated:** December 4, 2025  
**Owner:** DBA Team  
**Review Frequency:** Quarterly

## Overview

This runbook provides step-by-step procedures for recovering the RDS Operations Dashboard from various disaster scenarios. All DynamoDB tables (except metrics-cache) have Point-in-Time Recovery (PITR) enabled with 35-day retention.

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Component | RTO | RPO | Notes |
|-----------|-----|-----|-------|
| DynamoDB Tables | 2 hours | 5 minutes | PITR enabled, continuous backups |
| Lambda Functions | 30 minutes | 0 (code in Git) | Redeploy from CDK |
| API Gateway | 30 minutes | 0 (IaC) | Redeploy from CDK |
| S3 Data Bucket | 1 hour | 0 (versioned) | Versioning enabled |
| Frontend | 15 minutes | 0 (code in Git) | Redeploy from Git |

## Scenarios

### Scenario 1: Accidental DynamoDB Table Deletion

**Impact:** Loss of inventory, alerts, audit logs, or cost data  
**Detection:** CloudWatch alarms, user reports, API errors

#### Recovery Steps

1. **Identify the deleted table and deletion time**
   ```bash
   # Check CloudTrail for DeleteTable events
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteTable \
     --max-results 10
   ```

2. **Restore table from PITR**
   ```bash
   # Restore to a specific point in time (within last 35 days)
   aws dynamodb restore-table-to-point-in-time \
     --source-table-name rds-inventory \
     --target-table-name rds-inventory-restored \
     --restore-date-time "2025-12-04T10:00:00Z"
   ```

3. **Wait for restore to complete**
   ```bash
   # Monitor restore status
   aws dynamodb describe-table \
     --table-name rds-inventory-restored \
     --query 'Table.TableStatus'
   ```

4. **Verify restored data**
   ```bash
   # Check item count
   aws dynamodb describe-table \
     --table-name rds-inventory-restored \
     --query 'Table.ItemCount'
   
   # Sample a few items
   aws dynamodb scan \
     --table-name rds-inventory-restored \
     --max-items 5
   ```

5. **Update application to use restored table**
   - Option A: Rename tables (requires downtime)
     ```bash
     # Delete the empty table (if it was recreated)
     aws dynamodb delete-table --table-name rds-inventory
     
     # Wait for deletion
     aws dynamodb wait table-not-exists --table-name rds-inventory
     
     # Rename restored table (not directly supported, requires data migration)
     # Use AWS Data Pipeline or custom script
     ```
   
   - Option B: Update CDK and redeploy (recommended)
     ```typescript
     // Update data-stack.ts to use restored table name
     tableName: 'rds-inventory-restored'
     ```
     ```bash
     cd infrastructure
     npm run build
     cdk deploy DataStack
     ```

6. **Re-enable PITR on restored table**
   ```bash
   aws dynamodb update-continuous-backups \
     --table-name rds-inventory-restored \
     --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
   ```

7. **Verify application functionality**
   - Test discovery endpoint
   - Check dashboard displays data
   - Verify alerts are working

**Estimated Recovery Time:** 1-2 hours

---

### Scenario 2: Data Corruption in DynamoDB

**Impact:** Incorrect or corrupted data in tables  
**Detection:** Data validation errors, user reports, anomalous metrics

#### Recovery Steps

1. **Identify corruption time window**
   - Review CloudWatch logs for error patterns
   - Check audit logs for suspicious operations
   - Determine last known good state

2. **Create backup of current state (for forensics)**
   ```bash
   # Export current table to S3
   aws dynamodb export-table-to-point-in-time \
     --table-arn arn:aws:dynamodb:us-east-1:ACCOUNT:table/rds-inventory \
     --s3-bucket rds-dashboard-data-ACCOUNT \
     --s3-prefix backups/corrupted-$(date +%Y%m%d) \
     --export-format DYNAMODB_JSON
   ```

3. **Restore to point before corruption**
   ```bash
   # Restore to specific timestamp
   aws dynamodb restore-table-to-point-in-time \
     --source-table-name rds-inventory \
     --target-table-name rds-inventory-clean \
     --restore-date-time "2025-12-03T23:00:00Z"
   ```

4. **Compare corrupted vs clean data**
   ```python
   # Use Python script to identify differences
   import boto3
   
   dynamodb = boto3.resource('dynamodb')
   corrupted = dynamodb.Table('rds-inventory')
   clean = dynamodb.Table('rds-inventory-clean')
   
   # Compare item counts, sample data, etc.
   ```

5. **Switch to clean table** (follow steps from Scenario 1)

6. **Root cause analysis**
   - Review application logs
   - Check for code bugs
   - Verify IAM permissions
   - Document findings

**Estimated Recovery Time:** 2-4 hours

---

### Scenario 3: Complete Stack Deletion

**Impact:** All infrastructure destroyed  
**Detection:** CloudFormation stack deletion event, complete service outage

#### Recovery Steps

1. **Verify Git repository is intact**
   ```bash
   git clone https://github.com/your-org/rds-operations-dashboard.git
   cd rds-operations-dashboard
   git log --oneline -10
   ```

2. **Check if DynamoDB tables still exist**
   ```bash
   # Tables with RETAIN policy should still exist
   aws dynamodb list-tables | grep rds
   ```

3. **Restore S3 bucket if deleted**
   ```bash
   # Check if bucket exists
   aws s3 ls s3://rds-dashboard-data-ACCOUNT
   
   # If deleted, versioning should have prevented data loss
   # Contact AWS Support for bucket recovery
   ```

4. **Redeploy infrastructure from CDK**
   ```bash
   cd infrastructure
   npm install
   npm run build
   
   # Deploy all stacks
   cdk deploy --all --require-approval never
   ```

5. **Verify table connections**
   - CDK should reconnect to existing tables (RETAIN policy)
   - Check CloudFormation outputs match table names

6. **Redeploy Lambda functions**
   ```bash
   # Lambda code is redeployed with CDK
   # Verify all functions are active
   aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `rds-dashboard`)].FunctionName'
   ```

7. **Redeploy frontend**
   ```bash
   cd frontend
   npm install
   npm run build
   
   # Deploy to S3/CloudFront
   aws s3 sync dist/ s3://rds-dashboard-frontend-ACCOUNT/
   ```

8. **Run smoke tests**
   ```bash
   cd ..
   ./scripts/smoke-test.ps1
   ```

**Estimated Recovery Time:** 1-2 hours

---

### Scenario 4: Lambda Function Failure

**Impact:** Specific functionality unavailable  
**Detection:** CloudWatch alarms, API errors, user reports

#### Recovery Steps

1. **Identify failing function**
   ```bash
   # Check CloudWatch Logs
   aws logs tail /aws/lambda/rds-dashboard-discovery --follow
   ```

2. **Check recent deployments**
   ```bash
   # List function versions
   aws lambda list-versions-by-function \
     --function-name rds-dashboard-discovery
   ```

3. **Rollback to previous version**
   ```bash
   # Update alias to point to previous version
   aws lambda update-alias \
     --function-name rds-dashboard-discovery \
     --name live \
     --function-version 5
   ```

4. **Or redeploy from Git**
   ```bash
   cd infrastructure
   git checkout <last-known-good-commit>
   npm run build
   cdk deploy ComputeStack
   ```

5. **Verify function recovery**
   ```bash
   # Test function
   aws lambda invoke \
     --function-name rds-dashboard-discovery \
     --payload '{"test": true}' \
     response.json
   ```

**Estimated Recovery Time:** 15-30 minutes

---

### Scenario 5: S3 Data Loss

**Impact:** Historical metrics, reports, or CloudOps requests lost  
**Detection:** Missing files, user reports

#### Recovery Steps

1. **Check S3 versioning**
   ```bash
   # List deleted objects
   aws s3api list-object-versions \
     --bucket rds-dashboard-data-ACCOUNT \
     --prefix compliance-reports/ \
     --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}'
   ```

2. **Restore deleted objects**
   ```bash
   # Remove delete marker to restore
   aws s3api delete-object \
     --bucket rds-dashboard-data-ACCOUNT \
     --key compliance-reports/2025-12-01.json \
     --version-id <delete-marker-version-id>
   ```

3. **Restore from previous version**
   ```bash
   # Copy specific version to current
   aws s3api copy-object \
     --bucket rds-dashboard-data-ACCOUNT \
     --copy-source rds-dashboard-data-ACCOUNT/file.json?versionId=<version-id> \
     --key file.json
   ```

4. **Verify restored data**
   ```bash
   aws s3 ls s3://rds-dashboard-data-ACCOUNT/compliance-reports/
   ```

**Estimated Recovery Time:** 30 minutes - 1 hour

---

## Recovery Validation Checklist

After any recovery procedure, complete this checklist:

- [ ] All DynamoDB tables are accessible
- [ ] PITR is enabled on all tables (except metrics-cache)
- [ ] Lambda functions are responding
- [ ] API Gateway endpoints return 200 OK
- [ ] Frontend loads successfully
- [ ] Discovery process completes successfully
- [ ] Cost analysis generates reports
- [ ] Compliance checks run without errors
- [ ] Alerts are being generated
- [ ] Audit logs are being written
- [ ] CloudWatch dashboards show metrics
- [ ] No error alarms are firing

## Escalation Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Primary DBA | [NAME] | 24/7 |
| Secondary DBA | [NAME] | Business hours |
| AWS Support | Enterprise Support | 24/7 |
| DevOps Lead | [NAME] | 24/7 on-call |

## Post-Incident Review

After any disaster recovery event:

1. Document timeline of events
2. Identify root cause
3. Calculate actual RTO/RPO achieved
4. Update runbook with lessons learned
5. Implement preventive measures
6. Test recovery procedures

## Testing Schedule

- **Quarterly:** Test DynamoDB PITR restore
- **Bi-annually:** Full stack redeployment drill
- **Annually:** Complete disaster recovery simulation

## Related Documentation

- [Deployment Guide](./deployment.md)
- [Monitoring Guide](./structured-logging-guide.md)
- [Architecture Documentation](./architecture.md)
- [Cross-Account Setup](./cross-account-setup.md)

---

**Metadata:**
```json
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-04T10:45:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-7.1, REQ-7.5 → DESIGN-DisasterRecovery → TASK-10.1",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
```
