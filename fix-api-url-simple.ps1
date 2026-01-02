#!/usr/bin/env pwsh

Write-Host "=== Fixing Frontend API URL ===" -ForegroundColor Cyan

# Step 1: Fix .env.production file
Write-Host "Fixing .env.production..." -ForegroundColor Yellow
$envProd = "frontend/.env.production"
if (Test-Path $envProd) {
    $content = Get-Content $envProd -Raw
    $content = $content -replace "km9ww1hh3k", "08mqqv008c"
    $content | Set-Content $envProd -NoNewline
    Write-Host "✅ Fixed .env.production" -ForegroundColor Green
}

# Step 2: Rebuild frontend
Write-Host "Rebuilding frontend..." -ForegroundColor Yellow
Push-Location "frontend"

# Clean previous build
if (Test-Path "dist") {
    Remove-Item "dist" -Recurse -Force
}

# Build with production environment
$env:NODE_ENV = "production"
npm run build

Pop-Location
Write-Host "✅ Frontend rebuilt" -ForegroundColor Green

# Step 3: Deploy to S3
Write-Host "Deploying to S3..." -ForegroundColor Yellow
aws s3 sync frontend/dist/ s3://rds-dashboard-frontend-876595225096/ --delete --region ap-southeast-1
Write-Host "✅ Deployed to S3" -ForegroundColor Green

# Step 4: Invalidate CloudFront
Write-Host "Invalidating CloudFront..." -ForegroundColor Yellow
aws cloudfront create-invalidation --distribution-id E25MCU6AMR4FOK --paths "/*" --region ap-southeast-1
Write-Host "✅ CloudFront invalidation created" -ForegroundColor Green

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Green
Write-Host "Wait 5-10 minutes for CloudFront to update, then test:" -ForegroundColor Yellow
Write-Host "https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Cyan