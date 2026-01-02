# CORS Verification and Testing Guide

This guide provides comprehensive instructions for verifying and testing CORS (Cross-Origin Resource Sharing) configuration in the RDS Operations Dashboard.

## Overview

The CORS verification suite includes multiple tools to ensure your CORS configuration is working correctly across different scenarios and environments.

## Available Tools

### 1. Master Verification Suite
**File:** `scripts/cors-verification-suite.ps1`
**Purpose:** Orchestrates all CORS verification tools in a single command

```powershell
# Run complete verification suite
.\scripts\cors-verification-suite.ps1 -Environment production

# Run with custom URLs
.\scripts\cors-verification-suite.ps1 -BffUrl "https://api.example.com" -FrontendUrl "https://app.example.com"

# Run with browser test
.\scripts\cors-verification-suite.ps1 -OpenBrowserTest

# Skip specific tests
.\scripts\cors-verification-suite.ps1 -SkipDiagnostics -SkipDeploymentVerification
```

### 2. Comprehensive CORS Testing
**File:** `scripts/test-cors-comprehensive.ps1`
**Purpose:** Tests CORS functionality across different request types and origins

```powershell
# Basic comprehensive test
.\scripts\test-cors-comprehensive.ps1

# Test with specific URLs
.\scripts\test-cors-comprehensive.ps1 -BffUrl "https://api.example.com" -AllowedOrigin "https://app.example.com"

# Test with verbose output
.\scripts\test-cors-comprehensive.ps1 -Verbose

# Test unauthorized origin rejection
.\scripts\test-cors-comprehensive.ps1 -TestOrigin "https://malicious-site.com"
```

**Tests Performed:**
- ✅ OPTIONS preflight requests from allowed origins
- ✅ GET requests from allowed origins
- ✅ POST requests with JSON content
- ✅ Requests from disallowed origins (should fail)
- ✅ Requests without Origin header
- ✅ Complex requests with custom headers
- ✅ Authenticated requests with credentials

### 3. CORS Issues Diagnostics
**File:** `scripts/diagnose-cors-issues.ps1`
**Purpose:** Provides detailed diagnostic information and resolution steps

```powershell
# Basic diagnostics
.\scripts\diagnose-cors-issues.ps1

# Include Lambda configuration check
.\scripts\diagnose-cors-issues.ps1 -CheckLambda

# Include API Gateway check
.\scripts\diagnose-cors-issues.ps1 -CheckApiGateway

# Full diagnostics with verbose output
.\scripts\diagnose-cors-issues.ps1 -CheckLambda -CheckApiGateway -Verbose
```

**Diagnostic Checks:**
- 🔍 Basic connectivity to BFF
- 🔍 CORS headers analysis
- 🔍 Environment configuration validation
- 🔍 Lambda function environment variables
- 🔍 Browser compatibility assessment

### 4. Deployment Verification
**File:** `scripts/verify-cors-deployment.ps1`
**Purpose:** Verifies CORS configuration after deployment

```powershell
# Verify production deployment
.\scripts\verify-cors-deployment.ps1 -Environment production

# Verify staging deployment
.\scripts\verify-cors-deployment.ps1 -Environment staging

# Detailed verification report
.\scripts\verify-cors-deployment.ps1 -Detailed

# Skip browser test generation
.\scripts\verify-cors-deployment.ps1 -SkipBrowserTest
```

**Verification Steps:**
- ✅ Pre-deployment validation
- ✅ CORS preflight verification
- ✅ Actual request verification
- ✅ Security verification
- ✅ Browser compatibility test generation

### 5. Browser-Based Testing
**File:** `test-cors-browser-comprehensive.html`
**Purpose:** Interactive browser-based CORS testing

**Usage:**
1. Open the HTML file in a web browser
2. Ensure you're accessing it from your frontend domain
3. Configure the BFF URL
4. Run individual tests or the complete suite
5. Download detailed test reports

**Browser Tests:**
- 🌐 Basic connectivity test
- 🌐 CORS preflight (OPTIONS) requests
- 🌐 Simple GET requests
- 🌐 POST requests with JSON
- 🌐 Authenticated requests with credentials
- 🌐 Custom headers testing
- 🌐 Error handling verification
- 🌐 Network timing analysis

## Environment-Specific Testing

### Production Environment
```powershell
.\scripts\cors-verification-suite.ps1 -Environment production -BffUrl "https://api.rds-dashboard.example.com" -FrontendUrl "https://d2qvaswtmn22om.cloudfront.net"
```

### Staging Environment
```powershell
.\scripts\cors-verification-suite.ps1 -Environment staging -BffUrl "https://staging-api.rds-dashboard.example.com" -FrontendUrl "https://staging-d2qvaswtmn22om.cloudfront.net"
```

### Development Environment
```powershell
.\scripts\cors-verification-suite.ps1 -Environment development -BffUrl "http://localhost:3001" -FrontendUrl "http://localhost:3000"
```

## Common CORS Issues and Solutions

### Issue 1: Missing Access-Control-Allow-Origin Header
**Symptoms:** Browser console shows "CORS policy" errors
**Solution:** 
1. Check BFF CORS middleware configuration
2. Verify `CORS_ORIGINS` environment variable
3. Ensure origin validation is working

### Issue 2: Preflight Requests Failing
**Symptoms:** OPTIONS requests return errors
**Solution:**
1. Verify OPTIONS method is allowed
2. Check `Access-Control-Allow-Methods` header
3. Ensure `Access-Control-Allow-Headers` includes required headers

### Issue 3: Credentials Not Working
**Symptoms:** Authentication fails in cross-origin requests
**Solution:**
1. Set `credentials: true` in CORS configuration
2. Ensure `Access-Control-Allow-Credentials: true` header
3. Never use wildcard origin (*) with credentials

### Issue 4: Custom Headers Rejected
**Symptoms:** Requests with custom headers fail
**Solution:**
1. Add custom headers to `Access-Control-Allow-Headers`
2. Ensure preflight requests handle custom headers
3. Check header name spelling and case

## Troubleshooting Workflow

### Step 1: Run Diagnostics
```powershell
.\scripts\diagnose-cors-issues.ps1 -CheckLambda -Verbose
```

### Step 2: Fix Identified Issues
- Update environment variables
- Redeploy BFF if needed
- Verify configuration changes

### Step 3: Run Comprehensive Test
```powershell
.\scripts\test-cors-comprehensive.ps1 -Verbose
```

### Step 4: Verify Deployment
```powershell
.\scripts\verify-cors-deployment.ps1 -Detailed
```

### Step 5: Browser Testing
1. Open `test-cors-browser-comprehensive.html`
2. Run tests from actual frontend domain
3. Verify all tests pass

## Automated Testing Integration

### CI/CD Pipeline Integration
```yaml
# Example GitHub Actions step
- name: Verify CORS Configuration
  run: |
    .\scripts\cors-verification-suite.ps1 -Environment staging
  shell: powershell
```

### Monitoring Integration
```powershell
# Schedule regular CORS verification
.\scripts\cors-verification-suite.ps1 -Environment production > cors-check.log 2>&1
```

## Security Considerations

### ✅ Best Practices
- Use specific origins instead of wildcards
- Enable credentials only when needed
- Validate all origins against allowlist
- Log security events for rejected origins
- Regular verification of CORS configuration

### ❌ Security Anti-Patterns
- Never use `Access-Control-Allow-Origin: *` with credentials
- Don't allow all headers without validation
- Avoid overly permissive CORS policies
- Don't ignore CORS errors in development

## Performance Optimization

### Preflight Caching
- Set appropriate `Access-Control-Max-Age` (recommended: 86400 seconds)
- Minimize preflight requests by using simple requests when possible

### Header Optimization
- Only include necessary headers in `Access-Control-Allow-Headers`
- Use `Access-Control-Expose-Headers` for response headers needed by frontend

## Reporting and Monitoring

### Generated Reports
All verification tools generate JSON reports with detailed results:
- `cors-verification-suite-report-{environment}-{timestamp}.json`
- `cors-verification-report-{environment}-{timestamp}.json`

### Log Analysis
Monitor CloudWatch logs for CORS-related entries:
```
[CORS] Origin validation failed: https://malicious-site.com
[CORS] Preflight request from allowed origin: https://app.example.com
```

## Support and Troubleshooting

### Common Commands
```powershell
# Quick health check
.\scripts\test-cors-comprehensive.ps1 -BffUrl "YOUR_BFF_URL"

# Full diagnostic
.\scripts\diagnose-cors-issues.ps1 -CheckLambda -CheckApiGateway -Verbose

# Post-deployment verification
.\scripts\verify-cors-deployment.ps1 -Environment production -Detailed
```

### Getting Help
1. Review generated diagnostic reports
2. Check CloudWatch logs for CORS errors
3. Verify environment variables are set correctly
4. Test with browser developer tools
5. Contact support with verification report

## Maintenance

### Regular Tasks
- Run verification suite after any CORS configuration changes
- Monitor CORS-related errors in application logs
- Update verification scripts when adding new API endpoints
- Review and update allowed origins list periodically

### Version Updates
When updating the BFF or CORS middleware:
1. Run full verification suite before deployment
2. Test in staging environment first
3. Verify all existing functionality still works
4. Update documentation if CORS behavior changes