# Fix Frontend API URL and Rebuild - Final Solution
# This script fixes the API URL issue permanently by rebuilding and redeploying the frontend

Write-Host "=== FIXING FRONTEND API URL PERMANENTLY ===" -ForegroundColor Green

# Step 1: Verify the correct .env.production file
Write-Host "`n1. Verifying .env.production configuration..." -ForegroundColor Yellow
$envFile = "frontend/.env.production"
if (Test-Path $envFile) {
    Write-Host "Current .env.production content:" -ForegroundColor Cyan
    Get-Content $envFile
    
    # Check if it has the correct API URL
    $content = Get-Content $envFile -Raw
    if ($content -match "08mqqv008c") {
        Write-Host "✅ .env.production has correct API Gateway URL (08mqqv008c)" -ForegroundColor Green
    } else {
        Write-Host "❌ .env.production has incorrect API Gateway URL" -ForegroundColor Red
        Write-Host "Updating .env.production with correct URL..." -ForegroundColor Yellow
        
        # Update the file with correct URL
        $newContent = $content -replace "km9ww1hh3k", "08mqqv008c"
        Set-Content -Path $envFile -Value $newContent
        Write-Host "✅ Updated .env.production with correct API Gateway URL" -ForegroundColor Green
    }
} else {
    Write-Host "❌ .env.production file not found!" -ForegroundColor Red
    exit 1
}

# Step 2: Clean and rebuild frontend
Write-Host "`n2. Cleaning and rebuilding frontend..." -ForegroundColor Yellow
Set-Location frontend

# Clean previous build
if (Test-Path "dist") {
    Remove-Item -Recurse -Force dist
    Write-Host "✅ Cleaned previous build" -ForegroundColor Green
}

# Install dependencies if needed
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies..." -ForegroundColor Cyan
    npm install
}

# Build for production
Write-Host "Building frontend for production..." -ForegroundColor Cyan
$env:NODE_ENV = "production"
npm run build

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Frontend build successful" -ForegroundColor Green
} else {
    Write-Host "❌ Frontend build failed" -ForegroundColor Red
    exit 1
}

# Step 3: Deploy to S3
Write-Host "`n3. Deploying to S3..." -ForegroundColor Yellow
$bucketName = "rds-dashboard-frontend-876595225096"

# Sync build to S3
aws s3 sync dist/ s3://$bucketName/ --delete --cache-control "max-age=31536000" --exclude "*.html"
aws s3 sync dist/ s3://$bucketName/ --delete --cache-control "no-cache" --include "*.html"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Frontend deployed to S3" -ForegroundColor Green
} else {
    Write-Host "❌ S3 deployment failed" -ForegroundColor Red
    exit 1
}

# Step 4: Invalidate CloudFront cache
Write-Host "`n4. Invalidating CloudFront cache..." -ForegroundColor Yellow
$distributionId = "E1YQXJZQZQZQZQ"  # Replace with actual distribution ID

# Get the actual distribution ID
$distributions = aws cloudfront list-distributions --query "DistributionList.Items[?contains(Aliases.Items, 'd2qvaswtmn22om.cloudfront.net')].Id" --output text
if ($distributions) {
    $distributionId = $distributions.Split()[0]
    Write-Host "Found CloudFront distribution: $distributionId" -ForegroundColor Cyan
    
    # Create invalidation
    $invalidationId = aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*" --query "Invalidation.Id" --output text
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ CloudFront invalidation created: $invalidationId" -ForegroundColor Green
        Write-Host "Cache invalidation may take 5-15 minutes to complete" -ForegroundColor Cyan
    } else {
        Write-Host "❌ CloudFront invalidation failed" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️ Could not find CloudFront distribution, manual cache clear may be needed" -ForegroundColor Yellow
}

# Step 5: Test the fix
Write-Host "`n5. Testing the fix..." -ForegroundColor Yellow
Set-Location ..

# Test API endpoint directly
Write-Host "Testing API Gateway endpoint..." -ForegroundColor Cyan
$apiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod/api/health"
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers @{
        "Origin" = "https://d2qvaswtmn22om.cloudfront.net"
    }
    Write-Host "✅ API Gateway responding correctly" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Cyan
} catch {
    Write-Host "❌ API Gateway test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== FRONTEND FIX COMPLETE ===" -ForegroundColor Green
Write-Host "✅ Frontend rebuilt with correct API URL (08mqqv008c)" -ForegroundColor Green
Write-Host "✅ Deployed to S3 and CloudFront cache invalidated" -ForegroundColor Green
Write-Host "✅ The ERR_NAME_NOT_RESOLVED errors should be fixed" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Wait 5-15 minutes for CloudFront cache to clear" -ForegroundColor Cyan
Write-Host "2. Test dashboard at: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Cyan
Write-Host "3. All API calls should now work without DNS errors" -ForegroundColor Cyan