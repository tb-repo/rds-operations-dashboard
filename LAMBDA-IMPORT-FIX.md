# Lambda Import Error Fix - 502 Bad Gateway Root Cause

## Issue Identified

**Root Cause**: All backend Lambda functions are failing with:
```
Runtime.ImportModuleError: Unable to import module 'handler': No module named 'shared.structured_logger'
```

**Impact**: 
- Frontend shows 500 Internal Server Error
- BFF receives 502 Bad Gateway from backend Lambdas
- All API endpoints (/instances, /compliance, /costs) are non-functional

## Why This Happened

The Lambda functions are deployed with only their individual directories:
```typescript
code: lambda.Code.fromAsset('../lambda/discovery'),  // ❌ Missing shared module
```

But the code imports from the shared module:
```python
from shared.structured_logger import get_logger
from shared.correlation_middleware import with_correlation_id
```

The `shared` folder is NOT included in the deployment package, causing import failures.

## Solution

### Option 1: Deploy with Parent Directory (Recommended)

Update `infrastructure/lib/compute-stack.ts` to include the shared module:

```typescript
// Before:
code: lambda.Code.fromAsset('../lambda/discovery'),

// After:
code: lambda.Code.fromAsset('../lambda', {
  bundling: {
    image: lambda.Runtime.PYTHON_3_11.bundlingImage,
    command: [
      'bash', '-c',
      'pip install -r requirements.txt -t /asset-output && cp -au . /asset-output'
    ],
  },
}),
handler: 'discovery.handler.lambda_handler',  // Update handler path
```

### Option 2: Use Lambda Layers (Better for Production)

Create a Lambda Layer for the shared module:

```typescript
// Create shared layer
const sharedLayer = new lambda.LayerVersion(this, 'SharedLayer', {
  code: lambda.Code.fromAsset('../lambda/shared'),
  compatibleRuntimes: [lambda.Runtime.PYTHON_3_11],
  description: 'Shared utilities for RDS Dashboard Lambdas',
});

// Add to each Lambda
this.discoveryFunction = new lambda.Function(this, 'DiscoveryFunction', {
  // ... existing config ...
  layers: [sharedLayer],
});
```

### Option 3: Quick Fix - Copy Shared Module

For immediate fix without redeployment:

```bash
# Copy shared module to each Lambda directory
cd lambda
for dir in discovery health-monitor cost-analyzer query-handler compliance-checker operations cloudops-generator monitoring approval-workflow; do
  cp -r shared $dir/
done
```

Then redeploy:
```bash
cd infrastructure
cdk deploy ComputeStack
```

## Recommended Action

**Use Option 3 for immediate fix**, then implement Option 2 (Lambda Layers) for proper architecture.

### Step-by-Step Fix

1. **Copy shared module to all Lambda directories**:
```powershell
cd rds-operations-dashboard/lambda
$dirs = @('discovery', 'health-monitor', 'cost-analyzer', 'query-handler', 'compliance-checker', 'operations', 'cloudops-generator', 'monitoring', 'approval-workflow')
foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Copy-Item -Path shared -Destination "$dir/shared" -Recurse -Force
        Write-Host "Copied shared to $dir"
    }
}
```

2. **Redeploy all Lambda functions**:
```powershell
cd ../infrastructure
cdk deploy ComputeStack --require-approval never
```

3. **Verify the fix**:
```powershell
# Check Lambda logs
aws logs tail /aws/lambda/rds-discovery --since 5m --follow --region ap-southeast-1

# Test the API
curl https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/instances `
  -H "x-api-key: OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
```

## Prevention

Add to deployment checklist:
- [ ] Verify all Lambda dependencies are included in deployment package
- [ ] Test Lambda imports locally before deployment
- [ ] Use Lambda Layers for shared code
- [ ] Add integration tests that actually invoke Lambdas

## Timeline

- **Issue Started**: After last CDK deployment
- **Identified**: 2025-12-07 16:51 UTC
- **Root Cause**: Missing shared module in Lambda deployment packages
- **Fix ETA**: 10 minutes (copy + redeploy)
