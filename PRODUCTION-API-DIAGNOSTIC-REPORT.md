# Production API Diagnostic Report

**Date:** December 20, 2025  
**Status:** 🔴 **CRITICAL ISSUES IDENTIFIED**  
**Spec:** Production API Fixes (Task 1)

---

## 🎯 Executive Summary

The RDS Operations Dashboard is experiencing two critical production API failures:

1. **500 Internal Server Error** on `/api/errors/statistics` endpoint
2. **403 Forbidden** on `/api/operations` endpoint

This report documents the root causes and provides actionable fixes.

---

## 🔍 Issue 1: 500 Error on `/api/errors/statistics`

### Symptoms
```
GET https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/errors/statistics
Status: 500 Internal Server Error
```

### Root Cause Analysis

**Problem:** The BFF is trying to call `/error-resolution/statistics` on the backend API Gateway, but this endpoint doesn't exist or isn't properly configured.

**Evidence:**
1. ✅ BFF route exists: `bff/src/routes/error-resolution.ts` has `/statistics` endpoint
2. ✅ API Gateway route exists: `api-stack.ts` creates `/error-resolution/statistics` route
3. ❌ **Lambda function doesn't handle this path**: The monitoring Lambda (`lambda/monitoring/handler.py`) doesn't have a handler for the statistics endpoint

**Code Analysis:**

In `bff/src/routes/error-resolution.ts`:
```typescript
router.get('/statistics', async (req: Request, res: Response) => {
  try {
    const response = await axios.get(
      `${internalApiUrl}/error-resolution/statistics`,  // ← Calls this endpoint
      {
        headers: { 'x-api-key': getApiKey() },
        timeout: 5000,
      }
    )
    res.json(response.data)
  } catch (error: any) {
    // Returns fallback data on error
    res.json({
      status: 'unavailable',
      message: 'Error statistics service is temporarily unavailable',
      fallback: true,
      // ... fallback data
    })
  }
})
```

In `infrastructure/lib/api-stack.ts`:
```typescript
private createErrorResolutionEndpoints(errorResolutionFunction: lambda.IFunction): void {
  const errorResolution = this.api.root.addResource('error-resolution');
  
  // ... other routes ...
  
  const statistics = errorResolution.addResource('statistics');
  statistics.addMethod(
    'GET',
    new apigateway.LambdaIntegration(errorResolutionFunction, {  // ← Routes to errorResolutionFunction
      proxy: true,
    }),
    {
      apiKeyRequired: true,
    }
  );
}
```

**The Problem:** The `errorResolutionFunction` Lambda doesn't exist or doesn't handle the `/error-resolution/statistics` path. The API Gateway is routing to a Lambda that either:
- Doesn't exist
- Exists but doesn't have a handler for this path
- Exists but is throwing an unhandled error

### Solution

**Option 1: Use the monitoring Lambda instead**
The monitoring Lambda (`lambda/monitoring/handler.py`) has the dashboard and metrics functionality. We should route the statistics endpoint to the monitoring Lambda, not the error-resolution Lambda.

**Option 2: Implement the statistics endpoint in the error-resolution Lambda**
Create a proper error-resolution Lambda function that handles statistics requests.

**Recommended:** Option 1 - Route to monitoring Lambda

---

## 🔍 Issue 2: 403 Error on `/api/operations`

### Symptoms
```
POST https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations
Status: 403 Forbidden
```

### Root Cause Analysis

**Problem:** The operations endpoint is returning 403 Forbidden, which indicates an authorization issue.

**Evidence:**
1. ✅ BFF route exists and forwards requests correctly
2. ✅ Operations Lambda exists and is deployed
3. ✅ Production operations are enabled in config (`enable_production_operations: true`)
4. ❌ **User authentication/authorization is failing**

**Possible Causes:**

1. **Missing JWT Token**: The frontend isn't sending a valid JWT token
2. **Token Validation Failure**: The BFF or Lambda is rejecting the token
3. **Insufficient Permissions**: The user doesn't have the required permissions
4. **Missing User Groups**: The user isn't in the required Cognito groups (Admin/DBA)
5. **Production Operation Validation**: The operation requires `confirm_production: true` parameter

**Code Analysis:**

In `lambda/operations/handler.py`:
```python
def _validate_production_operation(self, operation, instance, parameters, user_identity):
    # For risky operations, require additional validation
    if operation in risky_operations:
        # Check if admin privileges are required
        if require_admin:
            user_groups = user_identity.get('user_groups', [])
            is_admin = any(group in ['Admin', 'DBA'] for group in user_groups)
            
            if not is_admin:
                return {
                    'allowed': False,
                    'reason': f"Operation '{operation}' on production instance requires admin privileges"
                }
        
        # Additional safeguards for destructive operations
        if require_confirmation and operation in ['stop_instance', 'reboot', 'reboot_instance']:
            if not parameters.get('confirm_production', False):
                return {
                    'allowed': False,
                    'reason': f"Production {operation} requires 'confirm_production': true parameter"
                }
```

### Solution

**Immediate Fixes:**
1. Verify JWT token is being sent from frontend
2. Check user is in Admin or DBA Cognito group
3. For risky operations, include `confirm_production: true` parameter
4. Check CloudWatch logs for specific error messages

**Long-term Fixes:**
1. Improve error messages to indicate specific authorization failure reason
2. Add better logging of authentication failures
3. Implement frontend UI to show user permissions and required groups

---

## 📊 System Architecture Analysis

### Current Flow

```
Frontend (CloudFront)
    ↓ (JWT Token in Authorization header)
BFF Layer (Express)
    ↓ (Validates JWT, adds user context)
API Gateway (Backend)
    ↓ (Requires API Key)
Lambda Functions
    ↓ (Validates permissions)
AWS Services (RDS, DynamoDB, etc.)
```

### Issues in the Flow

1. **Error Statistics Path:**
   ```
   Frontend → BFF → /api/errors/statistics
   BFF → Backend API → /error-resolution/statistics
   Backend API → ??? (Lambda not found or misconfigured)
   ```

2. **Operations Path:**
   ```
   Frontend → BFF → /api/operations (with JWT)
   BFF → Backend API → /operations (with API key + user context)
   Backend API → Operations Lambda
   Operations Lambda → 403 (authorization failure)
   ```

---

## 🔧 Recommended Fixes

### Priority 1: Fix 500 Error on Statistics Endpoint

**Action:** Update API Gateway configuration to route statistics to monitoring Lambda

**Files to modify:**
- `infrastructure/lib/api-stack.ts` - Change Lambda integration for statistics endpoint

**Change:**
```typescript
// BEFORE
const statistics = errorResolution.addResource('statistics');
statistics.addMethod(
  'GET',
  new apigateway.LambdaIntegration(errorResolutionFunction, {
    proxy: true,
  }),
  {
    apiKeyRequired: true,
  }
);

// AFTER
const statistics = errorResolution.addResource('statistics');
statistics.addMethod(
  'GET',
  new apigateway.LambdaIntegration(monitoringDashboardFunction, {  // ← Use monitoring Lambda
    proxy: true,
  }),
  {
    apiKeyRequired: true,
  }
);
```

**Alternative:** Implement statistics endpoint in error-resolution Lambda or remove the endpoint entirely and disable the widget in the frontend.

### Priority 2: Fix 403 Error on Operations Endpoint

**Action:** Diagnose authentication flow and fix authorization

**Steps:**
1. Check CloudWatch logs for operations Lambda to see exact error message
2. Verify JWT token is being sent from frontend
3. Check user Cognito group membership
4. Test with proper authentication and required parameters

**Diagnostic Commands:**
```powershell
# Check Lambda logs
aws logs tail /aws/lambda/rds-operations --follow

# Check user groups
aws cognito-idp admin-list-groups-for-user `
  --user-pool-id <pool-id> `
  --username <username>

# Test with curl (with proper token)
curl -X POST https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations `
  -H "Authorization: Bearer <jwt-token>" `
  -H "Content-Type: application/json" `
  -d '{"operation_type":"create_snapshot","instance_id":"database-1","parameters":{"snapshot_id":"test-snapshot"}}'
```

---

## 📝 Next Steps

1. **Run diagnostic script:**
   ```powershell
   .\scripts\diagnose-production-api-issues.ps1 -Verbose
   ```

2. **Check CloudWatch logs:**
   - `/aws/lambda/rds-operations`
   - `/aws/lambda/rds-monitoring-dashboard`
   - `/aws/lambda/rds-dashboard-bff`

3. **Implement fixes:**
   - Task 2: Fix error statistics endpoint
   - Task 3: Fix operations endpoint

4. **Deploy and test:**
   - Deploy infrastructure changes
   - Test endpoints with proper authentication
   - Verify dashboard loads without errors

---

## 🎯 Success Criteria

- [ ] `/api/errors/statistics` returns 200 OK or graceful fallback
- [ ] `/api/operations` returns 200 OK for authorized users
- [ ] Dashboard loads without 500/403 errors in console
- [ ] Error monitoring widget displays correctly or hides gracefully
- [ ] Operations can be executed by authorized users

---

**Report Generated:** December 20, 2025  
**Next Review:** After implementing fixes in Tasks 2 and 3