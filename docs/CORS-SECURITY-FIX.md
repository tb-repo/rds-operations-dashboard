# CORS Security Fix - Origin Validation

**Date:** December 6, 2025  
**Issue:** Overly Permissive CORS Policy  
**Tool:** Snyk  
**Severity:** Medium  
**Status:** ✅ Fixed (1/4 files), 🔄 In Progress (3/4 files)

## Overview

Snyk identified overly permissive CORS policies using wildcard `*` in Lambda handlers. This allows malicious code on any domain to communicate with the application, which is a security risk.

## Vulnerability Details

### Affected Files
1. ✅ `lambda/approval-workflow/handler.py` - FIXED
2. 🔄 `lambda/cloudops-generator/handler.py` - TODO
3. 🔄 `lambda/operations/handler.py` - TODO  
4. 🔄 `lambda/query-handler/handler.py` - TODO

### Vulnerable Code

```python
# ❌ INSECURE: Allows requests from ANY origin
return {
    'statusCode': 200,
    'headers': {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'  # Wildcard allows all origins!
    },
    'body': json.dumps(data)
}
```

### Security Risk

**CORS Wildcard (`*`) Risks:**
1. **Cross-Site Request Forgery (CSRF)** - Malicious sites can make requests
2. **Data Exposure** - Sensitive data accessible from any domain
3. **Session Hijacking** - Credentials can be stolen
4. **Compliance Violations** - Fails security audits

**Attack Scenario:**
```javascript
// Malicious website: evil.com
fetch('https://your-api.amazonaws.com/prod/instances', {
    method: 'GET',
    credentials: 'include'  // Sends cookies/auth
})
.then(r => r.json())
.then(data => {
    // Attacker now has your sensitive data!
    sendToAttacker(data);
});
```

## Fix Implementation

### Solution: Origin Validation

Created `lambda/shared/cors_helper.py` with secure CORS handling:

```python
def get_cors_headers(event: Optional[Dict] = None) -> Dict[str, str]:
    """
    Get CORS headers with validated origin.
    
    Security:
        - Reads allowed origins from environment variable
        - Validates request origin against allowlist
        - Never uses wildcard "*"
    """
    # Get allowed origins from environment
    allowed_origins_str = os.environ.get(
        'ALLOWED_ORIGINS',
        'https://dashboard.example.com'
    )
    
    allowed_origins = [origin.strip() for origin in allowed_origins_str.split(',')]
    
    # Get request origin
    request_origin = None
    if event and 'headers' in event:
        headers = event['headers']
        request_origin = headers.get('origin') or headers.get('Origin')
    
    # Validate origin
    if request_origin and request_origin in allowed_origins:
        allowed_origin = request_origin
    else:
        allowed_origin = allowed_origins[0]
    
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': allowed_origin,  # ✅ Validated origin
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
        'Access-Control-Allow-Credentials': 'true',
        'Vary': 'Origin'
    }
```

### Updated Code Pattern

```python
# ✅ SECURE: Validates origin against allowlist
from shared.cors_helper import get_cors_headers, is_preflight_request, handle_preflight

def lambda_handler(event, context):
    # Handle CORS preflight
    if is_preflight_request(event):
        return handle_preflight(event)
    
    try:
        # Your logic here
        return {
            'statusCode': 200,
            'headers': get_cors_headers(event),  # ✅ Secure CORS
            'body': json.dumps(data)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': get_cors_headers(event),  # ✅ Secure CORS
            'body': json.dumps({'error': str(e)})
        }
```

## Implementation Steps

### Step 1: Create CORS Helper ✅
- Created `lambda/shared/cors_helper.py`
- Implements origin validation
- Handles preflight requests

### Step 2: Update Lambda Handlers

**Completed:**
- ✅ `lambda/approval-workflow/handler.py`

**Remaining:**
- 🔄 `lambda/cloudops-generator/handler.py`
- 🔄 `lambda/operations/handler.py`
- 🔄 `lambda/query-handler/handler.py`

**Changes Required for Each File:**

1. Add import:
```python
from shared.cors_helper import get_cors_headers, is_preflight_request, handle_preflight
```

2. Add preflight handling at start of handler:
```python
if is_preflight_request(event):
    return handle_preflight(event)
```

3. Replace all CORS headers:
```python
# Before
'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'}

# After
'headers': get_cors_headers(event)
```

### Step 3: Configure Environment Variables

Set `ALLOWED_ORIGINS` in Lambda configuration:

```bash
# Development
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173

# Production
ALLOWED_ORIGINS=https://dashboard.example.com,https://admin.example.com
```

### Step 4: Update Infrastructure Code

Update CDK/CloudFormation to set environment variables:

```typescript
// In Lambda function definition
environment: {
  ALLOWED_ORIGINS: process.env.FRONTEND_URL || 'https://dashboard.example.com'
}
```

## Testing

### Test 1: Allowed Origin
```bash
curl -X GET https://your-api.amazonaws.com/prod/instances \
  -H "Origin: https://dashboard.example.com" \
  -v
  
# Expected: Access-Control-Allow-Origin: https://dashboard.example.com
```

### Test 2: Disallowed Origin
```bash
curl -X GET https://your-api.amazonaws.com/prod/instances \
  -H "Origin: https://evil.com" \
  -v
  
# Expected: Access-Control-Allow-Origin: https://dashboard.example.com
# (Not evil.com - browser will block the response)
```

### Test 3: Preflight Request
```bash
curl -X OPTIONS https://your-api.amazonaws.com/prod/instances \
  -H "Origin: https://dashboard.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -v
  
# Expected: 200 OK with CORS headers
```

## Security Benefits

### Before (Insecure)
- ❌ Any website can make requests
- ❌ No origin validation
- ❌ Vulnerable to CSRF
- ❌ Data exposure risk

### After (Secure)
- ✅ Only allowed origins can make requests
- ✅ Origin validated against allowlist
- ✅ CSRF protection
- ✅ Data protected from unauthorized domains
- ✅ Compliance with security standards

## Deployment Checklist

- [x] Create `cors_helper.py`
- [x] Update `approval-workflow/handler.py`
- [ ] Update `cloudops-generator/handler.py`
- [ ] Update `operations/handler.py`
- [ ] Update `query-handler/handler.py`
- [ ] Set `ALLOWED_ORIGINS` environment variable
- [ ] Update infrastructure code (CDK/CloudFormation)
- [ ] Test with allowed origins
- [ ] Test with disallowed origins
- [ ] Deploy to development
- [ ] Verify frontend still works
- [ ] Deploy to production

## Rollback Plan

If issues occur after deployment:

1. **Quick Fix:** Set `ALLOWED_ORIGINS=*` temporarily (reverts to wildcard)
2. **Proper Fix:** Add missing origin to allowed list
3. **Emergency:** Revert Lambda function to previous version

## References

- **CWE-942:** Overly Permissive Cross-domain Whitelist
- **OWASP:** Cross-Origin Resource Sharing (CORS)
- **MDN:** CORS Best Practices

---

**Status:** Partially Complete (1/4 files fixed)  
**Next Action:** Complete remaining 3 Lambda handlers  
**Priority:** High (Security Issue)
