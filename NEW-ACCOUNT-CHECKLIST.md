# New Account Deployment Checklist

Use this checklist when deploying the RDS Operations Dashboard to a new AWS account.

## Pre-Deployment

- [ ] AWS CLI configured with target account credentials
- [ ] Node.js 18+ installed
- [ ] Python 3.11+ installed
- [ ] AWS CDK CLI installed (`npm install -g aws-cdk`)
- [ ] Git repository cloned

## Infrastructure Setup

- [ ] Run `cd infrastructure && npm install`
- [ ] Update `cdk.json` with account/region if needed
- [ ] Run `cdk bootstrap` for the target account/region
- [ ] Run `cdk deploy --all` to create all stacks
- [ ] Note down CloudFront URL from outputs
- [ ] Note down API Gateway URL from outputs

## Account ID Configuration

Choose ONE option:

### Option A: Automatic (Recommended)
- [ ] Run `./scripts/add-account-id-to-cdk.ps1` (Windows) or `./scripts/add-account-id-to-cdk.sh` (Linux/Mac)
- [ ] Review changes: `git diff infrastructure/lib/compute-stack.ts`
- [ ] Redeploy: `cd infrastructure && cdk deploy --all`

### Option B: Manual
- [ ] Get account ID: `aws sts get-caller-identity --query Account --output text`
- [ ] Update each Lambda function:
  ```bash
  aws lambda update-function-configuration \
    --function-name <function-name> \
    --environment "Variables={AWS_ACCOUNT_ID=<your-account-id>}"
  ```
- [ ] Functions to update:
  - [ ] rds-discovery-prod
  - [ ] rds-health-monitor-prod
  - [ ] rds-operations-prod
  - [ ] rds-query-handler-prod
  - [ ] rds-cloudops-generator-prod
  - [ ] rds-compliance-checker-prod
  - [ ] rds-cost-analyzer-prod

## Cognito Setup

- [ ] Create Cognito User Pool:
  ```bash
  aws cognito-idp create-user-pool \
    --pool-name rds-dashboard-users \
    --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true}" \
    --auto-verified-attributes email
  ```
- [ ] Note User Pool ID: `_________________`

- [ ] Create App Client:
  ```bash
  aws cognito-idp create-user-pool-client \
    --user-pool-id <pool-id> \
    --client-name rds-dashboard-client \
    --generate-secret \
    --allowed-o-auth-flows code \
    --allowed-o-auth-scopes openid email profile \
    --callback-urls "<cloudfront-url>/callback" \
    --logout-urls "<cloudfront-url>" \
    --supported-identity-providers COGNITO \
    --allowed-o-auth-flows-user-pool-client
  ```
- [ ] Note Client ID: `_________________`
- [ ] Note Client Secret: `_________________`

- [ ] Create Cognito Domain:
  ```bash
  aws cognito-idp create-user-pool-domain \
    --domain rds-dashboard-<timestamp> \
    --user-pool-id <pool-id>
  ```
- [ ] Note Domain: `_________________`

- [ ] Create user groups:
  - [ ] Admins group
  - [ ] Operators group
  - [ ] Viewers group

## BFF Configuration

- [ ] Update BFF Lambda environment variables:
  ```bash
  aws lambda update-function-configuration \
    --function-name rds-dashboard-bff-prod \
    --environment "Variables={
      COGNITO_USER_POOL_ID=<pool-id>,
      COGNITO_CLIENT_ID=<client-id>,
      COGNITO_DOMAIN=<domain>.auth.<region>.amazoncognito.com,
      COGNITO_REGION=<region>,
      FRONTEND_URL=<cloudfront-url>
    }"
  ```

## Frontend Configuration

- [ ] Create `frontend/.env.production`:
  ```env
  VITE_API_URL=<api-gateway-url>
  VITE_COGNITO_USER_POOL_ID=<pool-id>
  VITE_COGNITO_CLIENT_ID=<client-id>
  VITE_COGNITO_DOMAIN=<domain>.auth.<region>.amazoncognito.com
  VITE_COGNITO_REGION=<region>
  ```

- [ ] Build frontend: `cd frontend && npm install && npm run build`
- [ ] Deploy to S3: `aws s3 sync dist/ s3://<bucket-name>/ --delete`
- [ ] Invalidate CloudFront: `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`

## Initial User Setup

- [ ] Create admin user:
  ```bash
  aws cognito-idp admin-create-user \
    --user-pool-id <pool-id> \
    --username admin@example.com \
    --user-attributes Name=email,Value=admin@example.com Name=email_verified,Value=true
  ```

- [ ] Set password:
  ```bash
  aws cognito-idp admin-set-user-password \
    --user-pool-id <pool-id> \
    --username admin@example.com \
    --password '<secure-password>' \
    --permanent
  ```

- [ ] Add to Admins group:
  ```bash
  aws cognito-idp admin-add-user-to-group \
    --user-pool-id <pool-id> \
    --username admin@example.com \
    --group-name Admins
  ```

## Discovery & Testing

- [ ] Run discovery to populate inventory:
  ```bash
  aws lambda invoke \
    --function-name rds-discovery-prod \
    --payload '{"operation":"discover"}' \
    response.json
  ```

- [ ] Verify inventory has data:
  ```bash
  aws dynamodb scan --table-name rds-inventory --select COUNT
  ```

- [ ] Access dashboard at CloudFront URL
- [ ] Log in with admin credentials
- [ ] Verify instance list loads
- [ ] Click on an instance to view details
- [ ] Test health metrics display
- [ ] Test start/stop operations (if applicable)

## Security Hardening

- [ ] Enable CloudTrail logging
- [ ] Set up CloudWatch alarms for Lambda errors
- [ ] Review IAM policies for least privilege
- [ ] Enable MFA for Cognito users
- [ ] Configure WAF rules (if needed)
- [ ] Set up VPC endpoints (if using private subnets)
- [ ] Enable encryption at rest for DynamoDB tables
- [ ] Enable S3 bucket versioning and encryption

## Monitoring Setup

- [ ] Create CloudWatch dashboard
- [ ] Set up SNS topic for alerts
- [ ] Configure Lambda error alarms
- [ ] Set up API Gateway throttling alerts
- [ ] Monitor DynamoDB capacity

## Documentation

- [ ] Document account ID: `_________________`
- [ ] Document region: `_________________`
- [ ] Document CloudFront URL: `_________________`
- [ ] Document API Gateway URL: `_________________`
- [ ] Document Cognito User Pool ID: `_________________`
- [ ] Document Cognito Client ID: `_________________`
- [ ] Document Cognito Domain: `_________________`
- [ ] Update team wiki/documentation
- [ ] Share credentials securely with team

## Post-Deployment Validation

- [ ] All Lambda functions have AWS_ACCOUNT_ID set
- [ ] Frontend loads without errors
- [ ] Authentication works
- [ ] Instance list displays
- [ ] Health metrics load
- [ ] Operations (start/stop) work
- [ ] Compliance checks run
- [ ] Cost analysis displays
- [ ] Audit logs are being created

## Troubleshooting

If you encounter issues:

1. **500 errors on operations**: Check AWS_ACCOUNT_ID is set on Lambda functions
2. **Auth redirect errors**: Verify Cognito callback URLs match CloudFront URL
3. **No instances showing**: Run discovery Lambda manually
4. **Health metrics not loading**: Check health-monitor Lambda logs
5. **CORS errors**: Verify API Gateway CORS configuration

## Rollback Plan

If deployment fails:

- [ ] Run `cd infrastructure && cdk destroy --all`
- [ ] Delete Cognito User Pool manually
- [ ] Clean up any remaining resources
- [ ] Review CloudFormation events for errors

## Success Criteria

Deployment is successful when:

- ✅ All CDK stacks deployed without errors
- ✅ Frontend accessible via CloudFront
- ✅ Users can log in via Cognito
- ✅ RDS instances discovered and displayed
- ✅ Health metrics loading correctly
- ✅ Operations (start/stop) working
- ✅ No errors in CloudWatch logs

## Notes

- Deployment time: ~30-45 minutes
- Cost estimate: ~$50-100/month (depending on usage)
- Maintenance: Review logs weekly, update dependencies monthly

---

**Deployment Date**: _______________
**Deployed By**: _______________
**Account ID**: _______________
**Region**: _______________
**Status**: ⬜ In Progress  ⬜ Complete  ⬜ Failed
