# Deploy Critical Production Fixes
# This script deploys the fixes for:
# 1. Instance operations 400 errors
# 2. Logout redirect_uri errors
# 3. Better error handling for user management

Write-Host "🚀 Deploying Critical Production Fixes..." -ForegroundColor Green

# Deploy frontend changes
Write-Host "📦 Building and deploying frontend..." -ForegroundColor Yellow
Set-Location frontend
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Frontend build failed!" -ForegroundColor Red
    exit 1
}

# Deploy to S3 and invalidate CloudFront
aws s3 sync dist/ s3://rds-dashboard-frontend-876595225096-prod --delete
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Frontend deployment failed!" -ForegroundColor Red
    exit 1
}

# Get CloudFront distribution ID
$distributionId = aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='RDS Dashboard Frontend'].Id" --output text
if ($distributionId) {
    Write-Host "🔄 Invalidating CloudFront cache..." -ForegroundColor Yellow
    aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*"
}

Set-Location ..

# Deploy BFF changes
Write-Host "📦 Deploying BFF..." -ForegroundColor Yellow
Set-Location bff
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ BFF build failed!" -ForegroundColor Red
    exit 1
}

# Create deployment package
Compress-Archive -Path dist/* -DestinationPath bff-critical-fixes.zip -Force

# Update Lambda function
aws lambda update-function-code --function-name rds-bff-prod --zip-file fileb://bff-critical-fixes.zip
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ BFF deployment failed!" -ForegroundColor Red
    exit 1
}

# Clean up
Remove-Item bff-critical-fixes.zip -Force

Set-Location ..

Write-Host "✅ Critical fixes deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "🔧 Fixes Applied:" -ForegroundColor Cyan
Write-Host "  ✅ Fixed instance operations 400 errors (operation_type → operation)" -ForegroundColor Green
Write-Host "  ✅ Fixed logout redirect_uri error (logout_uri → redirect_uri)" -ForegroundColor Green
Write-Host "  ✅ Added better error handling for user management" -ForegroundColor Green
Write-Host ""
Write-Host "🧪 Test the fixes:" -ForegroundColor Yellow
Write-Host "  1. Try instance operations (start/stop/reboot)" -ForegroundColor White
Write-Host "  2. Test logout functionality" -ForegroundColor White
Write-Host "  3. Check user management tab" -ForegroundColor White
Write-Host "  4. Verify no console errors" -ForegroundColor White