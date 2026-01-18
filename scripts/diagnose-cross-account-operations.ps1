#!/usr/bin/env pwsh
# Comprehensive Cross-Account Discovery and Operations Diagnostic Script

Write-Host "=== RDS Dashboard Cross-Account Discovery and Operations Diagnostic ===" -ForegroundColor Cyan
Write-Host "This script will test both cross-account discovery and instance operations functionality" -ForegroundColor Yellow
Write-Host ""

# Configuration
$HubAccount = "876595225096"
$CrossAccount = "817214535871"
$Region = "ap-southeast-1"
$ExternalId = "rds-dashboard-unique-id-12345"
$RoleName = "RDSDashboardCrossAccountRole"

# Test URLs
$BffUrl = "https://d2qvaswtmn22om.cloudfront.net"
$ApiUrl = "https://api.rdsdashboard.com"

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Hub Account: $HubAccount"
Write-Host "  Cross Account: $CrossAccount"
Write-Host "  Region: $Region"
Write-Host "  External ID: $ExternalId"
Write-Host "  Role Name: $RoleName"
Write-Host "  BFF URL: $BffUrl"
Write-Host "  API URL: $ApiUrl"
Write-Host ""

# Function to test API endpoint
function Test-ApiEndpoint {
    param(
        [string]$Url,
        [string]$Description,
        [string]$Method = "GET",
        [hashtable]$Body = $null
    )
    
    Write-Host "Testing: $Description" -ForegroundColor Yellow
    Write-Host "  URL: $Url"
    
    try {
        $headers = @{
            'Content-Type' = 'application/json'
            'Accept' = 'application/json'
        }
        
        $params = @{
            Uri = $Url
            Method = $Method
            Headers = $headers
            TimeoutSec = 30
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
            Write-Host "  Body: $($params.Body)"
        }
        
        $response = Invoke-RestMethod @params
        
        Write-Host "  ✅ SUCCESS" -ForegroundColor Green
        Write-Host "  Response: $($response | ConvertTo-Json -Depth 3 -Compress)"
        return @{ Success = $true; Data = $response }
    }
    catch {
        Write-Host "  ❌ FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            Write-Host "  Status: $($_.Exception.Response.StatusCode)"
        }
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    finally {
        Write-Host ""
    }
}

# Function to test Lambda function directly
function Test-LambdaFunction {
    param(
        [string]$FunctionName,
        [string]$Description,
        [hashtable]$Payload = @{}
    )
    
    Write-Host "Testing Lambda: $Description" -ForegroundColor Yellow
    Write-Host "  Function: $FunctionName"
    
    try {
        $payloadJson = $Payload | ConvertTo-Json -Depth 10
        Write-Host "  Payload: $payloadJson"
        
        $result = aws lambda invoke --function-name $FunctionName --payload $payloadJson --cli-binary-format raw-in-base64-out response.json
        
        if ($LASTEXITCODE -eq 0) {
            $response = Get-Content response.json | ConvertFrom-Json
            Write-Host "  ✅ SUCCESS" -ForegroundColor Green
            Write-Host "  Response: $($response | ConvertTo-Json -Depth 3 -Compress)"
            Remove-Item response.json -ErrorAction SilentlyContinue
            return @{ Success = $true; Data = $response }
        } else {
            Write-Host "  ❌ FAILED" -ForegroundColor Red
            Write-Host "  AWS CLI Error: $result"
            return @{ Success = $false; Error = $result }
        }
    }
    catch {
        Write-Host "  ❌ FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    finally {
        Write-Host ""
    }
}

# Function to check cross-account role
function Test-CrossAccountRole {
    param(
        [string]$AccountId,
        [string]$RoleName,
        [string]$ExternalId
    )
    
    Write-Host "Testing Cross-Account Role Access" -ForegroundColor Yellow
    Write-Host "  Account: $AccountId"
    Write-Host "  Role: $RoleName"
    Write-Host "  External ID: $ExternalId"
    
    try {
        $roleArn = "arn:aws:iam::${AccountId}:role/${RoleName}"
        
        $result = aws sts assume-role --role-arn $roleArn --role-session-name "test-session" --external-id $ExternalId
        
        if ($LASTEXITCODE -eq 0) {
            $credentials = $result | ConvertFrom-Json
            Write-Host "  ✅ SUCCESS - Role can be assumed" -ForegroundColor Green
            Write-Host "  Session: $($credentials.AssumedRoleUser.AssumedRoleId)"
            return @{ Success = $true; Data = $credentials }
        } else {
            Write-Host "  ❌ FAILED - Cannot assume role" -ForegroundColor Red
            Write-Host "  Error: $result"
            return @{ Success = $false; Error = $result }
        }
    }
    catch {
        Write-Host "  ❌ FAILED" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    finally {
        Write-Host ""
    }
}

# Start diagnostics
Write-Host "=== PHASE 1: Infrastructure Checks ===" -ForegroundColor Magenta

# 1. Test cross-account role access
$roleTest = Test-CrossAccountRole -AccountId $CrossAccount -RoleName $RoleName -ExternalId $ExternalId

# 2. Check if Lambda functions exist
Write-Host "Checking Lambda Functions:" -ForegroundColor Yellow
$functions = @(
    "rds-discovery-service",
    "rds-operations-service", 
    "rds-bff-service"
)

foreach ($func in $functions) {
    try {
        $result = aws lambda get-function --function-name $func 2>$null
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
Write-Host ""

Write-Host "=== PHASE 2: Discovery Service Tests ===" -ForegroundColor Magenta

# 3. Test discovery service directly
$discoveryTest = Test-LambdaFunction -FunctionName "rds-discovery-service" -Description "RDS Discovery Service" -Payload @{}

# 4. Test BFF instances endpoint
$instancesTest = Test-ApiEndpoint -Url "$BffUrl/api/instances" -Description "BFF Instances Endpoint"

Write-Host "=== PHASE 3: Operations Service Tests ===" -ForegroundColor Magenta

# 5. Check if operations Lambda exists and test it
$operationsTest = Test-LambdaFunction -FunctionName "rds-operations-service" -Description "RDS Operations Service" -Payload @{
    httpMethod = "POST"
    path = "/operations"
    body = @{
        operation = "create_snapshot"
        instance_id = "test-instance"
        parameters = @{
            snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }
        user_id = "test-user"
        requested_by = "diagnostic-script"
    } | ConvertTo-Json
}

# 6. Test BFF operations endpoint (if it exists)
if ($instancesTest.Success -and $instancesTest.Data.instances) {
    $testInstance = $instancesTest.Data.instances[0]
    if ($testInstance) {
        Write-Host "Testing operations on instance: $($testInstance.instance_id)" -ForegroundColor Yellow
        
        $operationsBffTest = Test-ApiEndpoint -Url "$BffUrl/api/operations" -Description "BFF Operations Endpoint" -Method "POST" -Body @{
            operation = "create_snapshot"
            instance_id = $testInstance.instance_id
            parameters = @{
                snapshot_id = "test-snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
            user_id = "test-user"
            requested_by = "diagnostic-script"
        }
    }
} else {
    Write-Host "⚠️  No instances found to test operations" -ForegroundColor Yellow
}

Write-Host "=== PHASE 4: Cross-Account Discovery Tests ===" -ForegroundColor Magenta

# 7. Test discovery with cross-account configuration
if ($roleTest.Success) {
    Write-Host "Testing cross-account discovery..." -ForegroundColor Yellow
    
    # Set environment variables for cross-account discovery
    $env:TARGET_ACCOUNTS = "[$HubAccount,$CrossAccount]"
    $env:TARGET_REGIONS = "[`"$Region`"]"
    $env:EXTERNAL_ID = $ExternalId
    $env:CROSS_ACCOUNT_ROLE_NAME = $RoleName
    
    $crossAccountDiscoveryTest = Test-LambdaFunction -FunctionName "rds-discovery-service" -Description "Cross-Account Discovery" -Payload @{
        target_accounts = @($HubAccount, $CrossAccount)
        target_regions = @($Region)
    }
} else {
    Write-Host "⚠️  Skipping cross-account discovery test - role access failed" -ForegroundColor Yellow
}

Write-Host "=== DIAGNOSTIC SUMMARY ===" -ForegroundColor Magenta

$results = @{
    "Cross-Account Role Access" = $roleTest.Success
    "Discovery Service" = $discoveryTest.Success
    "BFF Instances Endpoint" = $instancesTest.Success
    "Operations Service" = $operationsTest.Success
    "Cross-Account Discovery" = if ($roleTest.Success) { $crossAccountDiscoveryTest.Success } else { "Skipped" }
}

foreach ($test in $results.GetEnumerator()) {
    $status = switch ($test.Value) {
        $true { "✅ PASS" }
        $false { "❌ FAIL" }
        "Skipped" { "⚠️  SKIP" }
    }
    Write-Host "  $($test.Key): $status"
}

Write-Host ""
Write-Host "=== RECOMMENDATIONS ===" -ForegroundColor Magenta

if (-not $roleTest.Success) {
    Write-Host "🔧 CRITICAL: Set up cross-account role in account $CrossAccount" -ForegroundColor Red
    Write-Host "   Run: aws cloudformation deploy --template-file infrastructure/cross-account-role.yaml --stack-name rds-dashboard-cross-account-role --parameter-overrides ManagementAccountId=$HubAccount ExternalId=$ExternalId --capabilities CAPABILITY_NAMED_IAM"
}

if (-not $operationsTest.Success) {
    Write-Host "🔧 CRITICAL: Operations service not working" -ForegroundColor Red
    Write-Host "   1. Check if rds-operations-service Lambda function is deployed"
    Write-Host "   2. Verify API Gateway routing to operations endpoints"
    Write-Host "   3. Check Lambda function permissions and environment variables"
}

if ($instancesTest.Success) {
    Write-Host "🔧 HIGH: BFF missing operations endpoints" -ForegroundColor Yellow
    Write-Host "   1. Add /api/operations endpoint to BFF"
    Write-Host "   2. Configure BFF to call operations Lambda function"
    Write-Host "   3. Update API Gateway routing"
}

if ($discoveryTest.Success -and $instancesTest.Success) {
    $instanceCount = if ($instancesTest.Data.metadata) { $instancesTest.Data.metadata.total_instances } else { $instancesTest.Data.instances.Count }
    Write-Host "✅ Discovery working: $instanceCount instances found" -ForegroundColor Green
    
    if ($instanceCount -eq 0) {
        Write-Host "⚠️  No instances discovered - check if RDS instances exist in target accounts/regions" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== NEXT STEPS ===" -ForegroundColor Magenta
Write-Host "1. Fix any CRITICAL issues first"
Write-Host "2. Deploy missing components"
Write-Host "3. Test operations functionality"
Write-Host "4. Verify cross-account discovery across multiple regions"
Write-Host ""
Write-Host "Diagnostic complete!" -ForegroundColor Green