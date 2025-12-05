# Migration Guide: Environment-Based to Centralized Deployment

**Version:** 1.0.0  
**Last Updated:** 2025-11-23  
**Purpose:** Guide for migrating from environment-based deployment to centralized deployment model

## Overview

This guide helps you migrate from the old environment-based deployment model (separate dev/staging/prod deployments) to the new centralized deployment model (single dashboard monitoring all RDS instances).

## What Changed

### Old Model (Environment-Based Deployment)

```
Management Account:
├── RDSDashboard-Data-dev
├── RDSDashboard-Compute-dev
├── RDSDashboard-API-dev
├── RDSDashboard-Data-staging
├── RDSDashboard-Compute-staging
├── RDSDashboard-API-staging
├── RDSDashboard-Data-prod
├── RDSDashboard-Compute-prod
└── RDSDashboard-API-prod

Resources:
- rds-inventory-dev
- rds-inventory-staging
- rds-inventory-prod
- rds-discovery-dev
- rds-discovery-staging
- rds-discovery-prod
```

### New Model (Centralized Deployment)

```
Management Account:
├── RDSDashboard-Data
├── RDSDashboard-Compute
├── RDSDashboard-API
├── RDSDashboard-Auth
├── RDSDashboard-BFF
├── RDSDashboard-Orchestration
└── RDSDashboard-Monitoring

Resources:
- rds-inventory (single table for all RDS instances)
- metrics-cache
- health-alerts
- rds-discovery (single Lambda)
- rds-operations (single Lambda)
```

## Migration Steps

### Phase 1: Preparation (1 hour)

#### 1.1 Backup Existing Data

Export data from your existing DynamoDB tables:

```bash
# Export production inventory
aws dynamodb scan \
  --table-name rds-inventory-prod \
  --region ap-southeast-1 \
  --output json > rds-inventory-prod-backup.json

# Export staging inventory
aws dynamodb scan \
  --table-name rds-inventory-staging \
  --region ap-southeast-1 \
  --output json > rds-inventory-staging-backup.json

# Export dev inventory
aws dynamodb scan \
  --table-name rds-inventory-dev \
  --region ap-southeast-1 \
  --output json > rds-inventory-dev-backup.json
```

#### 1.2 Document Current Configuration

```bash
# Export CloudFormation stack outputs
aws cloudformation describe-stacks \
  --stack-name RDSDashboard-Data-prod \
  --region ap-southeast-1 \
  --output json > stack-outputs-prod.json

aws cloudformation describe-stacks \
  --stack-name RDSDashboard-Data-staging \
  --region ap-southeast-1 \
  --output json > stack-outputs-staging.json

aws cloudformation describe-stacks \
  --stack-name RDSDashboard-Data-dev \
  --region ap-southeast-1 \
  --output json > stack-outputs-dev.json
```

#### 1.3 Verify RDS Instance Tags

Ensure all RDS instances have the `Environment` tag:

```bash
# Check RDS instances in production account
aws rds describe-db-instances \
  --region ap-southeast-1 \
  --query 'DBInstances[*].[DBInstanceIdentifier,TagList[?Key==`Environment`].Value|[0]]' \
  --output table

# If any instances are missing the Environment tag, add it:
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:ap-southeast-1:123456789012:db:my-instance \
  --tags Key=Environment,Value=Production
```

### Phase 2: Deploy New Centralized Infrastructure (30 minutes)

#### 2.1 Pull Latest Code

```bash
cd rds-operations-dashboard
git pull origin main
```

#### 2.2 Deploy New Stacks

```bash
# Deploy all new stacks
cd scripts
./deploy-all.ps1

# Or deploy individually
cd ../infrastructure
cdk deploy RDSDashboard-Data
cdk deploy RDSDashboard-IAM
cdk deploy RDSDashboard-Compute
cdk deploy RDSDashboard-API
cdk deploy RDSDashboard-Auth
cdk deploy RDSDashboard-BFF
cdk deploy RDSDashboard-Orchestration
cdk deploy RDSDashboard-Monitoring
```

#### 2.3 Initialize S3 Bucket

```bash
cd ../scripts
./setup-s3-structure.ps1 -AccountId YOUR_ACCOUNT_ID
```

### Phase 3: Data Migration (30 minutes)

#### 3.1 Merge Inventory Data

The new centralized model stores all RDS instances in a single `rds-inventory` table. Merge your existing data:

```python
# merge-inventory.py
import boto3
import json

dynamodb = boto3.resource('dynamodb', region_name='ap-southeast-1')
new_table = dynamodb.Table('rds-inventory')

# Load backup files
with open('rds-inventory-prod-backup.json') as f:
    prod_data = json.load(f)

with open('rds-inventory-staging-backup.json') as f:
    staging_data = json.load(f)

with open('rds-inventory-dev-backup.json') as f:
    dev_data = json.load(f)

# Merge and write to new table
for item in prod_data['Items'] + staging_data['Items'] + dev_data['Items']:
    new_table.put_item(Item=item)

print("Migration complete!")
```

Run the migration:

```bash
python merge-inventory.py
```

#### 3.2 Verify Data Migration

```bash
# Check item count in new table
aws dynamodb describe-table \
  --table-name rds-inventory \
  --region ap-southeast-1 \
  --query 'Table.ItemCount'

# Sample some items
aws dynamodb scan \
  --table-name rds-inventory \
  --region ap-southeast-1 \
  --max-items 5
```

### Phase 4: Update Cross-Account Roles (15 minutes)

Update trust relationships in target accounts to reference the new role names:

```bash
# Update cross-account role in each target account
aws cloudformation update-stack \
  --stack-name RDSDashboard-CrossAccountRole \
  --template-body file://cross-account-role.yaml \
  --parameters \
    ParameterKey=ManagementAccountId,ParameterValue=123456789012 \
    ParameterKey=LambdaRoleName,ParameterValue=RDSDashboardLambdaRole \
    ParameterKey=ExternalId,ParameterValue=YOUR_EXTERNAL_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region ap-southeast-1 \
  --profile target-account
```

### Phase 5: Update Frontend Configuration (10 minutes)

#### 5.1 Update API Endpoint

Get the new API Gateway endpoint:

```bash
aws cloudformation describe-stacks \
  --stack-name RDSDashboard-API \
  --region ap-southeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text
```

Update frontend `.env`:

```bash
# Old
REACT_APP_API_URL=https://abc123-prod.execute-api.ap-southeast-1.amazonaws.com/prod

# New
REACT_APP_API_URL=https://xyz789.execute-api.ap-southeast-1.amazonaws.com/api
```

#### 5.2 Redeploy Frontend

```bash
cd frontend
npm run build
aws s3 sync build/ s3://rds-dashboard-frontend-YOUR_ACCOUNT_ID/
```

### Phase 6: Testing (30 minutes)

#### 6.1 Test Discovery

Trigger the discovery Lambda manually:

```bash
aws lambda invoke \
  --function-name rds-discovery \
  --region ap-southeast-1 \
  --payload '{}' \
  response.json

cat response.json
```

#### 6.2 Test Dashboard

1. Open the dashboard URL
2. Verify all RDS instances are visible
3. Check that instances are correctly classified by environment
4. Test filtering by environment (Production, Development, etc.)

#### 6.3 Test Operations

1. Try starting/stopping a non-production RDS instance
2. Verify authorization works based on RDS instance environment
3. Check audit logs in DynamoDB

### Phase 7: Decommission Old Stacks (15 minutes)

Once you've verified everything works:

#### 7.1 Delete Old Stacks

```bash
# Delete old environment-specific stacks
cdk destroy RDSDashboard-Data-prod
cdk destroy RDSDashboard-Compute-prod
cdk destroy RDSDashboard-API-prod

cdk destroy RDSDashboard-Data-staging
cdk destroy RDSDashboard-Compute-staging
cdk destroy RDSDashboard-API-staging

cdk destroy RDSDashboard-Data-dev
cdk destroy RDSDashboard-Compute-dev
cdk destroy RDSDashboard-API-dev
```

#### 7.2 Clean Up Old Resources

```bash
# Delete old DynamoDB tables (after confirming data migration)
aws dynamodb delete-table --table-name rds-inventory-prod
aws dynamodb delete-table --table-name rds-inventory-staging
aws dynamodb delete-table --table-name rds-inventory-dev

# Delete old S3 buckets (after backing up any important data)
aws s3 rb s3://rds-dashboard-data-123456789012-prod --force
aws s3 rb s3://rds-dashboard-data-123456789012-staging --force
aws s3 rb s3://rds-dashboard-data-123456789012-dev --force
```

## Rollback Plan

If you need to rollback to the old environment-based deployment:

### 1. Restore Old Stacks

```bash
# Redeploy old stacks from backup
git checkout <old-commit-hash>
cd infrastructure
cdk deploy --all --context environment=prod
```

### 2. Restore Data

```bash
# Restore DynamoDB data from backups
python restore-inventory.py --backup rds-inventory-prod-backup.json --table rds-inventory-prod
```

### 3. Update Frontend

```bash
# Revert frontend configuration
cd frontend
git checkout .env
npm run build
aws s3 sync build/ s3://rds-dashboard-frontend-prod-YOUR_ACCOUNT_ID/
```

## Troubleshooting

### Issue: RDS instances not appearing in dashboard

**Cause:** Discovery Lambda hasn't run yet or failed

**Solution:**
```bash
# Manually trigger discovery
aws lambda invoke \
  --function-name rds-discovery \
  --region ap-southeast-1 \
  --payload '{}' \
  response.json

# Check logs
aws logs tail /aws/lambda/rds-discovery --follow
```

### Issue: Authorization errors when performing operations

**Cause:** Cross-account roles not updated

**Solution:**
- Verify cross-account role trust relationships
- Check that role names match new naming convention (no `-prod` suffix)
- Verify External ID is correct

### Issue: Missing environment classification

**Cause:** RDS instances missing `Environment` tag

**Solution:**
```bash
# Add Environment tag to RDS instances
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:REGION:ACCOUNT:db:INSTANCE_ID \
  --tags Key=Environment,Value=Production
```

## Post-Migration Checklist

- [ ] All RDS instances visible in dashboard
- [ ] Environment classification working correctly
- [ ] Operations (start/stop/reboot) working
- [ ] Authorization based on RDS instance environment
- [ ] Health monitoring active
- [ ] Cost analysis running
- [ ] Compliance checks passing
- [ ] CloudOps request generation working
- [ ] Audit logs being written
- [ ] Old stacks decommissioned
- [ ] Old resources cleaned up
- [ ] Documentation updated
- [ ] Team trained on new model

## Benefits of Centralized Deployment

✅ **Simplified Management:** Single deployment to maintain instead of 3+  
✅ **Reduced Costs:** Fewer Lambda functions, API Gateways, and resources  
✅ **Unified View:** All RDS instances in one dashboard  
✅ **Easier Updates:** Deploy once instead of to multiple environments  
✅ **Better Resource Utilization:** Shared infrastructure across all RDS instances  
✅ **Consistent Authorization:** Based on RDS instance environment, not deployment  

## Support

For migration assistance:
- Review [Deployment Guide](./deployment.md)
- Check [Environment Classification Guide](./environment-classification.md)
- Contact DBA team or AWS support

## Timeline Summary

| Phase | Duration | Can Run in Parallel? |
|-------|----------|---------------------|
| 1. Preparation | 1 hour | No |
| 2. Deploy New Infrastructure | 30 min | No |
| 3. Data Migration | 30 min | No |
| 4. Update Cross-Account Roles | 15 min | Yes (per account) |
| 5. Update Frontend | 10 min | No |
| 6. Testing | 30 min | No |
| 7. Decommission Old Stacks | 15 min | Yes (per stack) |
| **Total** | **~3 hours** | |

**Recommended:** Perform migration during a maintenance window to minimize disruption.
