# Security Issues - JWT Tokens & Hardcoded Passwords - Resolution

**Date:** December 6, 2025  
**Issues:**
- Sonar S8135 - JSON Web Tokens should not be disclosed
- Snyk - Hardcoded passwords in test code  
**Severity:** Critical  
**Status:** ✅ Resolved

## Issue Description

Sonar detected JWT tokens in the codebase that appeared to be real credentials. The security scanner flagged:

```
Make sure this JSON Web Token (JWT) gets revoked, changed, and removed from the code.
JSON Web Tokens should not be disclosed
secrets:S8135
```

## Root Cause

The JWT tokens found were **test examples** used in:
1. `lambda/tests/test_sensitive_data_redaction.py` - Unit tests for JWT redaction functionality
2. `lambda/shared/structured_logger.py` - Example code demonstrating sanitization

The token `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U` is a well-known example JWT from JWT.io documentation that decodes to:
- Header: `{"alg":"HS256","typ":"JWT"}`
- Payload: `{"sub":"1234567890"}`

**This was NOT a real credential**, but static analysis tools cannot distinguish between real and test tokens.

## Resolution

Replaced all JWT-like patterns in test code with clearly fake/placeholder values:

### Before
```python
text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
```

### After
```python
# Using a fake JWT-like pattern for testing (not a real token)
fake_jwt = "eyJTEST.eyJTEST.FAKE_SIGNATURE_FOR_TESTING_ONLY"
text = f"Authorization: Bearer {fake_jwt}"
```

## Files Modified

1. **lambda/tests/test_sensitive_data_redaction.py**
   - `test_jwt_token_redaction()` - Replaced with fake JWT pattern
   - `test_multiple_patterns_in_string()` - Replaced with fake JWT pattern

2. **lambda/shared/structured_logger.py**
   - Example code in `__main__` section - Replaced with fake JWT pattern

## Verification

✅ All 20 tests in `test_sensitive_data_redaction.py` pass  
✅ No real JWT tokens remain in codebase  
✅ JWT redaction functionality still works correctly  
✅ TypeScript compilation successful (frontend fixes)

## Best Practices Applied

1. **Never use real-looking tokens in test code** - Even example tokens from documentation can trigger security scanners
2. **Use obviously fake patterns** - Patterns like `eyJTEST.eyJTEST.FAKE_SIG` are clearly not real tokens
3. **Add comments** - Explicitly state that tokens are fake/for testing only
4. **Test the redaction, not the token** - Focus tests on the redaction logic, not on realistic token formats

## Additional Context

This fix was part of addressing TypeScript errors and security issues identified during code quality review:

1. ✅ Fixed React Query v5 migration (`cacheTime` → `gcTime`)
2. ✅ Fixed Sonar JWT token disclosure warning
3. ✅ Maintained test coverage for sensitive data redaction

## Governance Compliance

**AI SDLC Governance Framework Compliance:**
- ✅ Security gate passed (no real credentials in code)
- ✅ Test coverage maintained (20/20 tests passing)
- ✅ External analysis integration (Sonar findings addressed)
- ✅ Documentation updated

**Traceability:**
- Requirements: REQ-6.4 (Data Security)
- Design: DESIGN-6.4 (Sensitive Data Redaction)
- Task: TASK-4.4 (Implement Logging Enhancements)

## Issue 2: Hardcoded Test Passwords (Snyk)

### Root Cause

Snyk detected hardcoded passwords in example/test code across multiple logger files:
- `lambda/shared/logger.py`
- `lambda/discovery/shared/logger.py`
- `lambda/health-monitor/shared/logger.py`
- `lambda/query-handler/shared/logger.py`
- `lambda/operations/shared/logger.py`
- `lambda/cloudops-generator/shared/logger.py`
- `lambda/compliance-checker/shared/logger.py`
- `lambda/cost-analyzer/shared/logger.py`

The passwords were in example code sections (under `if __name__ == '__main__'`) used to demonstrate the sanitization functionality.

### Resolution

Replaced all hardcoded test passwords with obviously fake placeholder values:

**Before:**
```python
sensitive_data = {
    'username': 'john.doe',
    'password': 'secret123',      # ❌ Looks like a real password
    'api_key': 'abc123',          # ❌ Looks like a real API key
    'instance_id': 'i-1234567890'
}
```

**After:**
```python
# Test sanitization (using fake test data - not real credentials)
sensitive_data = {
    'username': 'john.doe',
    'password': 'FAKE_PASSWORD_FOR_TESTING',  # ✅ Clearly fake
    'api_key': 'FAKE_API_KEY_FOR_TESTING',    # ✅ Clearly fake
    'instance_id': 'i-1234567890'
}
```

### Files Modified

**Logger Files (8 files):**
- `lambda/shared/logger.py`
- `lambda/discovery/shared/logger.py`
- `lambda/health-monitor/shared/logger.py`
- `lambda/query-handler/shared/logger.py`
- `lambda/operations/shared/logger.py`
- `lambda/cloudops-generator/shared/logger.py`
- `lambda/compliance-checker/shared/logger.py`
- `lambda/cost-analyzer/shared/logger.py`

### Verification

✅ No instances of `secret123` remain in any logger files  
✅ All test passwords replaced with `FAKE_PASSWORD_FOR_TESTING`  
✅ All test API keys replaced with `FAKE_API_KEY_FOR_TESTING`  
✅ Comments added to clarify these are fake test values

---

**Conclusion:** Both JWT tokens and hardcoded passwords were never real credentials - they were test examples. However, following security best practices, we've replaced them with obviously fake patterns to avoid triggering security scanners and to make it crystal clear that these are not real credentials.
