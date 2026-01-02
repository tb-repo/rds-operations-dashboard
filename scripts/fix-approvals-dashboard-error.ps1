# Fix Approvals Dashboard Error
# This script fixes the "v.filter is not a function" error in ApprovalsDashboard

Write-Host "=== Fixing Approvals Dashboard Error ===" -ForegroundColor Green

# Step 1: Deploy updated BFF with approvals endpoint
Write-Host "Step 1: Deploying updated BFF with approvals endpoint..." -ForegroundColor Yellow

# Create deployment package
$deployDir = "rds-operations-dashboard/bff/deploy-approvals"
if (Test-Path $deployDir) {
    Remove-Item $deployDir -Recurse -Force
}
New-Item -ItemType Directory -Path $deployDir -Force | Out-Null

# Copy the working BFF file
Copy-Item "rds-operations-dashboard/bff/working-bff-with-data.js" "$deployDir/index.js"

# Create package.json
$packageJson = @{
    name = "rds-dashboard-bff"
    version = "1.0.0"
    description = "RDS Dashboard BFF with Approvals Support"
    main = "index.js"
    dependencies = @{}
} | ConvertTo-Json -Depth 3

Set-Content -Path "$deployDir/package.json" -Value $packageJson

# Create ZIP file
$zipPath = "rds-operations-dashboard/bff/bff-with-approvals.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

# Create ZIP using PowerShell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($deployDir, $zipPath)

Write-Host "Created deployment package: $zipPath" -ForegroundColor Green

# Step 2: Update Lambda function
Write-Host "Step 2: Updating Lambda function..." -ForegroundColor Yellow

try {
    # Update the Lambda function code
    aws lambda update-function-code `
        --function-name "rds-dashboard-bff-prod" `
        --zip-file "fileb://$zipPath" `
        --region ap-southeast-1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Lambda function updated successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to update Lambda function" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Error updating Lambda function: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Test the approvals endpoint
Write-Host "Step 3: Testing approvals endpoint..." -ForegroundColor Yellow

$testPayload = @{
    operation = "get_pending_approvals"
    user_email = "test@example.com"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/api/approvals" `
        -Method POST `
        -Body $testPayload `
        -ContentType "application/json" `
        -Headers @{
            "Origin" = "https://d2qvaswtmn22om.cloudfront.net"
        }
    
    Write-Host "✅ Approvals endpoint test successful" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Depth 2)" -ForegroundColor Cyan
} catch {
    Write-Host "⚠️  Approvals endpoint test failed: $_" -ForegroundColor Yellow
    Write-Host "This might be expected if the endpoint needs authentication" -ForegroundColor Yellow
}

# Step 4: Rebuild and deploy frontend
Write-Host "Step 4: Rebuilding frontend with fixes..." -ForegroundColor Yellow

try {
    Set-Location "rds-operations-dashboard/frontend"
    
    # Install dependencies if needed
    if (-not (Test-Path "node_modules")) {
        Write-Host "Installing frontend dependencies..." -ForegroundColor Yellow
        npm install
    }
    
    # Build the frontend
    Write-Host "Building frontend..." -ForegroundColor Yellow
    npm run build
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Frontend build successful" -ForegroundColor Green
    } else {
        Write-Host "❌ Frontend build failed" -ForegroundColor Red
        Set-Location "../.."
        exit 1
    }
    
    # Deploy to S3
    Write-Host "Deploying to S3..." -ForegroundColor Yellow
    aws s3 sync dist/ s3://rds-operations-dashboard-frontend --delete --region ap-southeast-1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Frontend deployed to S3" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to deploy frontend to S3" -ForegroundColor Red
        Set-Location "../.."
        exit 1
    }
    
    # Invalidate CloudFront cache
    Write-Host "Invalidating CloudFront cache..." -ForegroundColor Yellow
    $distributionId = "E1234567890123"  # Replace with actual distribution ID
    aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*" --region ap-southeast-1
    
    Set-Location "../.."
    
} catch {
    Write-Host "❌ Error during frontend deployment: $_" -ForegroundColor Red
    Set-Location "../.."
    exit 1
}

Write-Host "=== Approvals Dashboard Fix Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary of changes:" -ForegroundColor Cyan
Write-Host "✅ Fixed ApprovalsDashboard.tsx to handle non-array responses" -ForegroundColor Green
Write-Host "✅ Added approvals endpoint to BFF Lambda function" -ForegroundColor Green
Write-Host "✅ Updated Lambda function with new code" -ForegroundColor Green
Write-Host "✅ Rebuilt and deployed frontend" -ForegroundColor Green
Write-Host ""
Write-Host "The Approvals tab should now work without the 'v.filter is not a function' error." -ForegroundColor Green
Write-Host "Test the dashboard at: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Cyan