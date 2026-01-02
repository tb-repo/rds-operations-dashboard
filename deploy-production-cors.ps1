# Production-Only CORS Deployment
# This script deploys CORS configuration directly to production

param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Production CORS Deployment ===" -ForegroundColor Cyan

# Production-only CORS configuration
$ProductionCorsOrigins = "https://d2qvaswtmn22om.cloudfront.net"

Write-Host "Target: Production Environment Only" -ForegroundColor Yellow
Write-Host "Function: $FunctionName" -ForegroundColor Cyan
Write-Host "CORS Origin: $ProductionCorsOrigins" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build BFF
Write-Host "Building BFF code..." -ForegroundColor Yellow
Push-Location "bff"
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit 1
}
Pop-Location

# Step 2: Create deployment package
Write-Host "Creating deployment package..." -ForegroundColor Yellow

$tempDir = "temp-production"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy files
Copy-Item "bff/dist/index.js" "$tempDir/" -Force
Copy-Item "bff/package.json" "$tempDir/" -Force

# Install minimal dependencies
Push-Location $tempDir
npm install --production --no-audit --no-fund --silent
Pop-Location

# Create zip
Write-Host "Creating zip file..." -ForegroundColor Yellow
try {
    python -c "
import zipfile
import os

def create_zip(source_dir, output_file):
    with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                file_path = os.path.join(root, file)
                arc_name = os.path.relpath(file_path, source_dir)
                zipf.write(file_path, arc_name)

create_zip('$tempDir', 'production-deployment.zip')
print('Zip created successfully')
"
    Write-Host "Package created successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to create package: $($_.Exception.Message)"
    exit 1
}

# Step 3: Check if function exists
Write-Host "Checking if production function exists..." -ForegroundColor Yellow
$functionExists = $false
try {
    aws lambda get-function --function-name $FunctionName --region $Region | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $functionExists = $true
        Write-Host "Production function exists, will update" -ForegroundColor Green
    }
} catch {
    Write-Host "Production function doesn't exist, will create" -ForegroundColor Yellow
}

# Step 4: Deploy function
if (-not $functionExists) {
    Write-Host "Creating new production Lambda function..." -ForegroundColor Yellow
    
    # Get role from existing function
    $existingConfig = aws lambda get-function-configuration --function-name "rds-query-handler" --region $Region | ConvertFrom-Json
    $roleArn = $existingConfig.Role
    
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime "nodejs18.x" `
        --role $roleArn `
        --handler "index.handler" `
        --zip-file "fileb://production-deployment.zip" `
        --description "RDS Dashboard BFF - Production with CORS" `
        --timeout 30 `
        --memory-size 512 `
        --region $Region `
        --environment "Variables={CORS_ORIGINS='$ProductionCorsOrigins',NODE_ENV='production'}"
        
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Production function created successfully!" -ForegroundColor Green
    } else {
        Write-Error "Failed to create function"
        exit 1
    }
} else {
    Write-Host "Updating existing production function..." -ForegroundColor Yellow
    
    # Update environment variables
    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --environment "Variables={CORS_ORIGINS='$ProductionCorsOrigins',NODE_ENV='production'}" `
        --region $Region
        
    # Update code
    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file "fileb://production-deployment.zip" `
        --region $Region
        
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Production function updated successfully!" -ForegroundColor Green
    } else {
        Write-Error "Failed to update function"
        exit 1
    }
}

# Step 5: Test function
Write-Host "Testing production function..." -ForegroundColor Yellow

$testPayload = @{
    httpMethod = "GET"
    path = "/health"
    headers = @{
        Origin = "https://d2qvaswtmn22om.cloudfront.net"
    }
} | ConvertTo-Json

$testPayload | Out-File "test.json" -Encoding UTF8

aws lambda invoke `
    --function-name $FunctionName `
    --payload "file://test.json" `
    --region $Region `
    "response.json"

if (Test-Path "response.json") {
    $response = Get-Content "response.json" | ConvertFrom-Json
    Write-Host "Response Status: $($response.statusCode)" -ForegroundColor Cyan
    
    if ($response.headers -and $response.headers.'Access-Control-Allow-Origin') {
        Write-Host "CORS Header: $($response.headers.'Access-Control-Allow-Origin')" -ForegroundColor Green
    }
}

# Cleanup
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "production-deployment.zip" -Force -ErrorAction SilentlyContinue
Remove-Item "test.json" -Force -ErrorAction SilentlyContinue
Remove-Item "response.json" -Force -ErrorAction SilentlyContinue

Write-Host "" 
Write-Host "=== Production CORS Deployment Complete! ===" -ForegroundColor Green
Write-Host "Function: $FunctionName" -ForegroundColor Cyan
Write-Host "CORS Origin: $ProductionCorsOrigins (Production Only)" -ForegroundColor Cyan
Write-Host "Environment: production" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Your dashboard should now work without CORS errors!" -ForegroundColor Green
Write-Host "🌐 Test at: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Yellow