# Monitoring Stack Deployment Issue

**Issue:** RDSDashboard-Monitoring stack failed during deployment  
**Error:** `AWS::EarlyValidation::ResourceExistenceCheck` - Resource validation failed  
**Impact:** Low - Monitoring stack is optional, core functionality works without it

## Root Cause

The Monitoring stack requires Lambda function references from the Compute stack:
- discoveryFunction
- healthMonitorFunction  
- costAnalyzerFunction
- complianceCheckerFunction
- operationsFunction

These references may not be properly exported/imported between stacks.

## Workaround

**Option 1: Skip Monitoring Stack (Recommended for now)**

The monitoring stack creates CloudWatch alarms and dashboards. Core functionality works without it:
- ✅ RDS Discovery works
- ✅ Health Monitoring works
- ✅ Operations work
- ✅ API Gateway works
- ❌ CloudWatch Dashboard (optional)
- ❌ SNS Alarms (optional)

**Option 2: Deploy Monitoring Stack Separately Later**

After other stacks are deployed:
```powershell
cd rds-operations-dashboard/infrastructure
npx cdk deploy RDSDashboard-Monitoring
```

## Current Deployment Status

**Successful (4 stacks):**
- ✅ RDSDashboard-Data
- ✅ RDSDashboard-IAM
- ✅ RDSDashboard-Compute
- ✅ RDSDashboard-Orchestration

**Failed (1 stack):**
- ❌ RDSDashboard-Monitoring (optional)

**Remaining (3 stacks):**
- ⏳ RDSDashboard-API
- ⏳ RDSDashboard-Auth
- ⏳ RDSDashboard-BFF

## Recommendation

**Continue with remaining stacks.** The Monitoring stack is optional and can be fixed/deployed later. The core RDS Operations Dashboard functionality will work without it.

## Next Steps

1. Let the remaining stacks (API, Auth, BFF) complete deployment
2. Test core functionality (discovery, operations, health monitoring)
3. Fix Monitoring stack later if needed (or manually create CloudWatch dashboards)

## Fix for Future Deployment

Update `infrastructure/bin/app.ts` to properly pass Lambda function references to Monitoring stack, or make Monitoring stack lookup functions by name instead of requiring references.
