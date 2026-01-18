#!/usr/bin/env pwsh

# Simple logout flow test
Write-Host "Testing Logout Flow" -ForegroundColor Yellow

# Configuration
$CognitoDomain = "rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com"
$ClientId = "28e031hsul0mi91k0s6f33bs7s"
$CloudFrontDomain = "https://d2qvaswtmn22om.cloudfront.net"
$UserPoolId = "ap-southeast-1_4tyxh4qJe"

Write-Host ""
Write-Host "1. Testing Cognito App Client Configuration..." -ForegroundColor Cyan
try {
    $config = aws cognito-idp describe-user-pool-client --user-pool-id $UserPoolId --client-id $ClientId --query 'UserPoolClient.{CallbackURLs:CallbackURLs,LogoutURLs:LogoutURLs}' --output json | ConvertFrom-Json
    
    Write-Host "Callback URLs:" -ForegroundColor Gray
    $config.CallbackURLs | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
    
    Write-Host "Logout URLs:" -ForegroundColor Gray
    $config.LogoutURLs | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
    
    $hasCloudFrontLogout = $config.LogoutURLs -contains "$CloudFrontDomain/"
    if ($hasCloudFrontLogout) {
        Write-Host "PASS: CloudFront logout URL is configured" -ForegroundColor Green
    } else {
        Write-Host "FAIL: CloudFront logout URL is missing" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: Error checking Cognito configuration: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Testing Frontend Implementation..." -ForegroundColor Cyan
$cognitoTsPath = "frontend/src/lib/auth/cognito.ts"
if (Test-Path $cognitoTsPath) {
    $content = Get-Content $cognitoTsPath -Raw
    
    if ($content -match "redirect_uri=") {
        Write-Host "PASS: Frontend uses redirect_uri parameter (correct for Cognito OAuth2)" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Frontend does not use redirect_uri parameter" -ForegroundColor Red
    }
    
    if ($content -match "encodeURIComponent") {
        Write-Host "PASS: Frontend properly encodes logout URL" -ForegroundColor Green
    } else {
        Write-Host "FAIL: Frontend does not encode logout URL" -ForegroundColor Red
    }
} else {
    Write-Host "FAIL: Frontend file not found: $cognitoTsPath" -ForegroundColor Red
}

Write-Host ""
Write-Host "3. Testing Dashboard Accessibility..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri $CloudFrontDomain -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -eq 200) {
        Write-Host "PASS: CloudFront dashboard is accessible" -ForegroundColor Green
    } else {
        Write-Host "FAIL: CloudFront dashboard returned status: $($response.StatusCode)" -ForegroundColor Red
    }
} catch {
    Write-Host "FAIL: Error accessing dashboard: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Manual Testing Steps:" -ForegroundColor Yellow
Write-Host "1. Open: $CloudFrontDomain" -ForegroundColor White
Write-Host "2. Login with test credentials" -ForegroundColor White
Write-Host "3. Click the logout button" -ForegroundColor White
Write-Host "4. Verify clean redirect to login page" -ForegroundColor White
Write-Host "5. Check browser console for any errors" -ForegroundColor White

Write-Host ""
Write-Host "Logout flow test completed!" -ForegroundColor Green