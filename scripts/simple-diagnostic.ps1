#!/usr/bin/env pwsh
# Simple Cross-Account Discovery and Operations Diagnostic

Write-Host "=== RDS Dashboard Diagnostic ===" -ForegroundColor Cyan

# Configuration
$HubAccount = "876595225096"
$CrossAccount = "817214535871"
$Region = "ap-southeast-1"
$ExternalId = "rds-dashboard-unique-id-12345"
$RoleName = "RDSDashboardCrossAccountRole"
$BffUrl = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "Testing basic functionality..." -ForegroundColor Yellow

# Test 1: Check Lambda functions
Write-Host "`n1. Checking Lambda Functions:" -ForegroundColor Green
$functions = @("rds-discovery-service", "rds-operations-service", "rds-bff-service")

foreach ($func in $functions) {
    try {
        aws lambda get-function --function-name $func --query 'Configuration.FunctionName' --output text 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ $func exists" -ForegroundColor Green
        } else {
            Write-Host "  ❌ $func not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ❌ $func not found" -ForegroundColor Red
    }
}

# Test 2: Test cross-account role
Write-Host "`n2. Testing Cross-Account Role:" -ForegroundColor Green
$roleArn = "arn:aws:iam::${CrossAccount}:role/${RoleName}"
Write-Host "  Role ARN: $roleArn"

try {
    $result = aws sts assume-role --role-arn $roleArn --role-session-name "test-session" --external-id $ExternalId 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✅ Cross-account role accessible" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Cannot assume cross-account role" -ForegroundColor Red
        Write-Host "  Need to deploy cross-account role in account $CrossAccount"
    }
}
catch {
    Write-Host "  ❌ Cross-account role test failed" -ForegroundColor Red
}

# Test 3: Test BFF instances endpoint
Write-Host "`n3. Testing BFF Instances Endpoint:" -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/instances" -Method GET -TimeoutSec 10
    Write-Host "  ✅ BFF instances endpoint working" -ForegroundColor Green
    
    if ($response.instances) {
        Write-Host "  Found $($response.instances.Count) instances"
        
        # Show first instance for testing operations
        if ($response.instances.Count -gt 0) {
            $testInstance = $response.instances[0]
            Write-Host "  Test instance: $($testInstance.instance_id) ($($testInstance.status))"
        }
    } else {
        Write-Host "  No instances found"
    }
}
catch {
    Write-Host "  ❌ BFF instances endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Test operations endpoint
Write-Host "`n4. Testing Operations Endpoint:" -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri "$BffUrl/api/operations" -Method GET -TimeoutSec 10
    Write-Host "  ✅ Operations endpoint exists" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "  ❌ Operations endpoint not found (404)" -ForegroundColor Red
        Write-Host "  Need to add operations endpoint to BFF"
    } else {
        Write-Host "  ⚠️  Operations endpoint error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Test 5: Test discovery service directly
Write-Host "`n5. Testing Discovery Service:" -ForegroundColor Green
try {
    $payload = '{}' | Out-File -FilePath temp_payload.json -Encoding utf8
    $result = aws lambda invoke --function-name rds-discovery-service --payload file://temp_payload.json response.json 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        $response = Get-Content response.json | ConvertFrom-Json
        Write-Host "  ✅ Discovery service working" -ForegroundColor Green
        
        if ($response.body) {
            $body = $response.body | ConvertFrom-Json
            Write-Host "  Total instances: $($body.total_instances)"
            Write-Host "  Accounts scanned: $($body.accounts_scanned)"
        }
    } else {
        Write-Host "  ❌ Discovery service failed" -ForegroundColor Red
    }
    
    Remove-Item temp_payload.json -ErrorAction SilentlyContinue
    Remove-Item response.json -ErrorAction SilentlyContinue
}
catch {
    Write-Host "  ❌ Discovery service test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta
Write-Host "Based on the tests above, here are the likely issues:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. If cross-account role failed:" -ForegroundColor Cyan
Write-Host "   Deploy role: aws cloudformation deploy --template-file infrastructure/cross-account-role.yaml --stack-name rds-dashboard-cross-account-role --parameter-overrides ManagementAccountId=$HubAccount ExternalId=$ExternalId --capabilities CAPABILITY_NAMED_IAM"
Write-Host ""
Write-Host "2. If operations endpoint not found:" -ForegroundColor Cyan
Write-Host "   Need to add /api/operations endpoint to BFF and deploy operations Lambda"
Write-Host ""
Write-Host "3. If discovery working but no cross-account instances:" -ForegroundColor Cyan
Write-Host "   Configure TARGET_ACCOUNTS environment variable in discovery Lambda"
Write-Host ""
Write-Host "Diagnostic complete!" -ForegroundColor Green