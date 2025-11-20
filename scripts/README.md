# Scripts Directory

This directory contains utility scripts for setting up and managing the RDS Operations Dashboard infrastructure.

## Available Scripts

### BFF (Backend-for-Frontend) Scripts

#### deploy-bff.ps1

Deploys the complete BFF stack with Secrets Manager integration.

**Requirements:**
- PowerShell 5.1 or later
- AWS CLI installed and configured
- CDK installed (`npm install -g aws-cdk`)
- Internal API stack deployed

**Usage:**
```powershell
.\deploy-bff.ps1 [-Environment prod]
```

**What it does:**
1. Deploys BFF CDK stack (Lambda + API Gateway + Secrets Manager)
2. Retrieves API key from internal API Gateway
3. Stores credentials in Secrets Manager
4. Outputs BFF API URL for frontend configuration

**See:** [BFF Deployment Guide](../BFF-DEPLOYMENT.md) for detailed instructions

---

#### setup-bff-secrets.ps1

Populates Secrets Manager with API Gateway credentials.

**Requirements:**
- PowerShell 5.1 or later
- AWS CLI installed and configured
- BFF stack deployed
- Internal API stack deployed

**Usage:**
```powershell
.\setup-bff-secrets.ps1 [-Environment prod]
```

**What it does:**
1. Retrieves API Key ID from CloudFormation
2. Gets API URL from CloudFormation
3. Fetches actual API key value from API Gateway
4. Creates/updates secret in Secrets Manager

---

#### test-bff.ps1

Validates BFF deployment and configuration.

**Requirements:**
- PowerShell 5.1 or later
- AWS CLI installed and configured

**Usage:**
```powershell
.\test-bff.ps1 [-Environment prod]
```

**What it does:**
- Tests BFF stack exists
- Verifies API Gateway URL
- Checks Lambda function
- Validates Secrets Manager secret
- Tests IAM permissions
- Verifies CORS configuration
- Tests API endpoints
- Checks CloudWatch logs

**Output:**
- Test summary with pass/fail status
- BFF URL for frontend configuration
- Troubleshooting guidance if tests fail

---

### Infrastructure Setup Scripts

#### setup-s3-structure.py

Python script to initialize S3 bucket folder structure and upload CloudOps templates.

**Requirements:**
- Python 3.7+
- boto3 library (`pip install boto3`)
- AWS credentials configured

**Usage:**
```bash
python setup-s3-structure.py --bucket-name rds-dashboard-data-123456789012-prod
```

**See:** [S3 Setup Guide](../docs/s3-setup-guide.md) for detailed instructions

---

#### setup-s3-structure.ps1

PowerShell script to initialize S3 bucket folder structure and upload CloudOps templates (Windows).

**Requirements:**
- PowerShell 5.1 or later
- AWS CLI installed and configured

**Usage:**
```powershell
.\setup-s3-structure.ps1 -BucketName "rds-dashboard-data-123456789012-prod"
```

**See:** [S3 Setup Guide](../docs/s3-setup-guide.md) for detailed instructions

---

## Quick Reference

### BFF Deployment Workflow

```powershell
# 1. Deploy BFF (one command)
.\deploy-bff.ps1

# 2. Test deployment
.\test-bff.ps1

# 3. Get BFF URL
aws cloudformation describe-stacks `
  --stack-name RDSDashboard-BFF-prod `
  --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
  --output text

# 4. Update frontend/.env with BFF URL
# VITE_BFF_API_URL=<your-bff-url>

# 5. Deploy frontend
cd ../frontend
npm run dev  # Test locally
git push     # Deploy to production
```

### Troubleshooting BFF

```powershell
# View BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow

# Check secret
aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod

# Re-run secrets setup
.\setup-bff-secrets.ps1

# Redeploy BFF
cd ../infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod --force
```

---

## Script Execution Order

### Initial Setup
1. **Deploy Infrastructure First**: Run `cdk deploy DataStack` to create the S3 bucket
2. **Run S3 Setup Script**: Initialize folder structure and upload templates
3. **Deploy Lambda Functions**: Deploy compute stack with Lambda functions
4. **Configure EventBridge**: Set up scheduled rules for automation

### BFF Setup (Security Enhancement)
1. **Deploy Internal API**: Ensure `RDSDashboard-API-prod` stack is deployed
2. **Deploy BFF Stack**: Run `.\deploy-bff.ps1`
3. **Test BFF**: Run `.\test-bff.ps1`
4. **Update Frontend**: Configure frontend to use BFF URL
5. **Deploy Frontend**: Push changes to trigger GitHub Actions

---

## Common Issues

### BFF Scripts

#### Error: "Could not retrieve API Key ID from CloudFormation stack"

**Solution:**
Ensure the internal API stack is deployed:
```powershell
aws cloudformation describe-stacks --stack-name RDSDashboard-API-prod
```

#### Error: "Secret does not exist yet"

**Solution:**
Deploy the BFF stack first:
```powershell
cd ../infrastructure
npx aws-cdk deploy RDSDashboard-BFF-prod
```

#### Error: BFF tests fail

**Solution:**
1. Check CloudWatch logs: `aws logs tail /aws/lambda/rds-dashboard-bff-prod --follow`
2. Verify secret: `aws secretsmanager get-secret-value --secret-id rds-dashboard-api-key-prod`
3. Re-run secrets setup: `.\setup-bff-secrets.ps1`

### S3 Scripts

#### Python Script: ModuleNotFoundError: No module named 'boto3'

**Solution:**
```bash
pip install boto3
```

#### PowerShell Script: AWS CLI not found

**Solution:**
Install AWS CLI from: https://aws.amazon.com/cli/

#### Access Denied Errors

**Solution:**
Ensure your AWS credentials have the required S3 permissions. See [S3 Setup Guide](../docs/s3-setup-guide.md) for required IAM permissions.

---

## Script Conventions

All scripts in this directory follow these conventions:

1. **Naming**: Use kebab-case for script names (e.g., `setup-s3-structure.ps1`)
2. **Documentation**: Each script should have a header comment explaining its purpose
3. **Error Handling**: Scripts should handle errors gracefully and provide clear error messages
4. **Idempotency**: Scripts should be safe to run multiple times
5. **Logging**: Scripts should log their actions for troubleshooting
6. **Parameters**: Use named parameters with defaults where appropriate
7. **Output**: Provide clear, colored output for success/failure/warnings

## Environment Variables

Scripts may use these environment variables:

- `AWS_PROFILE` - AWS CLI profile to use
- `AWS_REGION` - AWS region (default: ap-southeast-1)
- `AWS_ACCOUNT_ID` - AWS account ID

## Exit Codes

Scripts use standard exit codes:

- `0` - Success
- `1` - General error
- `2` - Invalid parameters
- `3` - Missing prerequisites

---

## Adding New Scripts

When adding new scripts to this directory:

1. Include metadata header with:
   - Generated by
   - Timestamp
   - Version
   - Policy Version
   - Traceability
   - Risk Level

2. Add comprehensive error handling

3. Include usage examples in comments

4. Update this README with script description

5. Add entry to main project documentation

6. Follow naming and documentation conventions

7. Test in development environment first

---

## Related Documentation

### BFF Documentation
- [BFF Deployment Guide](../BFF-DEPLOYMENT.md)
- [BFF Security Guide](../docs/bff-security-guide.md)
- [BFF Implementation Summary](../BFF-IMPLEMENTATION-SUMMARY.md)
- [BFF Deployment Checklist](../BFF-DEPLOYMENT-CHECKLIST.md)

### Infrastructure Documentation
- [S3 Setup Guide](../docs/s3-setup-guide.md)
- [S3 Bucket Structure](../docs/s3-bucket-structure.md)
- [Deployment Guide](../docs/deployment.md)
- [Infrastructure Documentation](../INFRASTRUCTURE.md)

---

## Support

For issues or questions about these scripts:

1. Check script output for error messages
2. Review CloudWatch logs (for AWS-related scripts)
3. Refer to main project documentation
4. Contact the development team
