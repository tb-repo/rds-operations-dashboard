# Update BFF Lambda CORS Environment Variable
# This script updates the CORS_ORIGIN environment variable for the BFF Lambda function

param(
    [Parameter(Mandatory=$true)]
    [string]$Origin,
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionName = "rds-dashboard-bff",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-southeast-1"
)

Write-Host "Updating BFF Lambda CORS configuration..." -ForegroundColor Green
Write-Host "Function: $FunctionName" -ForegroundColor Cyan
Write-Host "Region: $Region" -ForegroundColor Cyan
Write-Host "New Origin: $Origin" -ForegroundColor Cyan

try {
    # Get current function configuration
    Write-Host "`nGetting current Lambda configuration..." -ForegroundColor Yellow
    $currentConfig = aws lambda get-function-configuration --function-name $FunctionName --region $Region | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get Lambda function configuration"
    }
    
    Write-Host "Current FRONTEND_URL: $($currentConfig.Environment.Variables.FRONTEND_URL)" -ForegroundColor Cyan
    
    # Update the FRONTEND_URL environment variable
    Write-Host "`nUpdating FRONTEND_URL environment variable..." -ForegroundColor Yellow
    
    $envVars = @{
        COGNITO_USER_POOL_ID = $currentConfig.Environment.Variables.COGNITO_USER_POOL_ID
        COGNITO_REGION = $currentConfig.Environment.Variables.COGNITO_REGION
        COGNITO_CLIENT_ID = $currentConfig.Environment.Variables.COGNITO_CLIENT_ID
        INTERNAL_API_URL = $currentConfig.Environment.Variables.INTERNAL_API_URL
        INTERNAL_API_KEY = $currentConfig.Environment.Variables.INTERNAL_API_KEY
        API_SECRET_ARN = $currentConfig.Environment.Variables.API_SECRET_ARN
        FRONTEND_URL = $Origin
        PORT = $currentConfig.Environment.Variables.PORT
        NODE_ENV = $currentConfig.Environment.Variables.NODE_ENV
        LOG_LEVEL = $currentConfig.Environment.Variables.LOG_LEVEL
        AUDIT_LOG_GROUP = $currentConfig.Environment.Variables.AUDIT_LOG_GROUP
        ENABLE_AUDIT_LOGGING = $currentConfig.Environment.Variables.ENABLE_AUDIT_LOGGING
        AWS_NODEJS_CONNECTION_REUSE_ENABLED = $currentConfig.Environment.Variables.AWS_NODEJS_CONNECTION_REUSE_ENABLED
        BUILD_VERSION = $currentConfig.Environment.Variables.BUILD_VERSION
    }
    
    # Convert to JSON format for AWS CLI
    $envVarsJson = ($envVars | ConvertTo-Json -Compress) -replace '"', '\"'
    
    $updateResult = aws lambda update-function-configuration --function-name $FunctionName --region $Region --environment "Variables=$envVarsJson" | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Lambda function configuration"
    }
    
    Write-Host "`n✅ Successfully updated Lambda environment variable!" -ForegroundColor Green
    Write-Host "New FRONTEND_URL: $($updateResult.Environment.Variables.FRONTEND_URL)" -ForegroundColor Green
    
    # Wait for the update to be applied
    Write-Host "`nWaiting for Lambda function to be updated..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    
    # Verify the update
    Write-Host "`nVerifying the update..." -ForegroundColor Yellow
    $verifyConfig = aws lambda get-function-configuration --function-name $FunctionName --region $Region | ConvertFrom-Json
    
    if ($verifyConfig.Environment.Variables.FRONTEND_URL -eq $Origin) {
        Write-Host "✅ Verification successful! FRONTEND_URL is now set to: $Origin" -ForegroundColor Green
    } else {
        Write-Host "❌ Verification failed. Expected: $Origin, Got: $($verifyConfig.Environment.Variables.FRONTEND_URL)" -ForegroundColor Red
    }
    
    Write-Host "`n📋 Summary:" -ForegroundColor Cyan
    Write-Host "- Function Name: $FunctionName" -ForegroundColor White
    Write-Host "- Region: $Region" -ForegroundColor White
    Write-Host "- Updated FRONTEND_URL: $Origin" -ForegroundColor White
    Write-Host "- Last Modified: $($updateResult.LastModified)" -ForegroundColor White
    
} catch {
    Write-Host "`n❌ Error updating Lambda configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n🎉 CORS configuration update completed successfully!" -ForegroundColor Green
Write-Host "The BFF Lambda function should now accept requests from the CloudFront origin." -ForegroundColor Green