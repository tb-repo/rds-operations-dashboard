# Deploy Frontend to S3 and Invalidate CloudFront
# This script builds and deploys the React frontend

param(
    [switch]$SkipBuild = $false
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Command Hub - Frontend Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get CloudFormation outputs
Write-Host "Fetching deployment configuration..." -ForegroundColor Yellow

$bucketName = aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Frontend `
    --query 'Stacks[0].Outputs[?OutputKey==`FrontendBucketName`].OutputValue' `
    --output text

$distributionId = aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Frontend `
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' `
    --output text

$cloudFrontUrl = aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Frontend `
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' `
    --output text

if (-not $bucketName -or -not $distributionId) {
    Write-Host "ERROR: Could not find frontend stack outputs" -ForegroundColor Red
    Write-Host "Make sure RDSDashboard-Frontend stack is deployed" -ForegroundColor Red
    exit 1
}

Write-Host "S3 Bucket: $bucketName" -ForegroundColor Green
Write-Host "CloudFront Distribution: $distributionId" -ForegroundColor Green
Write-Host "CloudFront URL: $cloudFrontUrl" -ForegroundColor Green
Write-Host ""

# Build frontend
if (-not $SkipBuild) {
    Write-Host "Building React application..." -ForegroundColor Yellow
    Push-Location frontend
    
    if (-not (Test-Path "node_modules")) {
        Write-Host "Installing dependencies..." -ForegroundColor Yellow
        npm install
    }
    
    Write-Host "Running build..." -ForegroundColor Yellow
    npm run build
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Build failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    
    Pop-Location
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Skipping build (using existing dist/ folder)" -ForegroundColor Yellow
    Write-Host ""
}

# Upload to S3
Write-Host "Uploading files to S3..." -ForegroundColor Yellow
aws s3 sync frontend/dist/ s3://$bucketName/ --delete

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: S3 upload failed" -ForegroundColor Red
    exit 1
}

Write-Host "Files uploaded successfully!" -ForegroundColor Green
Write-Host ""

# Invalidate CloudFront cache
Write-Host "Invalidating CloudFront cache..." -ForegroundColor Yellow
$invalidation = aws cloudfront create-invalidation `
    --distribution-id $distributionId `
    --paths "/*" `
    --query 'Invalidation.Id' `
    --output text

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: CloudFront invalidation failed" -ForegroundColor Red
    exit 1
}

Write-Host "Invalidation created: $invalidation" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "CloudFront URL: $cloudFrontUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Wait 2-3 minutes for CloudFront invalidation to complete" -ForegroundColor White
Write-Host "2. Visit the URL above" -ForegroundColor White
Write-Host "3. Hard refresh your browser (Ctrl+F5)" -ForegroundColor White
Write-Host "4. You should see 'RDS Command Hub' as the application name" -ForegroundColor White
Write-Host "5. Test the 'Trigger Discovery' and 'Refresh' buttons" -ForegroundColor White
Write-Host ""
Write-Host "Check invalidation status:" -ForegroundColor Yellow
Write-Host "aws cloudfront get-invalidation --distribution-id $distributionId --id $invalidation" -ForegroundColor Gray
Write-Host ""
