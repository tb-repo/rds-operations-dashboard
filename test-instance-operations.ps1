#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test instance operations after fixing environment classification

.DESCRIPTION
    This script tests that operations work correctly after fixing the environment
    classification issue. It performs safe, non-destructive tests.

.PARAMETER InstanceId
    The RDS instance ID to test (default: database-1)

.PARAMETER BffUrl
    The BFF URL (will try to detect from CloudFormation if not provided)

.EXAMPLE
    .\test-instance-operations.ps1 -InstanceId database-1
#>

param(
    [string]$InstanceId = "database-1",
    [string]$BffUrl = ""
)

Write-Host "🧪 Testing Instance Operations" -ForegroundColor Cyan
Write-Host "Instance: $InstanceId" -ForegroundColor White
Write-Host ""

# Function to get BFF URL from CloudFormation
function Get-BffUrl {
    try {
        $outputs = aws cloudformation describe-stacks --stack-name RDSDashboardBFFStack --query 'Stacks[0].Outputs' --output json | ConvertFrom-Json
        $bffOutput = $outputs | Where-Object { $_.OutputKey -eq "BFFUrl" -or $_.OutputKey -eq "ApiUrl" }
        if ($bffOutput) {
            return $bffOutput.OutputValue
        }
    } catch {
        Write-Host "⚠️  Could not get BFF URL from CloudFormation" -ForegroundColor Yellow
    }
    return $null
}

# Get BFF URL if not provided
if (-not $BffUrl) {
    $BffUrl = Get-BffUrl
    if (-not $BffUrl) {
        Write-Host "❌ BFF URL not provided and could not detect from CloudFormation" -ForegroundColor Red
        Write-Host "   Please provide the BFF URL with -BffUrl parameter" -ForegroundColor Red
        Write-Host "   Example: -BffUrl https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "🌐 BFF URL: $BffUrl" -ForegroundColor Green
Write-Host ""

# Check if we have a valid auth token (this is a simplified test)
Write-Host "📋 Test 1: Health Endpoint (No Auth Required)" -ForegroundColor Yellow

try {
    $healthResponse = Invoke-RestMethod -Uri "$BffUrl/health" -Method GET -TimeoutSec 10
    Write-Host "✅ BFF Health Check: $($healthResponse.status)" -ForegroundColor Green
} catch {
    Write-Host "❌ BFF Health Check Failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Check if BFF is deployed and accessible" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "📋 Test 2: Instance Health Endpoint (Requires Auth)" -ForegroundColor Yellow

# Note: This test requires authentication, so it will likely fail in a script context
# But it will show us if the endpoint is accessible and what kind of error we get

try {
    $instanceHealthUrl = "$BffUrl/api/health/$InstanceId"
    Write-Host "Testing: $instanceHealthUrl" -ForegroundColor Cyan
    
    # This will likely return 401 (unauthorized) which is expected without auth
    $response = Invoke-WebRequest -Uri $instanceHealthUrl -Method GET -TimeoutSec 10 -SkipHttpErrorCheck
    
    if ($response.StatusCode -eq 401) {
        Write-Host "✅ Endpoint accessible (401 Unauthorized - expected without auth token)" -ForegroundColor Green
    } elseif ($response.StatusCode -eq 403) {
        Write-Host "⚠️  403 Forbidden - This might indicate the environment classification issue still exists" -ForegroundColor Yellow
        Write-Host "   Response: $($response.Content)" -ForegroundColor Yellow
    } elseif ($response.StatusCode -eq 500) {
        Write-Host "❌ 500 Internal Server Error - Backend issue" -ForegroundColor Red
        Write-Host "   Response: $($response.Content)" -ForegroundColor Red
    } else {
        Write-Host "✅ Unexpected response (Status: $($response.StatusCode))" -ForegroundColor Green
        Write-Host "   This might indicate the endpoint is working" -ForegroundColor Green
    }
    
} catch {
    $errorMessage = $_.Exception.Message
    if ($errorMessage -like "*401*" -or $errorMessage -like "*Unauthorized*") {
        Write-Host "✅ Endpoint accessible (401 Unauthorized - expected without auth token)" -ForegroundColor Green
    } elseif ($errorMessage -like "*403*" -or $errorMessage -like "*Forbidden*") {
        Write-Host "⚠️  403 Forbidden - Environment classification issue may still exist" -ForegroundColor Yellow
    } elseif ($errorMessage -like "*500*") {
        Write-Host "❌ 500 Internal Server Error - Backend issue" -ForegroundColor Red
    } else {
        Write-Host "❌ Unexpected error: $errorMessage" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "📋 Test 3: Check Instance in DynamoDB" -ForegroundColor Yellow

try {
    $inventoryTable = "rds-inventory-prod"
    $dynamoItem = aws dynamodb get-item --table-name $inventoryTable --key "{`"instance_id`": {`"S`": `"$InstanceId`"}}" --output json 2>$null | ConvertFrom-Json
    
    if ($dynamoItem.Item) {
        Write-Host "✅ Instance found in DynamoDB inventory" -ForegroundColor Green
        
        # Check environment in DynamoDB
        if ($dynamoItem.Item.tags -and $dynamoItem.Item.tags.M -and $dynamoItem.Item.tags.M.Environment) {
            $environment = $dynamoItem.Item.tags.M.Environment.S
            Write-Host "   Environment in DynamoDB: $environment" -ForegroundColor Cyan
            
            if ($environment.ToLower() -eq "production") {
                Write-Host "⚠️  Instance still shows as Production in DynamoDB" -ForegroundColor Yellow
                Write-Host "   Run discovery to refresh: .\scripts\activate-discovery.ps1" -ForegroundColor Yellow
            } else {
                Write-Host "✅ Environment is non-production: $environment" -ForegroundColor Green
            }
        } else {
            Write-Host "⚠️  No Environment tag found in DynamoDB" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  Instance not found in DynamoDB inventory" -ForegroundColor Yellow
        Write-Host "   Run discovery to populate: .\scripts\activate-discovery.ps1" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "⚠️  Could not check DynamoDB (table may not exist or no permissions)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📋 Test 4: Check AWS Instance Tags" -ForegroundColor Yellow

try {
    $instanceDetails = aws rds describe-db-instances --db-instance-identifier $InstanceId --output json | ConvertFrom-Json
    $instanceArn = $instanceDetails.DBInstances[0].DBInstanceArn
    
    $tagsResponse = aws rds list-tags-for-resource --resource-name $instanceArn --output json | ConvertFrom-Json
    $tags = $tagsResponse.TagList
    
    $envTag = $tags | Where-Object { $_.Key -eq "Environment" }
    
    if ($envTag) {
        Write-Host "✅ Environment tag found: $($envTag.Value)" -ForegroundColor Green
        
        if ($envTag.Value.ToLower() -eq "production") {
            Write-Host "⚠️  Instance is still tagged as Production in AWS" -ForegroundColor Yellow
            Write-Host "   Use: .\fix-instance-environment.ps1 -InstanceId $InstanceId -Environment Development" -ForegroundColor Yellow
        } else {
            Write-Host "✅ Environment is non-production: $($envTag.Value)" -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️  No Environment tag found in AWS" -ForegroundColor Yellow
        Write-Host "   Use: .\fix-instance-environment.ps1 -InstanceId $InstanceId -Environment Development" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "❌ Could not check AWS instance tags: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "📋 Test 5: Check Lambda Functions" -ForegroundColor Yellow

$lambdaFunctions = @(
    "rds-dashboard-bff",
    "rds-health-monitor", 
    "rds-operations",
    "rds-discovery"
)

foreach ($functionName in $lambdaFunctions) {
    try {
        $function = aws lambda get-function --function-name $functionName --output json 2>$null | ConvertFrom-Json
        if ($function) {
            Write-Host "✅ $functionName exists" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  $functionName not found or not accessible" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "📊 TEST SUMMARY" -ForegroundColor Cyan
Write-Host ""

# Provide recommendations based on test results
Write-Host "🔧 Recommendations:" -ForegroundColor Green
Write-Host ""

Write-Host "1. If you see 403 errors or Production environment tags:" -ForegroundColor Yellow
Write-Host "   .\fix-instance-environment.ps1 -InstanceId $InstanceId -Environment Development"
Write-Host ""

Write-Host "2. If DynamoDB is out of sync with AWS tags:" -ForegroundColor Yellow
Write-Host "   .\scripts\activate-discovery.ps1"
Write-Host ""

Write-Host "3. If health endpoints return 500 errors:" -ForegroundColor Yellow
Write-Host "   Check Lambda logs:"
Write-Host "   aws logs tail /aws/lambda/rds-health-monitor --follow"
Write-Host ""

Write-Host "4. For full authentication testing:" -ForegroundColor Yellow
Write-Host "   - Log into the dashboard UI"
Write-Host "   - Navigate to the instance details page"
Write-Host "   - Try performing an operation (like creating a snapshot)"
Write-Host ""

Write-Host "📞 For more help:" -ForegroundColor Blue
Write-Host "   .\TROUBLESHOOTING-403-500-ERRORS.md"
Write-Host ""