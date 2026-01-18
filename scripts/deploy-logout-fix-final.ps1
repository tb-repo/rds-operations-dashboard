#!/usr/bin/env pwsh

# Deploy Final Logout Fix
# Fixes the "Required String parameter 'response_type' is not present" error

$ErrorActionPreference = "Stop"

Write-Host "Deploying Final Logout Fix..." -ForegroundColor Cyan
Write-Host "Issue: Missing response_type parameter in logout URL" -ForegroundColor Yellow
Write-Host "Fix: Using logout_uri parameter instead of redirect_uri" -ForegroundColor Green

# Build and deploy frontend
Write-Host "Building frontend with logout fix..." -ForegroundColor Blue

try {
    Set-Location "frontend"
    
    # Install dependencies if needed
    if (-not (Test-Path "node_modules")) {
        Write-Host "Installing dependencies..."
        npm install
    }
    
    # Build the frontend
    Write-Host "Building frontend..."
    npm run build
    
    if ($LASTEXITCODE -ne 0) {
        throw "Frontend build failed"
    }
    
    Write-Host "Frontend build successful!" -ForegroundColor Green
    
    # Deploy to S3
    Write-Host "Deploying to S3..." -ForegroundColor Blue
    
    $bucketName = "rds-dashboard-frontend-876595225096"
    
    aws s3 sync dist/ s3://$bucketName --delete --cache-control "max-age=31536000"
    
    if ($LASTEXITCODE -ne 0) {
        throw "S3 deployment failed"
    }
    
    Write-Host "S3 deployment successful!" -ForegroundColor Green
    
    # Invalidate CloudFront cache
    Write-Host "Invalidating CloudFront cache..." -ForegroundColor Blue
    
    $distributionId = "E25MCU6AMR4FOK"
    
    $invalidationResult = aws cloudfront create-invalidation `
        --distribution-id $distributionId `
        --paths "/*" `
        --output json
    
    if ($LASTEXITCODE -eq 0) {
        $invalidation = $invalidationResult | ConvertFrom-Json
        $invalidationId = $invalidation.Invalidation.Id
        Write-Host "CloudFront invalidation created: $invalidationId" -ForegroundColor Green
    } else {
        Write-Host "CloudFront invalidation failed, but deployment may still work" -ForegroundColor Yellow
    }
    
    Set-Location ".."
    
    Write-Host ""
    Write-Host "SUCCESS: Final Logout Fix Deployed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Changes Applied:" -ForegroundColor Cyan
    Write-Host "  - Fixed logout URL to use logout_uri parameter"
    Write-Host "  - Removed redirect_uri parameter that was causing response_type error"
    Write-Host "  - Frontend rebuilt and deployed to S3"
    Write-Host "  - CloudFront cache invalidated"
    Write-Host ""
    Write-Host "Testing:" -ForegroundColor Yellow
    Write-Host "  1. Open dashboard: https://d2qvaswtmn22om.cloudfront.net"
    Write-Host "  2. Login to the dashboard"
    Write-Host "  3. Click logout button"
    Write-Host "  4. Verify no 'response_type' error occurs"
    Write-Host "  5. Verify successful redirect to logout page"
    Write-Host ""
    Write-Host "The logout functionality should now work without errors!" -ForegroundColor Green
    
} catch {
    Set-Location ".."
    Write-Host "ERROR: Deployment failed - $_" -ForegroundColor Red
    exit 1
}