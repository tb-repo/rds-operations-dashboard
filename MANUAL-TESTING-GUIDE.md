# Manual Testing Guide - Evidence-Based Diagnosis

**Purpose**: Gather concrete evidence about what's actually broken vs what documentation claims  
**Approach**: Test each component manually to understand the real current state  

## 🎯 **Testing Philosophy**

**STOP** making assumptions about what's broken. **START** testing what actually works.

Previous fixes failed because they were based on assumptions rather than evidence. This guide helps you gather concrete proof of what's working and what isn't.

---

## 🔍 **Test 1: Frontend Dashboard Access**

### **Objective**: Verify basic dashboard functionality

**Steps:**
1. Open browser to your dashboard URL
2. Log in with your credentials
3. Navigate to the main dashboard page

**Record Evidence:**
- ✅ **WORKS**: Dashboard loads, login successful, can navigate
- ❌ **BROKEN**: Specific error messages, which pages fail, console errors

**Browser Console Check:**
- Press F12 → Console tab
- Look for JavaScript errors (red text)
- Record exact error messages

**Expected Evidence:**
```
✅ Dashboard URL: https://your-dashboard-url.com
✅ Login: Successful
✅ Main page: Loads without errors
❌ Console errors: [Record any red error messages]
```

---

## 🔍 **Test 2: Instance Operations (The 400 Error)**

### **Objective**: Capture the exact 400 error and request details

**Steps:**
1. Navigate to an RDS instance on the dashboard
2. Open browser Developer Tools (F12) → Network tab
3. Click on an operation button (Stop/Start/Reboot)
4. Watch the Network tab for the failing request

**Record Evidence:**
- Request URL that's failing
- Request method (GET/POST/PUT)
- Request headers (especially Authorization)
- Request body/payload
- Response status code and error message
- Response headers

**Expected Evidence:**
```
❌ Request URL: https://api-gateway-url/api/operations
❌ Method: POST
❌ Status: 400 Bad Request
❌ Request Headers: [Copy Authorization header]
❌ Request Body: [Copy the JSON payload]
❌ Response: [Copy exact error message]
```

**Critical Questions:**
- Is the request reaching the API at all?
- What's the exact error message in the response?
- Are there authentication headers being sent?

---

## 🔍 **Test 3: Cross-Account Instance Visibility**

### **Objective**: Determine if instances exist and where they should be visible

**Steps:**
1. **Manual AWS Console Check**:
   - Log into AWS Console for account 876595225096
   - Go to RDS → Databases
   - Check regions: ap-southeast-1, eu-west-2, ap-south-1, us-east-1
   - Record all instances found

2. **Cross-Account Check** (if you have access):
   - Log into AWS Console for account 817214535871
   - Go to RDS → Databases  
   - Check same regions
   - Record all instances found

3. **Dashboard Comparison**:
   - Compare what you see in AWS Console vs Dashboard
   - Record which instances are missing from dashboard

**Expected Evidence:**
```
AWS Console - Account 876595225096:
✅ ap-southeast-1: [List instance IDs and states]
✅ eu-west-2: [List instance IDs and states]
✅ ap-south-1: [List instance IDs and states]
✅ us-east-1: [List instance IDs and states]

AWS Console - Account 817214535871:
✅ ap-southeast-1: [List instance IDs and states]
✅ eu-west-2: [List instance IDs and states]

Dashboard Display:
❌ Shows: [List what dashboard shows]
❌ Missing: [List what's missing compared to AWS Console]
```

---

## 🔍 **Test 4: API Endpoint Discovery**

### **Objective**: Find the actual API endpoints being used

**Steps:**
1. **Frontend Code Check**:
   ```bash
   # Look for API base URL in frontend code
   grep -r "baseURL\|API_BASE_URL\|apiUrl" frontend/src/
   ```

2. **Network Tab Analysis**:
   - Open browser Developer Tools → Network tab
   - Refresh the dashboard
   - Look for API calls being made
   - Record the base URLs being used

3. **AWS Infrastructure Check**:
   ```bash
   # Find API Gateway APIs
   aws apigateway get-rest-apis --query "items[].{id:id,name:name}"
   
   # Find Lambda functions
   aws lambda list-functions --query "Functions[?contains(FunctionName, 'bff') || contains(FunctionName, 'operation')].FunctionName"
   ```

**Expected Evidence:**
```
Frontend API Configuration:
✅ Base URL found: [URL from code]
✅ Operations endpoint: [endpoint path]

Network Tab API Calls:
✅ API calls to: [List of URLs being called]
❌ Failed calls: [URLs returning errors]

AWS Infrastructure:
✅ API Gateway IDs: [List API Gateway IDs]
✅ Lambda Functions: [List relevant Lambda function names]
```

---

## 🔍 **Test 5: Direct API Testing**

### **Objective**: Test API endpoints directly to isolate issues

**Prerequisites**: You need the API endpoint URL from Test 4

**Steps:**
1. **Test with curl** (replace with your actual API URL):
   ```bash
   # Test instances endpoint
   curl -X GET "https://your-api-gateway-id.execute-api.ap-southeast-1.amazonaws.com/prod/api/instances" \
        -H "Authorization: Bearer YOUR_JWT_TOKEN" \
        -H "Content-Type: application/json"
   
   # Test operations endpoint
   curl -X POST "https://your-api-gateway-id.execute-api.ap-southeast-1.amazonaws.com/prod/api/operations" \
        -H "Authorization: Bearer YOUR_JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"instanceId":"tb-pg-db1","operation":"stop","region":"ap-southeast-1"}'
   ```

2. **Get JWT Token**:
   - From browser Developer Tools → Application tab → Local Storage
   - Look for authentication tokens
   - Or from Network tab → Copy Authorization header from a working request

**Expected Evidence:**
```
Instances API Test:
✅ Status: 200 OK
✅ Response: [JSON with instance list]
❌ Status: 400/403/500
❌ Error: [Exact error message]

Operations API Test:
❌ Status: 400 Bad Request
❌ Error: [Exact error message - this is the key evidence!]
```

---

## 🔍 **Test 6: Lambda Function Direct Testing**

### **Objective**: Test Lambda functions directly to isolate the issue

**Steps:**
1. **Find Lambda Function Names**:
   ```bash
   aws lambda list-functions --query "Functions[?contains(FunctionName, 'operation')].FunctionName"
   ```

2. **Test Operations Lambda Directly**:
   ```bash
   aws lambda invoke \
     --function-name rds-operations-handler-prod \
     --payload '{"instanceId":"tb-pg-db1","operation":"stop","region":"ap-southeast-1","userIdentity":{"sub":"test-user"}}' \
     response.json
   
   cat response.json
   ```

3. **Check Lambda Logs**:
   ```bash
   aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'operation')].logGroupName"
   aws logs tail /aws/lambda/rds-operations-handler-prod --follow
   ```

**Expected Evidence:**
```
Lambda Direct Test:
✅ Function exists: rds-operations-handler-prod
❌ Invocation result: [Status code and error]
❌ Response content: [Content of response.json]
❌ CloudWatch logs: [Recent error messages]
```

---

## 📊 **Evidence Collection Template**

Use this template to record your findings:

```markdown
# Evidence Collection - [Date]

## Test 1: Frontend Dashboard Access
- Dashboard URL: 
- Login Status: ✅/❌
- Console Errors: 

## Test 2: Instance Operations 400 Error
- Request URL: 
- Request Method: 
- Request Headers: 
- Request Body: 
- Response Status: 
- Response Error: 

## Test 3: Cross-Account Instance Visibility
- AWS Console Account 1 Instances: 
- AWS Console Account 2 Instances: 
- Dashboard Shows: 
- Missing from Dashboard: 

## Test 4: API Endpoint Discovery
- Frontend API Base URL: 
- Network Tab API Calls: 
- API Gateway IDs: 
- Lambda Function Names: 

## Test 5: Direct API Testing
- Instances API Result: 
- Operations API Result: 
- JWT Token Status: 

## Test 6: Lambda Function Direct Testing
- Lambda Function Names: 
- Direct Invocation Result: 
- CloudWatch Log Errors: 

## Summary
- What definitely works: 
- What definitely doesn't work: 
- Root cause hypothesis: 
```

---

## 🎯 **Next Steps After Evidence Collection**

1. **Analyze the Evidence**: Look for patterns in what's working vs broken
2. **Identify the Specific Failure Point**: Don't assume - use the evidence
3. **Create Targeted Fix**: Fix only the specific broken component
4. **Test the Fix**: Re-run the relevant test to confirm it works
5. **Move to Next Issue**: Only after confirming the fix works

## 🚫 **What NOT to Do**

- ❌ Don't run "comprehensive fix scripts" without evidence
- ❌ Don't assume what's broken based on error messages alone
- ❌ Don't fix multiple things at once
- ❌ Don't trust previous status documents claiming things are "FIXED"
- ❌ Don't deploy changes without testing them first

## ✅ **What TO Do**

- ✅ Test each component independently
- ✅ Capture exact error messages and request/response data
- ✅ Fix one specific issue at a time
- ✅ Validate each fix before moving to the next
- ✅ Document what actually works vs what's broken

---

**This evidence-based approach will finally identify the real root causes instead of guessing.**