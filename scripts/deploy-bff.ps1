# Deploy BFF Stack with Secrets Manager
# This script deploys the complete BFF solution

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod"
)

Write-Host "Deploying BFF Stack for environment: $Environment" -ForegroundColor Green

try {
    # Get current directory
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent $scriptDir

    # Navigate to infrastructure directory
    Set-Location -Path "$projectRoot/infrastructure"

    # Deploy the BFF stack
    Write-Host "Deploying BFF stack..." -ForegroundColor Yellow
    npx aws-cdk deploy "RDSDashboard-BFF" --require-approval never

    if ($LASTEXITCODE -ne 0) {
        throw "BFF stack deployment failed"
    }

    Write-Host "BFF stack deployed successfully" -ForegroundColor Green

    # Setup secrets
    Write-Host "Setting up Secrets Manager..." -ForegroundColor Yellow
    Set-Location -Path $projectRoot
    & "$scriptDir/setup-bff-secrets.ps1" -Environment $Environment

    # Get BFF URL for frontend configuration
    Write-Host "Getting BFF API URL..." -ForegroundColor Yellow
    $bffUrl = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-BFF" `
        --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
        --output text

    Write-Host ""
    Write-Host "BFF Deployment Complete!" -ForegroundColor Green
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "   BFF API URL: $bffUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "   1. Update frontend/.env with: VITE_BFF_API_URL=$bffUrl" -ForegroundColor White
    Write-Host "   2. Test the frontend: cd frontend; npm run dev" -ForegroundColor White
    Write-Host "   3. Deploy frontend: git push (GitHub Actions will deploy)" -ForegroundColor White

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
