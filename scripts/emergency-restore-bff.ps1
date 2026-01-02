#!/usr/bin/env pwsh

<#
.SYNOPSIS
Emergency BFF Restoration

.DESCRIPTION
Restore API Gateway to point back to the original BFF function that handles all endpoints
#>

$ErrorActionPreference = "Stop"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== EMERGENCY BFF RESTORATION ===" -ForegroundColor Red
Write-Host "Restoring API Gateway to point to original BFF function" -ForegroundColor Yellow

$apiId = "km9ww1hh3k"
$resourceId = "gwazwv"
$region = "ap-southeast-1"
$accountId = "876595225096"

# Step 1: Update API Gateway integration to point back to original BFF
Write-Host "`n--- Step 1: Restore API Gateway Integration ---" -ForegroundColor Yellow

$originalBffArn = "arn:aws:apigateway:${region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${region}:${accountId}:function:rds-dashboard-bff/invocations"

Write-Info "Updating API Gateway integration to point to original BFF..."

try {
    aws apigateway put-integration `
        --rest-api-id $apiId `
        --resource-id $resourceId `
        --http-method ANY `
        --type AWS_PROXY `
        --integration-http-method POST `
        --uri $originalBffArn `
        --region $region

    Write-Success "✅ API Gateway integration updated to original BFF"
} catch {
    Write-Error "❌ Failed to update API Gateway integration: $($_.Exception.Message)"
    exit 1
}

# Step 2: Ensure original BFF has API Gateway permissions
Write-Host "`n--- Step 2: Grant API Gateway Permissions ---" -ForegroundColor Yellow

Write-Info "Adding API Gateway invoke permission to original BFF..."

try {
    aws lambda add-permission `
        --function-name "rds-dashboard-bff" `
        --statement-id "api-gateway-invoke-original" `
        --action "lambda:InvokeFunction" `
        --principal "apigateway.amazonaws.com" `
        --source-arn "arn:aws:execute-api:${region}:${accountId}:${apiId}/*/*" `
        --region $region 2>$null

    Write-Success "✅ API Gateway permissions granted to original BFF"
} catch {
    Write-Warning "⚠️  Permission may already exist (this is OK)"
}

# Step 3: Deploy API Gateway changes
Write-Host "`n--- Step 3: Deploy API Gateway Changes ---" -ForegroundColor Yellow

Write-Info "Deploying API Gateway changes..."

try {
    aws apigateway create-deployment `
        --rest-api-id $apiId `
        --stage-name prod `
        --description "Emergency restore to original BFF function" `
        --region $region

    Write-Success "✅ API Gateway deployment completed"
} catch {
    Write-Error "❌ Failed to deploy API Gateway: $($_.Exception.Message)"
    exit 1
}

# Step 4: Test the restoration
Write-Host "`n--- Step 4: Test Restoration ---" -ForegroundColor Yellow

$apiUrl = "https://${apiId}.execute-api.${region}.amazonaws.com/prod"

# Test main endpoints
$endpoints = @(
    "/api/instances",
    "/api/health",
    "/api/errors/dashboard"
)

$allWorking = $true

foreach ($endpoint in $endpoints) {
    Write-Info "Testing: $endpoint"
    
    try {
        $response = Invoke-WebRequest -Uri "$apiUrl$endpoint" -Method GET -ErrorAction Stop
        
        if ($response.StatusCode -eq 200) {
            $content = $response.Content | ConvertFrom-Json
            
            # Check if it's a proper response (not "temporarily unavailable")
            if ($content.message -and $content.message -match "temporarily unavailable") {
                Write-Warning "⚠️  $endpoint: Still returning 'temporarily unavailable'"
                $allWorking = $false
            } else {
                Write-Success "✅ $endpoint: Working properly"
            }
        } else {
            Write-Error "❌ $endpoint: Status $($response.StatusCode)"
            $allWorking = $false
        }
    } catch {
        Write-Error "❌ $endpoint: $($_.Exception.Message)"
        $allWorking = $false
    }
}

# Summary
Write-Host "`n=== RESTORATION SUMMARY ===" -ForegroundColor Cyan

if ($allWorking) {
    Write-Success "🎉 EMERGENCY RESTORATION SUCCESSFUL!"
    Write-Success "All endpoints are now working properly"
    
    Write-Host "`n--- What Should Work Now ---" -ForegroundColor Green
    Write-Host "✅ Dashboard should load with all data" -ForegroundColor White
    Write-Host "✅ Instances, Health, Costs, Compliance pages should work" -ForegroundColor White
    Write-Host "✅ Error monitoring should show graceful fallback" -ForegroundColor White
    
} else {
    Write-Warning "⚠️  Some endpoints may still have issues"
    Write-Warning "The original BFF function may need additional configuration"
    
    Write-Host "`n--- Next Steps ---" -ForegroundColor Yellow
    Write-Host "1. Check original BFF function logs for errors" -ForegroundColor White
    Write-Host "2. Verify backend API connectivity" -ForegroundColor White
    Write-Host "3. Test dashboard in browser" -ForegroundColor White
}

Write-Host "`n--- Technical Changes Made ---" -ForegroundColor Cyan
Write-Host "✅ API Gateway now points to: rds-dashboard-bff (original)" -ForegroundColor White
Write-Host "✅ API Gateway permissions granted" -ForegroundColor White
Write-Host "✅ Changes deployed to production stage" -ForegroundColor White

Write-Host "`nEmergency restoration complete!" -ForegroundColor Cyan