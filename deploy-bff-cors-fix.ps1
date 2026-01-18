#!/usr/bin/env pwsh

# Deploy BFF with CORS fix for operations endpoint
$FunctionName = "rds-dashboard-bff-prod"
$Region = "ap-southeast-1"

Write-Host "Deploying BFF with CORS fix for operations endpoint" -ForegroundColor Cyan

# Build and deploy BFF
Write-Host "Building BFF..." -ForegroundColor Yellow
Set-Location bff
npm install
npm run build

# Create deployment package
Write-Host "Creating deployment package..." -ForegroundColor Yellow
if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" }
Compress-Archive -Path "dist/*", "node_modules", "package.json" -DestinationPath "deployment.zip"

# Deploy to Lambda
Write-Host "Deploying to Lambda..." -ForegroundColor Yellow
aws lambda update-function-code `
    --function-name $FunctionName `
    --zip-file fileb://deployment.zip `
    --region $Region

# Update handler to use compiled code
Write-Host "Updating handler..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name $FunctionName `
    --handler "dist/index.handler" `
    --region $Region

# Wait for update to complete
Start-Sleep -Seconds 5

# Update environment variables to ensure CORS is properly configured
Write-Host "Updating environment variables..." -ForegroundColor Yellow
aws lambda update-function-configuration `
    --function-name $FunctionName `
    --environment "Variables={NODE_ENV=production,CORS_ORIGINS=https://d2qvaswtmn22om.cloudfront.net,COGNITO_USER_POOL_ID=ap-southeast-1_4tyxh4qJe,COGNITO_REGION=ap-southeast-1,COGNITO_CLIENT_ID=28e031hsul0mi91k0s6f33bs7s,INTERNAL_API_URL=https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com,API_SECRET_ARN=arn:aws:secretsmanager:ap-southeast-1:876595225096:secret:rds-dashboard-api-key-prod-abc123}" `
    --region $Region

Set-Location ..

Write-Host "BFF deployed with CORS fix!" -ForegroundColor Green
Write-Host "The operations endpoint should now work from CloudFront" -ForegroundColor Green