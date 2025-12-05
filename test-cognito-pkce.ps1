# Test Cognito PKCE Flow
# This script tests the PKCE flow with AWS Cognito to diagnose authentication issues

$ErrorActionPreference = "Stop"

# Configuration
$userPoolId = "ap-southeast-1_4tyxh4qJe"
$clientId = "28e031hsul0mi91k0s6f33bs7s"
$domain = "rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com"
$redirectUri = "http://localhost:3000/callback"

Write-Host "=== Cognito PKCE Flow Test ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check User Pool Client Configuration
Write-Host "Step 1: Checking User Pool Client Configuration..." -ForegroundColor Yellow
$clientConfig = aws cognito-idp describe-user-pool-client `
    --user-pool-id $userPoolId `
    --client-id $clientId `
    --query 'UserPoolClient' `
    --output json | ConvertFrom-Json

Write-Host "Client ID: $($clientConfig.ClientId)" -ForegroundColor Green
Write-Host "Client Name: $($clientConfig.ClientName)" -ForegroundColor Green
Write-Host "Has Client Secret: $($null -ne $clientConfig.ClientSecret)" -ForegroundColor $(if ($null -eq $clientConfig.ClientSecret) { "Green" } else { "Red" })
Write-Host "OAuth Flows: $($clientConfig.AllowedOAuthFlows -join ', ')" -ForegroundColor Green
Write-Host "OAuth Flows Enabled: $($clientConfig.AllowedOAuthFlowsUserPoolClient)" -ForegroundColor $(if ($clientConfig.AllowedOAuthFlowsUserPoolClient) { "Green" } else { "Red" })
Write-Host "Callback URLs: $($clientConfig.CallbackURLs -join ', ')" -ForegroundColor Green
Write-Host "Supported Identity Providers: $($clientConfig.SupportedIdentityProviders -join ', ')" -ForegroundColor Green
Write-Host ""

# Step 2: Check if callback URL matches
Write-Host "Step 2: Verifying Callback URL Configuration..." -ForegroundColor Yellow
if ($clientConfig.CallbackURLs -contains $redirectUri) {
    Write-Host "✓ Callback URL '$redirectUri' is configured" -ForegroundColor Green
} else {
    Write-Host "✗ Callback URL '$redirectUri' is NOT configured" -ForegroundColor Red
    Write-Host "  Configured URLs: $($clientConfig.CallbackURLs -join ', ')" -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Test PKCE Parameter Generation (JavaScript simulation)
Write-Host "Step 3: Testing PKCE Parameter Generation..." -ForegroundColor Yellow
Write-Host "  This would normally be done in the browser using Web Crypto API" -ForegroundColor Gray
Write-Host "  Code Verifier: 43-128 characters, base64url encoded" -ForegroundColor Gray
Write-Host "  Code Challenge: SHA-256 hash of verifier, base64url encoded" -ForegroundColor Gray
Write-Host ""

# Step 4: Check for common issues
Write-Host "Step 4: Checking for Common Issues..." -ForegroundColor Yellow

$issues = @()

if ($null -ne $clientConfig.ClientSecret) {
    $issues += "Client has a secret - PKCE requires a public client without secret"
}

if ($clientConfig.AllowedOAuthFlows -notcontains "code") {
    $issues += "Authorization code flow is not enabled"
}

if (-not $clientConfig.AllowedOAuthFlowsUserPoolClient) {
    $issues += "OAuth flows are not enabled for this client"
}

if ($clientConfig.CallbackURLs -notcontains $redirectUri) {
    $issues += "Redirect URI mismatch - '$redirectUri' not in configured callbacks"
}

if ($issues.Count -eq 0) {
    Write-Host "✓ No configuration issues found" -ForegroundColor Green
} else {
    Write-Host "✗ Found $($issues.Count) issue(s):" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}
Write-Host ""

# Step 5: Recommendations
Write-Host "Step 5: Recommendations..." -ForegroundColor Yellow

Write-Host @"
To fix the 'invalid_grant' error, try the following:

1. **Clear Browser State**: 
   - Clear all cookies, local storage, and session storage for localhost:3000
   - Or use an incognito/private window

2. **Check Authorization Code Usage**:
   - Authorization codes can only be used ONCE
   - If the callback page reloads, the code becomes invalid
   - Ensure the callback component prevents duplicate token exchange attempts

3. **Verify PKCE Implementation**:
   - Code verifier must be 43-128 characters
   - Code challenge must be SHA-256 hash of verifier, base64url encoded
   - Both must use URL-safe characters (no +, /, or =)

4. **Check Timing**:
   - Authorization codes expire after a short time (typically 5-10 minutes)
   - Ensure token exchange happens immediately after redirect

5. **Test with Cognito Hosted UI**:
   - Try logging in directly through Cognito Hosted UI
   - URL: https://$domain/login?client_id=$clientId&response_type=code&scope=openid+email+profile&redirect_uri=$redirectUri

6. **Enable CloudWatch Logs**:
   - Enable Cognito User Pool logs in CloudWatch
   - Check for detailed error messages

"@ -ForegroundColor Cyan

Write-Host "=== Test Complete ===" -ForegroundColor Cyan
