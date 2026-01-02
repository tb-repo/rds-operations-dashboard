#!/usr/bin/env pwsh

<#
.SYNOPSIS
Redirect API Gateway to Working BFF

.DESCRIPTION
Update the main API Gateway to point to the working BFF function
#>

$ErrorActionPreference = "Continue"

function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host "=== Redirecting API Gateway to Working BFF ===" -ForegroundColor Cyan

$mainApiId = "km9ww1hh3k"
$workingBffFunction = "rds-dashboard-bff-prod"  # This is the one we fixed

# Step 1: Get the proxy resource ID
Write-Info "Getting proxy resource ID..."
$resources = aws apigateway get-resources --rest-api-id $mainApiId --region ap-southeast-1 --output json | ConvertFrom-Json

$proxyResource = $resources.items | Where-Object { $_.path -eq "/{proxy+}" }

if (-not $proxyResource) {
    Write-Error "Proxy resource not found"
    exit 1
}

$resourceId = $proxyResource.id
Write-Success "Found proxy resource ID: $resourceId"

# Step 2: Update the integration to point to the working BFF
Write-Info "Updating integration to point to working BFF..."

$newUri = "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/arn:aws:lambda:ap-southeast-1:876595225096:function:$workingBffFunction/invocations"

$updateResult = aws apigateway put-integration `
    --rest-api-id $mainApiId `
    --resource-id $resourceId `
    --http-method ANY `
    --type AWS_PROXY `
    --integration-http-method POST `
    --uri $newUri `
    --region ap-southeast-1 `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update integration: $updateResult"
    exit 1
}

Write-Success "Integration updated successfully"

# Step 3: Deploy the changes
Write-Info "Deploying API Gateway changes..."

$deployResult = aws apigateway create-deployment `
    --rest-api-id $mainApiId `
    --stage-name prod `
    --description "Redirect to working BFF function" `
    --region ap-southeast-1 `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to deploy changes: $deployResult"
    exit 1
}

Write-Success "API Gateway changes deployed"

# Step 4: Wait for deployment
Write-Info "Waiting for deployment to propagate..."
Start-Sleep -Seconds 15

# Step 5: Test the updated API Gateway
Write-Info "Testing updated API Gateway..."

try {
    $apiUrl = "https://$mainApiId.execute-api.ap-southeast-1.amazonaws.com/prod/api/errors/dashboard"
    $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers @{
        "Content-Type" = "application/json"
    } -ErrorAction Stop
    
    Write-Success "✅ API Gateway is now working!"
    Write-Info "Response status: $($response.status)"
    
    if ($response.fallback) {
        Write-Success "✅ Fallback data is being returned correctly"
    }
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Warning "⚠️ API Gateway returned status: $statusCode"
    
    if ($statusCode -eq 401) {
        Write-Info "401 Unauthorized - this might be expected if authentication is required"
    } else {
        Write-Error "Unexpected error: $($_.Exception.Message)"
    }
}

# Step 6: Test statistics endpoint too
Write-Info "Testing statistics endpoint..."

try {
    $statsUrl = "https://$mainApiId.execute-api.ap-southeast-1.amazonaws.com/prod/api/errors/statistics"
    $statsResponse = Invoke-RestMethod -Uri $statsUrl -Method GET -Headers @{
        "Content-Type" = "application/json"
    } -ErrorAction Stop
    
    Write-Success "✅ Statistics endpoint is working!"
    Write-Info "Response status: $($statsResponse.status)"
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Warning "⚠️ Statistics endpoint returned status: $statusCode"
}

Write-Host "`n=== API Gateway Redirect Complete ===" -ForegroundColor Cyan
Write-Success "Main API Gateway now points to the working BFF function"
Write-Info "The dashboard should now work at: https://d2qvaswtmn22om.cloudfront.net/dashboard"
Write-Info "Frontend will get fallback data instead of 500 errors"