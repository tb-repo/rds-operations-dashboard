# Deploy Complete RDS Dashboard Infrastructure
# This script deploys all stacks in the correct dependency order

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Dashboard - Full Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Get current directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent $scriptDir

    # Navigate to infrastructure directory
    Set-Location -Path "$projectRoot/infrastructure"

    # Check if npm packages are installed
    if (-not (Test-Path "node_modules")) {
        Write-Host "Installing npm dependencies..." -ForegroundColor Yellow
        npm install
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed"
        }
    }

    # Bootstrap CDK (if needed)
    Write-Host "Checking CDK bootstrap..." -ForegroundColor Yellow
    npx aws-cdk bootstrap
    Write-Host ""

    # Deploy stacks in dependency order
    # Note: Stack names are defined in CDK app without environment suffix
    # Skipping RDSDashboard-Monitoring due to conflict with existing RDSDashboard-Monitoring-prod
    $stacks = @(
        "RDSDashboard-Data",
        "RDSDashboard-IAM", 
        "RDSDashboard-Compute",
        "RDSDashboard-Orchestration",
        "RDSDashboard-OnboardingOrchestration",
        "RDSDashboard-API",
        "RDSDashboard-Auth",
        "RDSDashboard-BFF",
        "RDSDashboard-WAF",
        "RDSDashboard-Frontend"
    )

    foreach ($stack in $stacks) {
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "Deploying: $stack" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        
        npx aws-cdk deploy $stack --require-approval never
        
        if ($LASTEXITCODE -ne 0) {
            throw "Deployment of $stack failed"
        }
        
        Write-Host "$stack deployed successfully" -ForegroundColor Green
        Write-Host ""
    }

    # Setup BFF secrets
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Setting up BFF Secrets Manager" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Set-Location -Path $projectRoot
    & "$scriptDir/setup-bff-secrets.ps1"

    # Get deployment outputs
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Deployment Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""

    $apiUrl = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-API" `
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' `
        --output text

    $bffUrl = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-BFF" `
        --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
        --output text

    Write-Host "Deployment Outputs:" -ForegroundColor Cyan
    Write-Host "   Internal API URL: $apiUrl" -ForegroundColor White
    Write-Host "   BFF API URL: $bffUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Update frontend/.env with: VITE_BFF_API_URL=$bffUrl" -ForegroundColor White
    Write-Host "   2. Test the API: .\scripts\test-bff.ps1" -ForegroundColor White
    Write-Host "   3. Deploy frontend: git push (GitHub Actions will deploy)" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Deployment Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}
