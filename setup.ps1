# RDS Operations Dashboard - Automated Setup Script
# Run this script to set up and deploy the entire application

param(
    [Parameter(Mandatory=$true)]
    [string]$AwsAccountId,
    
    [Parameter(Mandatory=$false)]
    [string]$AwsRegion = "ap-southeast-1",
    
    [Parameter(Mandatory=$false)]
    [string]$AwsProfile = "default",
    
    [Parameter(Mandatory=$false)]
    [string]$GitRemote = "https://github.com/tb-repo/rds-operations-dashboard.git"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Operations Dashboard - Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Function to check if command exists
function Test-Command {
    param($Command)
    try {
        if (Get-Command $Command -ErrorAction Stop) {
            return $true
        }
    } catch {
        return $false
    }
}

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$prerequisites = @{
    "git" = "Git"
    "node" = "Node.js"
    "python" = "Python"
    "aws" = "AWS CLI"
    "cdk" = "AWS CDK"
}

$missingPrereqs = @()
foreach ($cmd in $prerequisites.Keys) {
    if (Test-Command $cmd) {
        Write-Host "✓ $($prerequisites[$cmd]) installed" -ForegroundColor Green
    } else {
        Write-Host "✗ $($prerequisites[$cmd]) NOT installed" -ForegroundColor Red
        $missingPrereqs += $prerequisites[$cmd]
    }
}

if ($missingPrereqs.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Missing prerequisites: $($missingPrereqs -join ', ')" -ForegroundColor Red
    Write-Host "Please install missing tools and try again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All prerequisites met!" -ForegroundColor Green
Write-Host ""

# Step 1: Git Setup
Write-Host "Step 1: Setting up Git..." -ForegroundColor Yellow

if (-not (Test-Path ".git")) {
    git init
    Write-Host "✓ Git repository initialized" -ForegroundColor Green
}

git remote remove origin 2>$null
git remote add origin $GitRemote
Write-Host "✓ Git remote configured" -ForegroundColor Green

# Step 2: AWS Configuration
Write-Host ""
Write-Host "Step 2: Configuring AWS..." -ForegroundColor Yellow

$identity = aws sts get-caller-identity --profile $AwsProfile 2>$null | ConvertFrom-Json
if ($identity) {
    Write-Host "✓ AWS credentials valid" -ForegroundColor Green
    Write-Host "  Account: $($identity.Account)" -ForegroundColor Gray
    Write-Host "  User: $($identity.Arn)" -ForegroundColor Gray
} else {
    Write-Host "✗ AWS credentials not configured" -ForegroundColor Red
    Write-Host "Please run: aws configure --profile $AwsProfile" -ForegroundColor Yellow
    exit 1
}

# Step 3: Bootstrap CDK
Write-Host ""
Write-Host "Step 3: Bootstrapping AWS CDK..." -ForegroundColor Yellow

Set-Location infrastructure
cdk bootstrap "aws://$AwsAccountId/$AwsRegion" --profile $AwsProfile
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ CDK bootstrapped successfully" -ForegroundColor Green
} else {
    Write-Host "✗ CDK bootstrap failed" -ForegroundColor Red
    exit 1
}

# Step 4: Install Dependencies
Write-Host ""
Write-Host "Step 4: Installing dependencies..." -ForegroundColor Yellow

Write-Host "  Installing infrastructure dependencies..." -ForegroundColor Gray
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to install infrastructure dependencies" -ForegroundColor Red
    exit 1
}

Write-Host "  Installing Lambda dependencies..." -ForegroundColor Gray
Set-Location ../lambda
pip install -r requirements.txt -t .
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to install Lambda dependencies" -ForegroundColor Red
    exit 1
}

Write-Host "  Installing frontend dependencies..." -ForegroundColor Gray
Set-Location ../frontend
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to install frontend dependencies" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All dependencies installed" -ForegroundColor Green

# Step 5: Deploy Infrastructure
Write-Host ""
Write-Host "Step 5: Deploying infrastructure (this may take 10-15 minutes)..." -ForegroundColor Yellow

Set-Location ../infrastructure
cdk deploy --all --require-approval never --profile $AwsProfile
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Infrastructure deployed successfully" -ForegroundColor Green

# Step 6: Get Stack Outputs
Write-Host ""
Write-Host "Step 6: Retrieving deployment outputs..." -ForegroundColor Yellow

$apiUrl = aws cloudformation describe-stacks `
    --stack-name RdsDashboard-API-Stack `
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' `
    --output text `
    --profile $AwsProfile

$apiKey = aws cloudformation describe-stacks `
    --stack-name RdsDashboard-API-Stack `
    --query 'Stacks[0].Outputs[?OutputKey==`ApiKey`].OutputValue' `
    --output text `
    --profile $AwsProfile

if ($apiUrl -and $apiKey) {
    Write-Host "✓ Retrieved API Gateway details" -ForegroundColor Green
    Write-Host "  API URL: $apiUrl" -ForegroundColor Gray
} else {
    Write-Host "✗ Failed to retrieve API Gateway details" -ForegroundColor Red
    exit 1
}

# Step 7: Deploy Frontend
Write-Host ""
Write-Host "Step 7: Deploying frontend..." -ForegroundColor Yellow

Set-Location ../frontend

# Create .env file
@"
VITE_API_BASE_URL=$apiUrl
VITE_API_KEY=$apiKey
"@ | Out-File -FilePath .env -Encoding utf8

Write-Host "  Building frontend..." -ForegroundColor Gray
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Frontend build failed" -ForegroundColor Red
    exit 1
}

$bucketName = "rds-dashboard-frontend-$AwsAccountId"

Write-Host "  Creating S3 bucket..." -ForegroundColor Gray
aws s3 mb "s3://$bucketName" --region $AwsRegion --profile $AwsProfile 2>$null

Write-Host "  Configuring static website hosting..." -ForegroundColor Gray
aws s3 website "s3://$bucketName" --index-document index.html --profile $AwsProfile

Write-Host "  Uploading files..." -ForegroundColor Gray
aws s3 sync dist/ "s3://$bucketName" --delete --profile $AwsProfile

Write-Host "  Setting bucket policy..." -ForegroundColor Gray
$policy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$bucketName/*"
  }]
}
"@
$policy | aws s3api put-bucket-policy --bucket $bucketName --policy file:///dev/stdin --profile $AwsProfile

$websiteUrl = "http://$bucketName.s3-website-$AwsRegion.amazonaws.com"

Write-Host "✓ Frontend deployed successfully" -ForegroundColor Green

# Step 8: Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete! 🎉" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Dashboard URL: $websiteUrl" -ForegroundColor Green
Write-Host "API URL: $apiUrl" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Open the dashboard URL in your browser" -ForegroundColor White
Write-Host "2. Create a test RDS instance to see it in the dashboard" -ForegroundColor White
Write-Host "3. Review DEPLOYMENT-GUIDE.md for advanced configuration" -ForegroundColor White
Write-Host ""
Write-Host "To create a test RDS instance:" -ForegroundColor Yellow
Write-Host "aws rds create-db-instance --db-instance-identifier test-dashboard --db-instance-class db.t3.micro --engine postgres --master-username admin --master-user-password TestPass123! --allocated-storage 20 --profile $AwsProfile" -ForegroundColor Gray
Write-Host ""

# Save outputs to file
$outputFile = "../deployment-outputs.txt"
@"
Deployment Outputs
==================
Date: $(Get-Date)
AWS Account: $AwsAccountId
AWS Region: $AwsRegion

Dashboard URL: $websiteUrl
API URL: $apiUrl
API Key: $apiKey

S3 Bucket: $bucketName
"@ | Out-File -FilePath $outputFile -Encoding utf8

Write-Host "Deployment details saved to: deployment-outputs.txt" -ForegroundColor Gray
Write-Host ""
