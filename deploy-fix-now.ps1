#!/usr/bin/env pwsh

Write-Host "🚀 Deploying Operations Fix" -ForegroundColor Green

$BFF_FUNCTION = "rds-dashboard-bff-prod"
$OPS_FUNCTION = "rds-operations-prod"
$REGION = "ap-southeast-1"

# Deploy BFF
Write-Host "📦 Deploying BFF..." -ForegroundColor Cyan
Set-Location "bff"
npm install
npm run build

if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" -Force }
Compress-Archive -Path "dist/*", "node_modules", "package.json" -DestinationPath "deployment.zip" -Force

aws lambda update-function-code --function-name $BFF_FUNCTION --zip-file fileb://deployment.zip --region $REGION

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ BFF deployed" -ForegroundColor Green
} else {
    Write-Host "❌ BFF failed" -ForegroundColor Red
}

Set-Location ".."

# Deploy Operations Lambda
Write-Host "📦 Deploying Operations Lambda..." -ForegroundColor Cyan
Set-Location "lambda/operations"

if (Test-Path "deployment.zip") { Remove-Item "deployment.zip" -Force }

$temp = "temp"
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
New-Item -ItemType Directory -Path $temp | Out-Null

Copy-Item "handler.py" "$temp/"
New-Item -ItemType Directory -Path "$temp/shared" | Out-Null
Copy-Item "../shared/*.py" "$temp/shared/"

Set-Location $temp
Compress-Archive -Path "*" -DestinationPath "../deployment.zip" -Force
Set-Location ".."
Remove-Item $temp -Recurse -Force

aws lambda update-function-code --function-name $OPS_FUNCTION --zip-file fileb://deployment.zip --region $REGION

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Operations Lambda deployed" -ForegroundColor Green
} else {
    Write-Host "❌ Operations Lambda failed" -ForegroundColor Red
}

Set-Location "../.."

Write-Host "🎯 Deployment Complete!" -ForegroundColor Green
Write-Host "Next: Test operations in dashboard UI" -ForegroundColor Cyan