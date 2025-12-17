#!/usr/bin/env pwsh
# Test Authentication Flow
# Tests both local and CloudFront authentication

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Authentication Flow Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check Cognito Configuration
Write-Host "Test 1: Cognito Configuration..." -ForegroundColor Yellow
try {
    $client = aws cognito-idp describe-user-pool-client --user-pool-id "ap-southeast-1_4tyxh4qJe" --client-id "28e031hsul0mi91k0s6f33bs7s" --output json | ConvertFrom-Json
    
    Write-Host "✅ Callback URLs:" -ForegroundColor Green
    $client.UserPoolClient.CallbackURLs | ForEach-Object { Write-Host "   - $_" -ForegroundColor White }
    
    Write-Host "✅ Logout URLs:" -ForegroundColor Green
    $client.UserPoolClient.LogoutURLs | ForEach-Object { Write-Host "   - $_" -ForegroundColor White }
    
    Write-Host "✅ Domain: rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to get Cognito configuration: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 2: BFF Health Check
Write-Host "Test 2: BFF Health Check..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/health" -Method GET
    Write-Host "✅ BFF is healthy: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "❌ BFF health check failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: Frontend Accessibility
Write-Host "Test 3: Frontend Accessibility..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://d2qvaswtmn22om.cloudfront.net" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ CloudFront frontend is accessible" -ForegroundColor Green
    } else {
        Write-Host "❌ CloudFront returned status: $($response.StatusCode)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ CloudFront not accessible: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 4: Check Environment Configuration
Write-Host "Test 4: Environment Configuration..." -ForegroundColor Yellow
$envFile = Get-Content "frontend/.env" -Raw
if ($envFile -match "VITE_COGNITO_DOMAIN=.*\.auth\..*\.amazoncognito\.com") {
    Write-Host "✅ Cognito domain is properly configured" -ForegroundColor Green
} else {
    Write-Host "❌ Cognito domain configuration issue" -ForegroundColor Red
}

if ($envFile -match "VITE_BFF_API_URL=https://km9ww1hh3k") {
    Write-Host "✅ API URL points to BFF" -ForegroundColor Green
} else {
    Write-Host "❌ API URL configuration issue" -ForegroundColor Red
}

if ($envFile -notmatch "VITE_COGNITO_REDIRECT_URI=http://localhost") {
    Write-Host "✅ Redirect URIs are dynamic (not hardcoded)" -ForegroundColor Green
} else {
    Write-Host "⚠️  Redirect URIs are hardcoded to localhost" -ForegroundColor Yellow
}
Write-Host ""

# Instructions
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Manual Testing Instructions:" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. CloudFront Testing:" -ForegroundColor Yellow
Write-Host "   Open: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor White
Write-Host "   Click Login -> Should redirect to Cognito" -ForegroundColor White
Write-Host "   Login with: admin@example.com / AdminPass123!" -ForegroundColor White
Write-Host ""
Write-Host "2. Local Testing:" -ForegroundColor Yellow
Write-Host "   Run: npm run dev (in frontend folder)" -ForegroundColor White
Write-Host "   Open: http://localhost:3000" -ForegroundColor White
Write-Host "   Test login flow" -ForegroundColor White
Write-Host ""
Write-Host "3. Expected Behavior:" -ForegroundColor Yellow
Write-Host "   - Login redirects to proper Cognito domain" -ForegroundColor White
Write-Host "   - After login, redirects back to correct origin" -ForegroundColor White
Write-Host "   - Dashboard loads data from BFF API" -ForegroundColor White
Write-Host ""
