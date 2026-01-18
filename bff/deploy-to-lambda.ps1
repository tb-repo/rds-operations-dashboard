# Deploy BFF to Lambda
param(
    [string]$FunctionName = "rds-dashboard-bff-prod",
    [string]$Region = "ap-southeast-1"
)

Write-Host "Deploying BFF to Lambda: $FunctionName" -ForegroundColor Cyan

# Build TypeScript
Write-Host "`nStep 1: Building TypeScript..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green

# Check if lambda-package.zip exists from previous packaging
if (-not (Test-Path "lambda-package.zip")) {
    Write-Host "`nError: lambda-package.zip not found!" -ForegroundColor Red
    Write-Host "Please run package-lambda.ps1 first to create the deployment package." -ForegroundColor Yellow
    exit 1
}

# Get file size
$size = (Get-Item "lambda-package.zip").Length / 1MB
Write-Host "`nPackage size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan

# Update Lambda function
Write-Host "`nStep 2: Updating Lambda function code..." -ForegroundColor Yellow

aws lambda update-function-code `
    --function-name $FunctionName `
    --zip-file "fileb://lambda-package.zip" `
    --region $Region

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nDeployment successful!" -ForegroundColor Green
    Write-Host "Function: $FunctionName" -ForegroundColor Green
    Write-Host "Region: $Region" -ForegroundColor Green
    
    # Wait for function to be updated
    Write-Host "`nWaiting for function update to complete..." -ForegroundColor Yellow
    aws lambda wait function-updated --function-name $FunctionName --region $Region
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Function is now active and ready!" -ForegroundColor Green
    }
} else {
    Write-Host "`nDeployment failed!" -ForegroundColor Red
    Write-Host "Check AWS CLI configuration and permissions." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nDone!" -ForegroundColor Green
