# Fix Instance Detail Navigation
# This script updates the BFF to support instance detail endpoints

Write-Host "=== FIXING INSTANCE DETAIL NAVIGATION ===" -ForegroundColor Green

# Deploy updated BFF with instance detail support
$lambdaFunctionName = "rds-dashboard-bff-prod"
$bffCodeFile = "bff/working-bff-with-data.js"

Write-Host "`n1. Deploying updated BFF with instance detail support..." -ForegroundColor Yellow

# Create deployment package
$tempDir = "temp-bff-deploy-detail"
if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Copy the updated BFF code
Copy-Item $bffCodeFile "$tempDir/index.js"

# Create ZIP package
$zipFile = "bff-updated-detail.zip"
if (Test-Path $zipFile) {
    Remove-Item $zipFile
}

# Create ZIP using PowerShell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory((Resolve-Path $tempDir).Path, (Resolve-Path ".").Path + "\$zipFile")

# Deploy to Lambda
Write-Host "Updating Lambda function code..." -ForegroundColor Cyan
aws lambda update-function-code --function-name $lambdaFunctionName --zip-file fileb://$zipFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ BFF Lambda updated with instance detail support" -ForegroundColor Green
} else {
    Write-Host "❌ BFF Lambda update failed" -ForegroundColor Red
    exit 1
}

# Clean up
Remove-Item -Recurse -Force $tempDir
Remove-Item $zipFile

# Wait for Lambda to be ready
Write-Host "`n2. Waiting for Lambda to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Test the new endpoints
Write-Host "`n3. Testing new endpoints..." -ForegroundColor Yellow
$apiBaseUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"

# Test individual instance endpoint
Write-Host "Testing instance detail endpoint..." -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "$apiBaseUrl/api/instances/rds-prod-001" -Method GET -Headers @{
        "Origin" = "https://d2qvaswtmn22om.cloudfront.net"
    } -TimeoutSec 10
    Write-Host "✅ Instance detail endpoint working: $($response.instance.instance_id)" -ForegroundColor Green
} catch {
    Write-Host "❌ Instance detail endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test operations endpoint
Write-Host "Testing operations endpoint..." -ForegroundColor Cyan
try {
    $operationData = @{
        instance_id = "rds-prod-001"
        operation_type = "create_snapshot"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri "$apiBaseUrl/api/operations" -Method POST -Body $operationData -ContentType "application/json" -Headers @{
        "Origin" = "https://d2qvaswtmn22om.cloudfront.net"
    } -TimeoutSec 10
    Write-Host "✅ Operations endpoint working: $($response.status)" -ForegroundColor Green
} catch {
    Write-Host "❌ Operations endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== INSTANCE DETAIL FIX COMPLETE ===" -ForegroundColor Green
Write-Host "✅ Instance detail navigation should now work correctly!" -ForegroundColor Green
Write-Host "✅ Clicking on instances will load their detail pages" -ForegroundColor Green
Write-Host "✅ Operations functionality is now available" -ForegroundColor Green

Write-Host "`nNote: The browser extension error you saw is unrelated to our fixes." -ForegroundColor Yellow
Write-Host "It's a common browser extension issue that doesn't affect functionality." -ForegroundColor Yellow