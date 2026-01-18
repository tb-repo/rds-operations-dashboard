#!/usr/bin/env pwsh
# Comprehensive diagnostic for all 5 critical production issues

Write-Host "=== COMPREHENSIVE DIAGNOSTIC FOR CRITICAL PRODUCTION ISSUES ===" -ForegroundColor Yellow
Write-Host "Testing all 5 critical issues to understand current state" -ForegroundColor Cyan
Write-Host ""

# Configuration
$bffUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"
$frontendUrl = "https://d3v8k9l2m4n5o6.cloudfront.net"

# Issue 1: Test BFF API endpoint
Write-Host "1. Testing BFF API Endpoint..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$bffUrl/api/health" -Method GET -TimeoutSec 10
    Write-Host "   ✅ BFF API is responding" -ForegroundColor Green
    Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ BFF API not responding: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Issue 2: Test operations endpoint (without auth - expect 401)
Write-Host ""
Write-Host "2. Testing Operations Endpoint (without auth)..." -ForegroundColor Green
try {
    $body = @{
        instance_id = "test"
        operation = "stop"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri "$bffUrl/api/operations" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
    Write-Host "   ⚠️  Operations endpoint responded without auth (unexpected)" -ForegroundColor Yellow
    Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "   ✅ Operations endpoint requires auth (expected 401)" -ForegroundColor Green
    } elseif ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "   ⚠️  Operations endpoint returned 400 (validation error)" -ForegroundColor Yellow
    } else {
        Write-Host "   ❌ Operations endpoint error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Issue 3: Test instances endpoint
Write-Host ""
Write-Host "3. Testing Instances Endpoint..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$bffUrl/api/instances" -Method GET -TimeoutSec 10
    Write-Host "   ✅ Instances endpoint responding" -ForegroundColor Green
    if ($response.instances) {
        Write-Host "   Found $($response.instances.Count) instances" -ForegroundColor Gray
        foreach ($instance in $response.instances) {
            Write-Host "     - $($instance.instance_id) ($($instance.region)) - $($instance.status)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   ⚠️  No instances found in response" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Instances endpoint error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Issue 4: Test users endpoint (expect 401 without auth)
Write-Host ""
Write-Host "4. Testing Users Endpoint (without auth)..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$bffUrl/api/users" -Method GET -TimeoutSec 10
    Write-Host "   ⚠️  Users endpoint responded without auth (unexpected)" -ForegroundColor Yellow
    Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "   ✅ Users endpoint requires auth (expected 401)" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Users endpoint error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Issue 5: Test discovery endpoint
Write-Host ""
Write-Host "5. Testing Discovery Endpoint..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$bffUrl/api/discovery/trigger" -Method POST -TimeoutSec 10
    Write-Host "   ✅ Discovery endpoint responding" -ForegroundColor Green
    Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ Discovery endpoint error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        Write-Host "   Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Issue 6: Test frontend deployment
Write-Host ""
Write-Host "6. Testing Frontend Deployment..." -ForegroundColor Green
try {
    $response = Invoke-WebRequest -Uri $frontendUrl -Method GET -TimeoutSec 10
    Write-Host "   ✅ Frontend is accessible" -ForegroundColor Green
    Write-Host "   Status: $($response.StatusCode)" -ForegroundColor Gray
    
    # Check if it contains React app
    if ($response.Content -match "React" -or $response.Content -match "root") {
        Write-Host "   ✅ Frontend appears to be React app" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Frontend may not be properly deployed" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Frontend not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

# Issue 7: Test Cognito configuration
Write-Host ""
Write-Host "7. Testing Cognito Configuration..." -ForegroundColor Green
$cognitoDomain = "rds-dashboard-auth-876595225096.auth.ap-southeast-1.amazoncognito.com"
try {
    $response = Invoke-WebRequest -Uri "https://$cognitoDomain/.well-known/jwks.json" -Method GET -TimeoutSec 10
    Write-Host "   ✅ Cognito domain is accessible" -ForegroundColor Green
    Write-Host "   Status: $($response.StatusCode)" -ForegroundColor Gray
} catch {
    Write-Host "   ❌ Cognito domain not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== DIAGNOSTIC SUMMARY ===" -ForegroundColor Yellow
Write-Host "Issues to investigate:" -ForegroundColor Cyan
Write-Host "1. BFF authentication middleware - may not be passing user identity" -ForegroundColor White
Write-Host "2. Frontend cache - may not have latest logout fix" -ForegroundColor White
Write-Host "3. Discovery system - may not be finding all instances" -ForegroundColor White
Write-Host "4. User management - may lack proper permissions" -ForegroundColor White
Write-Host "5. Operations authentication - may be missing user context" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Fix BFF authentication middleware to pass user identity" -ForegroundColor White
Write-Host "2. Force frontend cache invalidation" -ForegroundColor White
Write-Host "3. Fix discovery system cross-account permissions" -ForegroundColor White
Write-Host "4. Update operations Lambda to handle user identity properly" -ForegroundColor White