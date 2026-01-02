#!/usr/bin/env pwsh
# Deployment Verification Script
# Tests all deployed components

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Dashboard Deployment Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true

# Test 1: BFF Health Check
Write-Host "Test 1: BFF Health Check..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/health" -Method GET
    if ($response.status -eq "healthy") {
        Write-Host "✅ BFF is healthy" -ForegroundColor Green
    } else {
        Write-Host "❌ BFF returned unexpected status" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "❌ BFF health check failed: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 2: BFF Authentication Required
Write-Host "Test 2: BFF Authentication..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/api/instances" -Method GET -ErrorAction Stop
    Write-Host "❌ BFF should require authentication" -ForegroundColor Red
    $allPassed = $false
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "✅ BFF correctly requires authentication" -ForegroundColor Green
    } else {
        Write-Host "❌ Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
        $allPassed = $false
    }
}
Write-Host ""

# Test 3: Frontend Accessibility
Write-Host "Test 3: Frontend Accessibility..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "https://d2qvaswtmn22om.cloudfront.net" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Frontend is accessible (Status: $($response.StatusCode))" -ForegroundColor Green
    } else {
        Write-Host "❌ Frontend returned status: $($response.StatusCode)" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "❌ Frontend not accessible: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 4: Cognito User Pool
Write-Host "Test 4: Cognito User Pool..." -ForegroundColor Yellow
try {
    $userPool = aws cognito-idp describe-user-pool --user-pool-id "ap-southeast-1_4tyxh4qJe" --query 'UserPool.Status' --output text 2>&1
    if ($userPool -eq "Enabled") {
        Write-Host "✅ Cognito User Pool is enabled" -ForegroundColor Green
    } else {
        Write-Host "❌ Cognito User Pool status: $userPool" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "❌ Failed to check Cognito: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 5: Cognito Groups
Write-Host "Test 5: Cognito Groups..." -ForegroundColor Yellow
try {
    $groups = aws cognito-idp list-groups --user-pool-id "ap-southeast-1_4tyxh4qJe" --query 'Groups[].GroupName' --output json | ConvertFrom-Json
    $expectedGroups = @("Admin", "DBA", "ReadOnly")
    $missingGroups = $expectedGroups | Where-Object { $_ -notin $groups }
    
    if ($missingGroups.Count -eq 0) {
        Write-Host "✅ All required groups exist: $($groups -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "❌ Missing groups: $($missingGroups -join ', ')" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "❌ Failed to check groups: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 6: Test Users
Write-Host "Test 6: Test Users..." -ForegroundColor Yellow
try {
    $testUsers = @("admin@example.com", "dba@example.com", "readonly@example.com")
    $existingUsers = @()
    
    foreach ($user in $testUsers) {
        try {
            $userInfo = aws cognito-idp admin-get-user --user-pool-id "ap-southeast-1_4tyxh4qJe" --username $user 2>&1
            if ($LASTEXITCODE -eq 0) {
                $existingUsers += $user
            }
        } catch {
            # User doesn't exist
        }
    }
    
    if ($existingUsers.Count -eq $testUsers.Count) {
        Write-Host "✅ All test users exist: $($existingUsers -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Some test users missing. Existing: $($existingUsers -join ', ')" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to check users: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 7: S3 Bucket
Write-Host "Test 7: S3 Frontend Bucket..." -ForegroundColor Yellow
try {
    $bucketExists = aws s3 ls s3://rds-dashboard-frontend-876595225096/ 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ S3 bucket exists and is accessible" -ForegroundColor Green
    } else {
        Write-Host "❌ S3 bucket not accessible" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "❌ Failed to check S3 bucket: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Test 8: CloudFront Distribution
Write-Host "Test 8: CloudFront Distribution..." -ForegroundColor Yellow
try {
    $distStatus = aws cloudfront get-distribution --id E25MCU6AMR4FOK --query 'Distribution.Status' --output text 2>&1
    if ($distStatus -eq "Deployed") {
        Write-Host "✅ CloudFront distribution is deployed" -ForegroundColor Green
    } else {
        Write-Host "⚠️  CloudFront distribution status: $distStatus" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to check CloudFront: $($_.Exception.Message)" -ForegroundColor Red
    $allPassed = $false
}
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your RDS Dashboard is ready to use!" -ForegroundColor Green
    Write-Host "Frontend URL: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Test Credentials:" -ForegroundColor Yellow
    Write-Host "  Admin: admin@example.com / AdminPass123!" -ForegroundColor White
    Write-Host "  DBA: dba@example.com / DbaPass123!" -ForegroundColor White
    Write-Host "  ReadOnly: readonly@example.com / ReadOnlyPass123!" -ForegroundColor White
} else {
    Write-Host "❌ SOME TESTS FAILED" -ForegroundColor Red
    Write-Host "Please review the errors above" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
