# API Gateway Clean URLs - Deployment Instructions

**Date:** December 24, 2025  
**Status:** Ready for Deployment  
**Prerequisites:** Docker Desktop must be running

## 🚨 Important Prerequisites

### 1. Docker Desktop Required
The BFF stack uses Docker containers and **requires Docker Desktop to be running**:

```bash
# Check if Docker is running
docker --version
docker ps
```

If Docker is not running:
- **Windows**: Start Docker Desktop application
- **macOS**: Start Docker Desktop application  
- **Linux**: Start Docker daemon (`sudo systemctl start docker`)

### 2. CDK Commands via NPM
**Always use `npm run cdk --` instead of direct `cdk` commands** to ensure proper dependencies:

```bash
# ✅ Correct way
npm run cdk -- deploy RDSDashboard-API

# ❌ Wrong way (may fail)
cdk deploy RDSDashboard-API
```

## 🚀 Deployment Steps

### Step 1: Verify Prerequisites
```bash
cd rds-operations-dashboard/infrastructure

# Check Docker is running
docker --version

# Check CDK is available
npm run cdk -- --version

# List available stacks
npm run cdk -- list
```

### Step 2: Deploy Both Stacks Together
Due to export dependencies between API and BFF stacks, deploy them together:

```bash
# Deploy API and BFF stacks simultaneously
npm run cdk -- deploy RDSDashboard-API RDSDashboard-BFF --require-approval never
```

**Alternative: Deploy individually (if needed)**
```bash
# Deploy API stack first
npm run cdk -- deploy RDSDashboard-API --require-approval never

# Then deploy BFF stack
npm run cdk -- deploy RDSDashboard-BFF --require-approval never
```

### Step 3: Validate Deployment
```bash
cd ..  # Back to project root
.\scripts\validate-clean-urls.ps1 -Verbose
```

## 🔧 Troubleshooting

### Issue: Docker Not Running
**Error:** `error during connect: Head "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/_ping"`

**Solution:**
1. Start Docker Desktop
2. Wait for Docker to fully initialize
3. Retry deployment

### Issue: Export Dependency Error
**Error:** `Cannot delete export RDSDashboard-API:ExportsOutputRefRdsOpsApiDeploymentStageprodBE55A035509C513C as it is in use by RDSDashboard-BFF and RDSDashboard-WAF`

**Solution:**
Deploy both stacks together:
```bash
npm run cdk -- deploy RDSDashboard-API RDSDashboard-BFF --require-approval never
```

### Issue: CDK Command Not Found
**Error:** `cdk : The term 'cdk' is not recognized`

**Solution:**
Always use npm scripts:
```bash
npm run cdk -- [command]
```

## 📋 Deployment Checklist

Before deployment:
- [ ] Docker Desktop is running
- [ ] You're in the `infrastructure/` directory
- [ ] AWS credentials are configured
- [ ] No other CDK deployments are running

After deployment:
- [ ] API Gateway console shows `$default` stage
- [ ] BFF endpoints respond without `/prod` in URL
- [ ] Frontend environment variables are updated
- [ ] All scripts use clean URLs
- [ ] Validation script passes

## 🎯 Expected Results

### Before Deployment
```
BFF API: https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod
Internal API: https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod
```

### After Deployment
```
BFF API: https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com
Internal API: https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com
```

## 🔄 Rollback Plan

If deployment fails or issues arise:

```bash
# Check current stack status
npm run cdk -- list

# View differences
npm run cdk -- diff RDSDashboard-API
npm run cdk -- diff RDSDashboard-BFF

# Rollback if needed (restore from git)
git checkout HEAD~1 -- infrastructure/lib/api-stack.ts
git checkout HEAD~1 -- infrastructure/lib/bff-stack.ts
git checkout HEAD~1 -- frontend/.env

# Redeploy previous version
npm run cdk -- deploy RDSDashboard-API RDSDashboard-BFF --require-approval never
```

## 📞 Support Commands

### Useful CDK Commands
```bash
# List all stacks
npm run cdk -- list

# Show differences before deployment
npm run cdk -- diff RDSDashboard-API

# Synthesize CloudFormation templates
npm run cdk -- synth

# Destroy stacks (careful!)
npm run cdk -- destroy RDSDashboard-API --force
```

### Validation Commands
```bash
# Test clean URLs
.\scripts\validate-clean-urls.ps1 -Verbose

# Test specific endpoints
curl https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/health
curl https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/health
```

## 💡 Future Deployments

**Remember for future deployments:**
1. Always use `npm run cdk --` instead of direct `cdk` commands
2. Ensure Docker Desktop is running for container-based stacks
3. Deploy interdependent stacks together to avoid export conflicts
4. Test with validation scripts after deployment
5. Keep rollback procedures documented and tested

---

**Ready to deploy?** Start Docker Desktop and run:
```bash
cd rds-operations-dashboard/infrastructure
npm run cdk -- deploy RDSDashboard-API RDSDashboard-BFF --require-approval never
```