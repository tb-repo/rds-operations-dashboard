#!/usr/bin/env pwsh

<#
.SYNOPSIS
Fix frontend API URL and redeploy
#>

Write-Host "=== Fixing Frontend API URL ===" -ForegroundColor Cyan

$correctApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod"
$incorrectApiUrl = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod"

Write-Host "Correct BFF API URL: $correctApiUrl" -ForegroundColor Green
Write-Host "Incorrect API URL: $incorrectApiUrl" -ForegroundColor Red
Write-Host ""

# Step 1: Verify environment files are correct
Write-Host "=== Step 1: Verify Environment Files ===" -ForegroundColor Cyan

$envFiles = @("frontend/.env", "frontend/.env.production")
foreach ($envFile in $envFiles) {
    if (Test-Path $envFile) {
        Write-Host "Checking: $envFile" -ForegroundColor Yellow
        $content = Get-Content $envFile -Raw
        if ($content -match "km9ww1hh3k") {
            Write-Host "  ❌ Found incorrect API URL in $envFile" -ForegroundColor Red
            Write-Host "  🔧 Fixing..." -ForegroundColor Yellow
            $content = $content -replace "km9ww1hh3k", "08mqqv008c"
            $content | Set-Content $envFile -NoNewline
            Write-Host "  ✅ Fixed $envFile" -ForegroundColor Green
        } else {
            Write-Host "  ✅ $envFile is correct" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠️  $envFile not found" -ForegroundColor Yellow
    }
}

Write-Host ""

# Step 2: Clean and rebuild frontend
Write-Host "=== Step 2: Rebuild Frontend ===" -ForegroundColor Cyan

Push-Location "frontend"

try {
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    if (Test-Path "dist") {
        Remove-Item "dist" -Recurse -Force
        Write-Host "  ✅ Cleaned dist directory" -ForegroundColor Green
    }
    
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    npm install --silent
    Write-Host "  ✅ Dependencies installed" -ForegroundColor Green
    
    Write-Host "Building for production..." -ForegroundColor Yellow
    npm run build
    Write-Host "  ✅ Build completed" -ForegroundColor Green
    
    # Verify the build doesn't contain the old API URL
    Write-Host "Verifying build..." -ForegroundColor Yellow
    $buildFiles = Get-ChildItem "dist" -Recurse -File -Include "*.js"
    $foundOldUrl = $false
    
    foreach ($file in $buildFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -and $content -match "km9ww1hh3k") {
            Write-Host "  ❌ Found old API URL in $($file.Name)" -ForegroundColor Red
            $foundOldUrl = $true
        }
    }
    
    if (-not $foundOldUrl) {
        Write-Host "  ✅ Build verified - no old API URLs found" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Old API URLs still present in build" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "  ❌ Build failed: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

Write-Host ""

# Step 3: Deploy to S3 and CloudFront
Write-Host "=== Step 3: Deploy Frontend ===" -ForegroundColor Cyan

try {
    $bucketName = "rds-dashboard-frontend-876595225096"
    $distributionId = "E25MCU6AMR4FOK"
    
    Write-Host "Uploading to S3 bucket: $bucketName" -ForegroundColor Yellow
    aws s3 sync frontend/dist/ s3://$bucketName/ --delete --region ap-southeast-1
    Write-Host "  ✅ Uploaded to S3" -ForegroundColor Green
    
    Write-Host "Creating CloudFront invalidation..." -ForegroundColor Yellow
    $invalidation = aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*" --region ap-southeast-1 | ConvertFrom-Json
    Write-Host "  ✅ CloudFront invalidation created: $($invalidation.Invalidation.Id)" -ForegroundColor Green
    
} catch {
    Write-Host "  ❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 4: Test the fix
Write-Host "=== Step 4: Test API Connectivity ===" -ForegroundColor Cyan

Write-Host "Testing BFF API endpoints..." -ForegroundColor Yellow

$endpoints = @("/health", "/api/health", "/api/errors/statistics", "/api/errors/dashboard")

foreach ($endpoint in $endpoints) {
    try {
        $response = Invoke-WebRequest -Uri "$correctApiUrl$endpoint" -Method GET -UseBasicParsing -TimeoutSec 10
        Write-Host "  ✅ $endpoint - Status: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ $endpoint - Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Green
Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait 5-10 minutes for CloudFront invalidation to complete" -ForegroundColor White
Write-Host "2. Test the dashboard: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor White
Write-Host "3. Check browser console for any remaining API errors" -ForegroundColor White
Write-Host ""
Write-Host "✅ Frontend should now use correct BFF API: $correctApiUrl" -ForegroundColor Green