# Operations 403 Forbidden Error - Final Fix

**Date:** December 19, 2025  
**Status:** 🔧 **FIXED - READY TO DEPLOY**  
**Issue:** 403 Forbidden when performing operations despite having Admin/DBA privileges

---

## 🔍 **Root Cause Identified**

The issue was **NOT** with user permissions in Cognito. The user correctly has Admin/DBA privileges. The problem was in the **communication between the BFF and the Operations Lambda**.

### **Technical Root Cause:**
1. **BFF Authorization**: ✅ Working correctly - validates user has `execute_operations` permission
2. **Operations Lambda Authorization**: ❌ **FAILING** - not receiving user group information
3. **Missing Data**: The BFF was not passing the user's Cognito groups to the Operations Lambda
4. **Validation Failure**: Operations Lambda couldn't validate admin privileges for production operations

### **Code Issue Details:**
- **BFF** (`bff/src/index.ts`): Only passed `user_id` and `requested_by`, missing `user_groups`
- **Operations Lambda** (`lambda/operations/handler.py`): Expected user groups in `cognitoAuthenticationProvider` format
- **Environment Variable**: `ENABLE_PRODUCTION_OPERATIONS` not set in BFF Lambda

---

## 🔧 **Fixes Applied**

### **Fix 1: BFF Request Enhancement**
**File:** `rds-operations-dashboard/bff/src/index.ts`

**Before:**
```typescript
const requestBody = {
  ...req.body,
  requested_by: req.user?.email,
  user_id: req.user?.userId,
}
```

**After:**
```typescript
const requestBody = {
  ...req.body,
  requested_by: req.user?.email,
  user_id: req.user?.userId,
  user_groups: req.user?.groups || [],
  user_permissions: req.user?.permissions || [],
}
```

### **Fix 2: Operations Lambda User Identity Extraction**
**File:** `rds-operations-dashboard/lambda/operations/handler.py`

**Before:**
```python
user_identity = event.get('requestContext', {}).get('identity', {})
```

**After:**
```python
# Extract user identity from request body (passed by BFF)
user_identity = {
    'user_id': body.get('user_id'),
    'requested_by': body.get('requested_by'),
    'user_groups': body.get('user_groups', []),
    'user_permissions': body.get('user_permissions', []),
    # Fallback to API Gateway context if needed
    **event.get('requestContext', {}).get('identity', {})
}
```

### **Fix 3: Admin Privilege Validation**
**File:** `rds-operations-dashboard/lambda/operations/handler.py`

**Before:**
```python
user_groups = user_identity.get('cognitoAuthenticationProvider', '').split(':')
is_admin = any('Admin' in group or 'DBA' in group for group in user_groups)
```

**After:**
```python
user_groups = user_identity.get('user_groups', [])
is_admin = any(group in ['Admin', 'DBA'] for group in user_groups)

logger.info(f"Checking admin privileges for {operation}", {
    'user_groups': user_groups,
    'is_admin': is_admin,
    'instance_id': instance_id
})
```

### **Fix 4: Environment Variable**
**Function:** `rds-dashboard-bff`
**Variable:** `ENABLE_PRODUCTION_OPERATIONS=true`

---

## 🚀 **Deployment Instructions**

### **Option 1: Automated Deployment (Recommended)**
```powershell
cd rds-operations-dashboard
.\fix-operations-403-error.ps1
```

The script will:
- ✅ Build and package both Lambda functions
- ✅ Deploy the updated code
- ✅ Set the required environment variable
- ✅ Verify the deployment

### **Option 2: Manual Deployment**

1. **Deploy Operations Lambda:**
   ```bash
   cd lambda
   zip -r operations.zip operations/ shared/
   aws lambda update-function-code --function-name rds-operations --zip-file fileb://operations.zip
   ```

2. **Deploy BFF Lambda:**
   ```bash
   cd bff
   npm run build
   zip -r bff.zip dist/ node_modules/ package.json
   aws lambda update-function-code --function-name rds-dashboard-bff --zip-file fileb://bff.zip
   ```

3. **Set Environment Variable:**
   ```bash
   aws lambda update-function-configuration \
     --function-name rds-dashboard-bff \
     --environment Variables='{
       "ENABLE_PRODUCTION_OPERATIONS": "true",
       "COGNITO_USER_POOL_ID": "your-pool-id",
       "COGNITO_REGION": "ap-southeast-1",
       "INTERNAL_API_URL": "your-api-url"
     }'
   ```

---

## 🧪 **Testing After Deployment**

### **Step 1: Clear Browser State**
1. **Log out** of the dashboard completely
2. **Clear browser cache** and cookies
3. **Close all browser tabs**

### **Step 2: Log Back In**
1. Go to the dashboard URL
2. Log in with your Admin/DBA user
3. Verify you see your groups in the user profile

### **Step 3: Test Operations**
1. Navigate to an RDS instance
2. Try a **safe operation** first: "Create Snapshot"
3. Try a **risky operation**: "Reboot Instance" (with confirmation)
4. Check browser console for any errors

### **Expected Results:**
- ✅ **No 403 Forbidden errors**
- ✅ **Operations execute successfully**
- ✅ **Proper audit logging**
- ✅ **Production operations work with confirmation**

---

## 🔍 **Verification Commands**

### **Check BFF Environment Variables:**
```bash
aws lambda get-function-configuration --function-name rds-dashboard-bff --query "Environment.Variables"
```

### **Check Operations Lambda Logs:**
```bash
aws logs tail /aws/lambda/rds-operations --follow
```

### **Test Operations Endpoint:**
```bash
# Replace with your BFF URL
curl -X POST https://your-bff-url/api/operations \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "create_snapshot",
    "instance_id": "database-1",
    "parameters": {
      "snapshot_id": "test-snapshot-123"
    }
  }'
```

---

## 🛡️ **Security Validation**

After deployment, the security layers will work as follows:

### **Layer 1: BFF Authorization**
- ✅ Validates user has `execute_operations` permission
- ✅ Only Admin/DBA users pass this check

### **Layer 2: Operations Lambda Validation**
- ✅ Receives user groups from BFF
- ✅ Validates admin privileges for risky operations
- ✅ Requires `confirm_production: true` for destructive operations

### **Layer 3: Production Safeguards**
- ✅ Safe operations (snapshot, backup window) - immediate access
- ⚠️ Risky operations (reboot, stop/start) - require admin + confirmation
- 🔒 All operations logged with full audit trail

---

## 📊 **Expected Behavior After Fix**

### **For Admin/DBA Users:**
| Operation | Production Instance | Confirmation Required | Expected Result |
|-----------|--------------------|--------------------|-----------------|
| Create Snapshot | ✅ Allowed | No | ✅ Success |
| Modify Backup Window | ✅ Allowed | No | ✅ Success |
| Reboot Instance | ✅ Allowed | Yes (`confirm_production: true`) | ✅ Success |
| Stop Instance | ✅ Allowed | Yes (`confirm_production: true`) | ✅ Success |
| Start Instance | ✅ Allowed | Yes (`confirm_production: true`) | ✅ Success |

### **For ReadOnly Users:**
| Operation | Any Instance | Expected Result |
|-----------|--------------|-----------------|
| Any Operation | ❌ Blocked | 403 Forbidden (at BFF level) |

---

## 🎯 **Success Criteria**

After deployment, you should be able to:

1. ✅ **Log in successfully** with Admin/DBA user
2. ✅ **See operation buttons** enabled on RDS instances
3. ✅ **Execute safe operations** (Create Snapshot) without errors
4. ✅ **Execute risky operations** (Reboot) with confirmation parameter
5. ✅ **View audit logs** of all operations
6. ✅ **No 403 Forbidden errors** in browser console

---

## 🚨 **Rollback Plan**

If issues occur after deployment:

### **Quick Rollback:**
```bash
# Revert to previous Lambda versions
aws lambda update-function-code --function-name rds-operations --zip-file fileb://backup/operations-old.zip
aws lambda update-function-code --function-name rds-dashboard-bff --zip-file fileb://backup/bff-old.zip

# Remove environment variable
aws lambda update-function-configuration --function-name rds-dashboard-bff --environment Variables='{}'
```

### **Disable Production Operations:**
```bash
aws lambda update-function-configuration \
  --function-name rds-dashboard-bff \
  --environment Variables='{"ENABLE_PRODUCTION_OPERATIONS": "false"}'
```

---

## 📞 **Support**

### **If Operations Still Fail:**
1. Check CloudWatch logs for both Lambda functions
2. Verify user groups in JWT token payload
3. Confirm environment variables are set correctly
4. Test with a simple operation first (Create Snapshot)

### **Debug Commands:**
```bash
# Check user groups in token
# Open browser dev tools → Network → Look for JWT payload

# Check Lambda logs
aws logs tail /aws/lambda/rds-operations --follow
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

---

**🎉 This fix resolves the 403 Forbidden error by ensuring user group information flows correctly from the BFF to the Operations Lambda, enabling proper admin privilege validation for production operations.**

**Last Updated:** December 19, 2025  
**Status:** Ready to Deploy ✅  
**Next Action:** Run `.\fix-operations-403-error.ps1` to deploy the fix