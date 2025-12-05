# Deployment Guide - Latest Changes

**Date:** November 23, 2025  
**Changes:** Monitoring Dashboards + Approval Workflow System  
**Risk Level:** Medium (New features, no breaking changes)

## Overview

This guide covers deploying the latest enhancements to the RDS Operations Dashboard:
1. **Monitoring Dashboards** - Real-time compute and connection monitoring
2. **Approval Workflow System** - Risk-based approval for high-risk operations

## Pre-Deployment Checklist

### 1. Environment Verification

```powershell
# Verify AWS credentials
aws sts get-caller-identity

# Verify CDK version
cdk --version

# Verify Node.js version
node --version  # Should be 18.x or higher

# Verify Python version
python --version  # Should be 3.11 or higher
```

### 2. Configuration Review

```powershell
# Review dashboard config
cat rds-operations-dashboard/config/dashboard-config.json

# Verify environment variables
cat rds-operations-dashboard/frontend/.env
```

### 3. Dependencies Check

```powershell
# Install/update CDK dependencies
cd rds-operations-dashboard/infrastructure
npm install

# Install/update BFF dependencies
cd ../bff
npm install

# Install/update frontend dependencies
cd ../frontend
npm install
```

## Deployment Steps

### Step 1: Deploy Infrastructure Changes

**What's Being Deployed:**
- New DynamoDB table: `rds-approvals-{env}`
- New Lambda function: `rds-approval-workflow-{env}`
- New Lambda function: `rds-monitoring-{env}`
- Updated IAM permissions
- New API Gateway endpoints

```powershell
cd rds-operations-dashboard/infrastructure

# Synthesize CloudFormation templates
cdk synth

# Review changes (IMPORTANT!)
cdk diff RDSDashboard-Data-dev
cdk diff RDSDashboard-IAM-dev
cdk diff RDSDashboard-Compute-dev
cdk diff RDSDashboard-API-dev

# Deploy Data Stack (new approvals table)
cdk deploy RDSDashboard-Data-dev --require-approval never

# Deploy IAM Stack (updated permissions)
cdk deploy RDSDashboard-IAM-dev --require-approval never

# Deploy Compute Stack (new Lambda functions)
cdk deploy RDSDashboard-Compute-dev --require-approval never

# Deploy API Stack (new endpoints)
cdk deploy RDSDashboard-API-dev --require-approval never
```

**Expected Output:**
```
✅ RDSDashboard-Data-dev
   - Created: rds-approvals-dev table
   - Created: 3 GSIs for approvals table

✅ RDSDashboard-IAM-dev
   - Updated: Lambda execution role permissions

✅ RDSDashboard-Compute-dev
   - Created: rds-approval-workflow-dev function
   - Created: rds-monitoring-dev function

✅ RDSDashboard-API-dev
   - Created: /approvals endpoint
   - Created: /monitoring endpoint
```

### Step 2: Deploy BFF Changes

**What's Being Deployed:**
- New approval workflow routes
- New monitoring routes
- Updated audit logging

```powershell
cd rds-operations-dashboard/bff

# Build TypeScript
npm run build

# Test locally (optional)
npm run dev

# Deploy to your hosting service
# Example for AWS Elastic Beanstalk:
eb deploy rds-dashboard-bff-dev

# Example for EC2/ECS:
# Build Docker image
docker build -t rds-dashboard-bff:latest .

# Push to ECR
aws ecr get-login-password --region ap-southeast-1 | docker login --username AWS --password-stdin YOUR_ECR_URL
docker tag rds-dashboard-bff:latest YOUR_ECR_URL/rds-dashboard-bff:latest
docker push YOUR_ECR_URL/rds-dashboard-bff:latest

# Update ECS service
aws ecs update-service --cluster rds-dashboard --service bff --force-new-deployment
```

### Step 3: Deploy Frontend Changes

**What's Being Deployed:**
- New ApprovalsDashboard page
- New ComputeMonitoring page
- New ConnectionMonitoring page
- Updated navigation
- Updated routing

```powershell
cd rds-operations-dashboard/frontend

# Build production bundle
npm run build

# Test build locally (optional)
npm run preview

# Deploy to S3 + CloudFront
aws s3 sync dist/ s3://your-frontend-bucket/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"

# Alternative: Deploy to hosting service
# Netlify:
# netlify deploy --prod

# Vercel:
# vercel --prod
```

### Step 4: Verify Deployment

```powershell
# Test infrastructure
cd rds-operations-dashboard

# Test approval workflow Lambda
aws lambda invoke --function-name rds-approval-workflow-dev \
  --payload '{"body":"{\"operation\":\"get_pending_approvals\"}"}' \
  response.json

# Test monitoring Lambda
aws lambda invoke --function-name rds-monitoring-dev \
  --payload '{"body":"{\"operation\":\"get_real_time_status\",\"instance_id\":\"test\"}"}' \
  response.json

# Test API Gateway
curl -X POST https://YOUR_API_URL/prod/approvals \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"operation":"get_pending_approvals"}'

# Test BFF
curl https://YOUR_BFF_URL/health

# Test Frontend
curl https://YOUR_FRONTEND_URL
```

## Post-Deployment Verification

### 1. Smoke Tests

**Test Monitoring Dashboards:**
1. Login to dashboard
2. Navigate to an instance detail page
3. Click "Compute Monitoring"
4. Verify metrics load
5. Click "Connection Monitoring"
6. Verify connection data loads

**Test Approval Workflow:**
1. Navigate to Approvals page
2. Verify pending approvals tab loads
3. Verify my requests tab loads
4. Create a test approval request (if possible)
5. Approve/reject a request
6. Verify status updates

### 2. Integration Tests

```powershell
# Run integration test script
cd rds-operations-dashboard
./scripts/test-deployment.ps1
```

### 3. Monitor Logs

```powershell
# Monitor Lambda logs
aws logs tail /aws/lambda/rds-approval-workflow-dev --follow
aws logs tail /aws/lambda/rds-monitoring-dev --follow

# Monitor API Gateway logs
aws logs tail API-Gateway-Execution-Logs_YOUR_API_ID/prod --follow

# Monitor BFF logs (depends on hosting)
# For ECS:
aws logs tail /ecs/rds-dashboard-bff --follow
```

### 4. Check CloudWatch Metrics

```powershell
# Check Lambda invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=rds-approval-workflow-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Check Lambda errors
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=rds-approval-workflow-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Rollback Plan

### If Issues Occur

**Rollback Infrastructure:**
```powershell
cd rds-operations-dashboard/infrastructure

# Rollback to previous version
cdk deploy RDSDashboard-Compute-dev --rollback

# Or destroy new resources
# Note: This will delete the approvals table!
# cdk destroy RDSDashboard-Compute-dev
```

**Rollback BFF:**
```powershell
# Revert to previous deployment
eb deploy rds-dashboard-bff-dev --version PREVIOUS_VERSION

# Or for ECS:
aws ecs update-service --cluster rds-dashboard --service bff \
  --task-definition rds-dashboard-bff:PREVIOUS_REVISION
```

**Rollback Frontend:**
```powershell
# Restore previous S3 version
aws s3 sync s3://your-frontend-bucket-backup/ s3://your-frontend-bucket/ --delete

# Invalidate CloudFront
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

## Environment-Specific Configurations

### Development Environment

```bash
ENVIRONMENT=dev
AWS_REGION=ap-southeast-1
ALERT_EMAIL=dev-team@example.com
```

### Staging Environment

```bash
ENVIRONMENT=staging
AWS_REGION=ap-southeast-1
ALERT_EMAIL=staging-alerts@example.com
```

### Production Environment

```bash
ENVIRONMENT=prod
AWS_REGION=ap-southeast-1
ALERT_EMAIL=ops-team@example.com
```

## Troubleshooting

### Issue: Lambda Function Not Found

**Solution:**
```powershell
# Verify function exists
aws lambda get-function --function-name rds-approval-workflow-dev

# If not found, redeploy compute stack
cd infrastructure
cdk deploy RDSDashboard-Compute-dev --force
```

### Issue: DynamoDB Table Not Found

**Solution:**
```powershell
# Verify table exists
aws dynamodb describe-table --table-name rds-approvals-dev

# If not found, redeploy data stack
cd infrastructure
cdk deploy RDSDashboard-Data-dev --force
```

### Issue: API Gateway 403 Errors

**Solution:**
```powershell
# Verify API key
aws apigateway get-api-keys --include-values

# Test with correct API key
curl -X POST https://YOUR_API_URL/prod/approvals \
  -H "x-api-key: CORRECT_API_KEY" \
  -d '{"operation":"get_pending_approvals"}'
```

### Issue: Frontend Not Loading

**Solution:**
```powershell
# Check S3 bucket
aws s3 ls s3://your-frontend-bucket/

# Check CloudFront distribution
aws cloudfront get-distribution --id YOUR_DIST_ID

# Verify environment variables
cat frontend/.env
```

### Issue: BFF Connection Errors

**Solution:**
```powershell
# Check BFF health
curl https://YOUR_BFF_URL/health

# Check environment variables
# Verify INTERNAL_API_URL and INTERNAL_API_KEY are set

# Check logs
aws logs tail /ecs/rds-dashboard-bff --follow
```

## Performance Monitoring

### Key Metrics to Watch

1. **Lambda Duration:**
   - Approval Workflow: < 3 seconds
   - Monitoring: < 5 seconds

2. **API Gateway Latency:**
   - P50: < 500ms
   - P99: < 2000ms

3. **DynamoDB Throttling:**
   - Should be 0

4. **Frontend Load Time:**
   - First Contentful Paint: < 2s
   - Time to Interactive: < 4s

### Set Up Alarms

```powershell
# Create CloudWatch alarm for Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name rds-approval-workflow-errors \
  --alarm-description "Alert on approval workflow errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=rds-approval-workflow-dev
```

## Security Checklist

- [ ] API keys rotated
- [ ] IAM permissions follow least privilege
- [ ] Secrets stored in Secrets Manager
- [ ] HTTPS enforced
- [ ] CORS configured correctly
- [ ] Authentication enabled
- [ ] Authorization checks in place
- [ ] Audit logging enabled
- [ ] Encryption at rest enabled
- [ ] Encryption in transit enabled

## Compliance Checklist

- [ ] Audit trail complete
- [ ] Data retention policies configured
- [ ] Backup strategy in place
- [ ] Disaster recovery tested
- [ ] Documentation updated
- [ ] Change management approved
- [ ] Security review completed
- [ ] Performance testing done

## Success Criteria

✅ All infrastructure stacks deployed successfully  
✅ All Lambda functions responding  
✅ API Gateway endpoints accessible  
✅ BFF health check passing  
✅ Frontend loading correctly  
✅ Monitoring dashboards displaying data  
✅ Approval workflow functional  
✅ No errors in CloudWatch logs  
✅ Performance metrics within targets  
✅ Security scans passing  

## Next Steps

1. **User Acceptance Testing:**
   - Schedule UAT sessions with DBAs
   - Gather feedback
   - Document issues

2. **Documentation:**
   - Update user guides
   - Create video tutorials
   - Update API documentation

3. **Training:**
   - Conduct training sessions
   - Create knowledge base articles
   - Set up support channels

4. **Monitoring:**
   - Set up dashboards
   - Configure alerts
   - Establish on-call rotation

5. **Optimization:**
   - Review performance metrics
   - Optimize slow queries
   - Tune Lambda memory/timeout
   - Implement caching strategies

## Support

**For Issues:**
- Check CloudWatch logs
- Review this deployment guide
- Contact DevOps team
- Create incident ticket

**For Questions:**
- Refer to user documentation
- Check FAQ
- Contact support team

---

**Deployment Completed:** [DATE]  
**Deployed By:** [NAME]  
**Environment:** [dev/staging/prod]  
**Version:** [VERSION]  
**Status:** [SUCCESS/FAILED/PARTIAL]
