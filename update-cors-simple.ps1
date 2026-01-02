#!/usr/bin/env pwsh

<#
.SYNOPSIS
Update BFF Lambda CORS environment variable - Simple approach

.DESCRIPTION
Updates the FRONTEND_URL environment variable to use the CloudFront origin
#>

param(
    [string]$FunctionName = "rds-dashboard-bff",
    [string]$Region = "ap-southeast-1",
    [string]$CloudFrontUrl = "https://d2qvaswtmn22om.cloudfront.net"
)

Write-Host "=== Updating BFF Lambda CORS Configuration ===" -ForegroundColor Cyan

# Create environment variables JSON file
$envVars = @{
    "API_KEY" = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
    "INTERNAL_API_URL" = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
    "INTERNAL_API_KEY" = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"
    "COGNITO_REGION" = "ap-southeast-1"
    "NODE_ENV" = "production"
    "COGNITO_USER_POOL_ID" = "ap-southeast-1_4tyxh4qJe"
    "LOG_LEVEL" = "info"
    "CORS_ORIGIN" = $CloudFrontUrl
    "FRONTEND_URL" = $CloudFrontUrl
}

$envConfig = @{
    Variables = $envVars
}

# Write to temporary JSON file
$jsonFile = "temp-env.json"
$envConfig | ConvertTo-Json -Depth 2 | Out-File -FilePath $jsonFile -Encoding ASCII

Write-Host "Environment configuration:" -ForegroundColor Cyan
Get-Content $jsonFile

Write-Host "Updating Lambda environment variables..." -ForegroundColor Yellow
Write-Host "Setting FRONTEND_URL to: $CloudFrontUrl" -ForegroundColor Green
Write-Host "Setting CORS_ORIGIN to: $CloudFrontUrl" -ForegroundColor Green

# Update the Lambda function using the JSON file
try {
    $result = aws lambda update-function-configuration --function-name $FunctionName --region $Region --environment file://$jsonFile --output json | ConvertFrom-Json
    
    Write-Host "Environment variables updated successfully!" -ForegroundColor Green
    Write-Host "Function: $($result.FunctionName)" -ForegroundColor Cyan
    Write-Host "Last Modified: $($result.LastModified)" -ForegroundColor Cyan
    
    # Verify the update
    Write-Host "Verifying update..." -ForegroundColor Yellow
    $updatedConfig = aws lambda get-function-configuration --function-name $FunctionName --region $Region --output json | ConvertFrom-Json
    
    Write-Host "Updated FRONTEND_URL: $($updatedConfig.Environment.Variables.FRONTEND_URL)" -ForegroundColor Green
    Write-Host "Updated CORS_ORIGIN: $($updatedConfig.Environment.Variables.CORS_ORIGIN)" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to update Lambda configuration: $($_.Exception.Message)"
    exit 1
} finally {
    # Clean up temporary file
    if (Test-Path $jsonFile) {
        Remove-Item $jsonFile -Force
    }
}

Write-Host "=== CORS Configuration Update Complete ===" -ForegroundColor Green