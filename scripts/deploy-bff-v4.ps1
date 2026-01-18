#!/usr/bin/env pwsh
# Deploy BFF with Operations Endpoint (v4)

Write-Host "=== Deploying BFF with Operations Endpoint ===" -ForegroundColor Cyan

$BFFFunction = "rds-bff-prod"
$BFFFile = "bff/working-bff-with-data-v4.js"
$TempDir = "temp-bff-deploy"
$ZipFile = "bff-v4.zip"

# Check if BFF file exists
if (-not (Test-Path $BFFFile)) {
    Write-Host "❌ BFF file not found: $BFFFile" -ForegroundColor Red
    exit 1
}

Write-Host "Step 1: Preparing deployment package..." -ForegroundColor Yellow

# Create temporary directory
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir | Out-Null

# Copy BFF file to temp directory as index.js
Copy-Item $BFFFile "$TempDir/index.js"

# Create package.json for dependencies
$packageJson = @{
    name = "rds-bff-with-operations"
    version = "1.4.0"
    description = "BFF for RDS Operations Dashboard with Operations Endpoint"
    main = "index.js"
    dependencies = @{
        "@aws-sdk/client-lambda" = "^3.0.0"
        "@aws-sdk/client-dynamodb" = "^3.0.0"
        "@aws-sdk/lib-dynamodb" = "^3.0.0"
    }
} | ConvertTo-Json -Depth 3

$packageJson | Out-File -FilePath "$TempDir/package.json" -Encoding UTF8

Write-Host "Step 2: Installing dependencies..." -ForegroundColor Yellow

# Install dependencies
Push-Location $TempDir
try {
    npm install --production
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ npm install failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
} catch {
    Write-Host "❌ npm install failed: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

Write-Host "Step 3: Creating deployment package..." -ForegroundColor Yellow

# Create zip file
if (Test-Path $ZipFile) {
    Remove-Item $ZipFile -Force
}

# Use PowerShell's Compress-Archive
try {
    Compress-Archive -Path "$TempDir/*" -DestinationPath $ZipFile -CompressionLevel Optimal
    Write-Host "✅ Deployment package created: $ZipFile" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create zip file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Step 4: Deploying to Lambda..." -ForegroundColor Yellow

# Deploy to Lambda
try {
    aws lambda update-function-code --function-name $BFFFunction --zip-file "fileb://$ZipFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ BFF deployed successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ BFF deployment failed" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ BFF deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Step 5: Updating environment variables..." -ForegroundColor Yellow

# Update BFF environment variables to include operations function
try {
    $envVars = @{
        "DISCOVERY_FUNCTION_NAME" = "rds-discovery-prod"
        "OPERATIONS_FUNCTION_NAME" = "rds-operations-prod"
        "CACHE_TABLE_NAME" = "rds-discovery-cache"
        "AWS_REGION" = "ap-southeast-1"
    }
    
    $envJson = $envVars | ConvertTo-Json -Compress
    aws lambda update-function-configuration --function-name $BFFFunction --environment "Variables=$envJson"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Environment variables updated" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Environment variables update failed, but deployment succeeded" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️  Environment variables update failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Step 6: Testing deployment..." -ForegroundColor Yellow

# Wait for deployment to propagate
Start-Sleep -Seconds 5

# Test BFF endpoint
try {
    $testPayload = @{
        httpMethod = "GET"
        path = "/api/instances"
        headers = @{}
    } | ConvertTo-Json
    
    $testPayload | Out-File -FilePath "test-bff-payload.json" -Encoding UTF8
    
    aws lambda invoke --function-name $BFFFunction --cli-binary-format raw-in-base64-out --payload file://test-bff-payload.json test-bff-response.json
    
    if ($LASTEXITCODE -eq 0) {
        $response = Get-Content test-bff-response.json | ConvertFrom-Json
        if ($response.statusCode -eq 200) {
            Write-Host "✅ BFF test successful" -ForegroundColor Green
        } else {
            Write-Host "⚠️  BFF test returned status: $($response.statusCode)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️  BFF test failed" -ForegroundColor Yellow
    }
    
    # Clean up test files
    Remove-Item test-bff-payload.json -ErrorAction SilentlyContinue
    Remove-Item test-bff-response.json -ErrorAction SilentlyContinue
} catch {
    Write-Host "⚠️  BFF test failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Step 7: Cleanup..." -ForegroundColor Yellow

# Clean up temporary files
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue

Write-Host "`n=== DEPLOYMENT COMPLETE ===" -ForegroundColor Magenta
Write-Host "✅ BFF v4 with operations endpoint deployed successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Available endpoints:" -ForegroundColor Yellow
Write-Host "  GET  /api/instances - List all RDS instances"
Write-Host "  GET  /api/instances/{id} - Get specific instance"
Write-Host "  POST /api/operations - Execute RDS operations"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test operations endpoint from the dashboard"
Write-Host "2. Verify cross-account discovery is working"
Write-Host "3. Test instance operations (start, stop, reboot, snapshot)"
Write-Host ""
Write-Host "BFF deployment complete!" -ForegroundColor Green