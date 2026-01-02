# Realistic Action Plan - Critical Issues Resolution

**Date:** December 19, 2025  
**Status:** 🔴 **INFRASTRUCTURE ISSUES DETECTED**  
**User:** itthiagu@gmail.com  

---

## Reality Check

I need to be honest about what my testing revealed:

**My Test Result:**
```
Exit Code: -1
```

This means **the test failed completely**. The system timed out and couldn't even complete basic connectivity tests.

**What This Means:**
- ❌ The backend is likely NOT fully operational
- ❌ Lambda functions may not be deployed or are failing
- ❌ API Gateway may not be properly configured
- ❌ DynamoDB tables may be missing or inaccessible
- ❌ The "fixes" I mentioned may not have been deployed

**I Was Wrong When I Said:**
- "Backend API is fully operational" - **NOT VERIFIED**
- "All Lambda functions are working" - **NOT VERIFIED**
- "Just clear browser cache" - **INSUFFICIENT**

---

## What We Need to Do NOW

### Step 1: Run Emergency Diagnostic (5 minutes)

This will tell us what's actually broken:

```powershell
cd rds-operations-dashboard
.\emergency-diagnostic.ps1
```

**This script will check:**
- ✅ Can we reach the backend API?
- ✅ Can we reach the BFF API?
- ✅ Do Lambda functions exist?
- ✅ Are Lambda functions in Active state?
- ✅ Can we invoke Lambda functions?
- ✅ Do DynamoDB tables exist?
- ✅ Does the user have correct Cognito groups?

**Expected Output:**
The script will list SPECIFIC issues like:
- "Backend API unreachable"
- "rds-health-monitor function not found"
- "rds-discovery function not Active"
- "DynamoDB table rds-inventory-prod not found"
- "User does not have Admin group"

### Step 2: Fix Infrastructure Issues (Based on Diagnostic)

**If Lambda functions are missing:**
```powershell
# Deploy the infrastructure
cd infrastructure
npm install
cdk deploy --all
```

**If Lambda functions exist but are failing:**
```powershell
# Check CloudWatch logs for specific errors
aws logs tail /aws/lambda/rds-health-monitor --follow
aws logs tail /aws/lambda/rds-discovery --follow
aws logs tail /aws/lambda/rds-operations --follow
```

**If DynamoDB tables are missing:**
```powershell
# Deploy data stack
cd infrastructure
cdk deploy RDSOperationsDashboard-DataStack
```

**If user doesn't have correct groups:**
```powershell
# Add user to Admin group
aws cognito-idp admin-add-user-to-group `
  --user-pool-id ap-southeast-1_4tyxh4qJe `
  --username itthiagu@gmail.com `
  --group-name Admin

# Add user to DBA group
aws cognito-idp admin-add-user-to-group `
  --user-pool-id ap-southeast-1_4tyxh4qJe `
  --username itthiagu@gmail.com `
  --group-name DBA
```

### Step 3: Verify Fixes (5 minutes)

After fixing infrastructure issues, run the diagnostic again:

```powershell
.\emergency-diagnostic.ps1
```

**Success Criteria:**
- All Lambda functions show "[OK] Active"
- All API endpoints show "[OK]"
- All DynamoDB tables show "[OK] Active"
- User groups show "[OK] Groups: Admin, DBA"

### Step 4: Test Dashboard (Only After Infrastructure is Fixed)

**ONLY do this if Step 3 shows all [OK]:**

1. Clear browser cache completely
2. Close all browser tabs
3. Open dashboard in incognito mode
4. Log in with itthiagu@gmail.com
5. Test features:
   - Dashboard should load without 500 errors
   - Discovery button should work
   - Instance operations should be available

---

## Common Infrastructure Issues and Fixes

### Issue 1: Lambda Functions Not Deployed

**Symptoms:**
- "function not found" errors
- API Gateway returns 502 Bad Gateway

**Fix:**
```powershell
cd infrastructure
cdk deploy RDSOperationsDashboard-ComputeStack
```

### Issue 2: Lambda Functions in Failed State

**Symptoms:**
- Functions exist but show "Failed" or "Pending" state
- CloudWatch logs show import errors

**Fix:**
```powershell
# Check logs for specific error
aws logs tail /aws/lambda/rds-health-monitor --since 1h

# Common issue: Missing dependencies
# Redeploy with dependencies
cd lambda/health-monitor
pip install -r requirements.txt -t .
zip -r function.zip .
aws lambda update-function-code --function-name rds-health-monitor --zip-file fileb://function.zip
```

### Issue 3: API Gateway Not Deployed

**Symptoms:**
- API endpoints return 404 or 403
- "API key invalid" errors

**Fix:**
```powershell
cd infrastructure
cdk deploy RDSOperationsDashboard-ApiStack
```

### Issue 4: DynamoDB Tables Missing

**Symptoms:**
- Lambda functions fail with "Table not found"
- Operations return 500 errors

**Fix:**
```powershell
cd infrastructure
cdk deploy RDSOperationsDashboard-DataStack
```

### Issue 5: IAM Permissions Missing

**Symptoms:**
- Lambda functions can't access DynamoDB
- Cross-account operations fail

**Fix:**
```powershell
cd infrastructure
cdk deploy RDSOperationsDashboard-IamStack
```

---

## What NOT to Do

❌ **Don't clear browser cache first** - This won't fix infrastructure issues  
❌ **Don't assume code fixes are deployed** - Verify deployment status  
❌ **Don't test frontend before backend works** - Fix infrastructure first  
❌ **Don't skip the diagnostic** - You need to know what's actually broken  

---

## Expected Timeline

**If infrastructure is broken:**
- Diagnostic: 5 minutes
- Fix deployment: 15-30 minutes
- Verification: 5 minutes
- Frontend testing: 5 minutes
- **Total: 30-45 minutes**

**If only configuration issues:**
- Diagnostic: 5 minutes
- Fix configuration: 10 minutes
- Verification: 5 minutes
- Frontend testing: 5 minutes
- **Total: 25 minutes**

---

## Success Criteria

**Infrastructure Level:**
- [ ] Emergency diagnostic shows all [OK]
- [ ] All Lambda functions in Active state
- [ ] All API endpoints return 200 OK
- [ ] All DynamoDB tables exist and are Active
- [ ] User has Admin and DBA groups

**Application Level:**
- [ ] Dashboard loads without 500 errors
- [ ] Discovery button triggers scan successfully
- [ ] Instance operations work for Admin user
- [ ] Audit logs capture operations
- [ ] No console errors in browser (F12)

---

## If You're Stuck

**Check CloudWatch Logs:**
```powershell
# Health Monitor
aws logs tail /aws/lambda/rds-health-monitor --follow

# Discovery
aws logs tail /aws/lambda/rds-discovery --follow

# Operations
aws logs tail /aws/lambda/rds-operations --follow

# BFF
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

**Check Lambda Function Status:**
```powershell
aws lambda get-function --function-name rds-health-monitor
aws lambda get-function --function-name rds-discovery
aws lambda get-function --function-name rds-operations
aws lambda get-function --function-name rds-dashboard-bff
```

**Check DynamoDB Tables:**
```powershell
aws dynamodb list-tables
aws dynamodb describe-table --table-name rds-inventory-prod
aws dynamodb describe-table --table-name audit-log-prod
```

**Check API Gateway:**
```powershell
aws apigateway get-rest-apis
```

---

## Bottom Line

**START HERE:**
1. Run `.\emergency-diagnostic.ps1`
2. Read the output carefully
3. Fix the specific issues it identifies
4. Run diagnostic again to verify
5. ONLY THEN test the dashboard

**Don't skip the diagnostic. It will save you hours of guessing.**

---

**Last Updated:** December 19, 2025  
**Status:** Awaiting Emergency Diagnostic Results  
**Next Action:** Run `emergency-diagnostic.ps1` and share the output