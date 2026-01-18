# Deploy API Gateway Stage Elimination
# Comprehensive deployment script for clean URL implementation

param(
    [string]$Environment = "production",
    [string]$BffApiUrl = "https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com",
    [string]$InternalApiUrl = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com",
    [switch]$ValidateOnly,
    [switch]$Verbose
)

Write-Host "API Gateway Stage Elimination Deployment" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "BFF API URL: $BffApiUrl" -ForegroundColor Yellow
Write-Host "Internal API URL: $InternalApiUrl" -ForegroundColor Yellow
Write-Host ""

$ErrorCount = 0
$WarningCount = 0

function Test-CleanUrl {
    param([string]$Url, [string]$Description)
    
    if ($Verbose) {
        Write-Host "  Testing: $Description" -ForegroundColor Cyan
        Write-Host "    URL: $Url" -ForegroundColor Gray
    }
    
    # Verify URL is clean (no stage prefixes)
    if ($Url -match "/prod/|/staging/|/dev/") {
        Write-Host "  ✗ FAIL: $Description - URL contains stage prefix" -ForegroundColor Red
        $script:ErrorCount++
        return $false
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Url -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  ✓ PASS: $Description" -ForegroundColor Green
        return $true
    }
    catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "  ✓ PASS: $Description (Expected auth error)" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "  ✗ FAIL: $Description - $($_.Exception.Message)" -ForegroundColor Red
            $script:ErrorCount++
            return $false
        }
    }
}

Write-Host "1. Validating Clean URL Structure" -ForegroundColor Magenta
Write-Host "=================================" -ForegroundColor Magenta

# Test BFF endpoints
$bffEndpoints = @(
    @{ Url = "$BffApiUrl/health"; Description = "BFF Health Check" },
    @{ Url = "$BffApiUrl/cors-config"; Description = "CORS Configuration" },
    @{ Url = "$BffApiUrl/api/health"; Description = "API Health Check" }
)

foreach ($endpoint in $bffEndpoints) {
    Test-CleanUrl -Url $endpoint.Url -Description $endpoint.Description
}

# Test Internal API endpoints (these will likely return auth errors, which is expected)
$internalEndpoints = @(
    @{ Url = "$InternalApiUrl/instances"; Description = "RDS Instances" },
    @{ Url = "$InternalApiUrl/operations"; Description = "RDS Operations" },
    @{ Url = "$InternalApiUrl/discovery"; Description = "RDS Discovery" }
)

foreach ($endpoint in $internalEndpoints) {
    Test-CleanUrl -Url $endpoint.Url -Description $endpoint.Description
}

Write-Host ""
Write-Host "2. Validating Environment Configuration" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta

# Check environment files for clean URLs
$envFiles = @(
    "frontend/.env",
    "frontend/.env.production", 
    "frontend/.env.example"
)

foreach ($envFile in $envFiles) {
    if (Test-Path $envFile) {
        $content = Get-Content $envFile -Raw
        if ($content -match "/prod|/staging|/dev") {
            Write-Host "  ✗ FAIL: $envFile contains stage prefixes" -ForegroundColor Red
            $ErrorCount++
        } else {
            Write-Host "  ✓ PASS: $envFile has clean URLs" -ForegroundColor Green
        }
    } else {
        Write-Host "  ⚠ WARNING: $envFile not found" -ForegroundColor Yellow
        $WarningCount++
    }
}

Write-Host ""
Write-Host "3. Deployment Actions" -ForegroundColor Magenta
Write-Host "====================" -ForegroundColor Magenta

if ($ValidateOnly) {
    Write-Host "Validation-only mode - skipping deployment actions" -ForegroundColor Yellow
} else {
    Write-Host "Ready to deploy the following components:" -ForegroundColor Cyan
    Write-Host "  - API Gateway configuration (remove /prod stages)" -ForegroundColor Gray
    Write-Host "  - BFF Lambda with service discovery" -ForegroundColor Gray
    Write-Host "  - Frontend with clean URL configuration" -ForegroundColor Gray
    Write-Host "  - Backend Lambda functions (if needed)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Deployment commands would be executed here..." -ForegroundColor Yellow
    Write-Host "  1. Update API Gateway stages to `$default" -ForegroundColor Gray
    Write-Host "  2. Deploy BFF Lambda with updated code" -ForegroundColor Gray
    Write-Host "  3. Update environment variables" -ForegroundColor Gray
    Write-Host "  4. Deploy frontend with clean URLs" -ForegroundColor Gray
}

Write-Host ""
Write-Host "4. Summary" -ForegroundColor Magenta
Write-Host "==========" -ForegroundColor Magenta

Write-Host "Validation Results:" -ForegroundColor Cyan
Write-Host "  Errors: $ErrorCount" -ForegroundColor $(if ($ErrorCount -eq 0) { "Green" } else { "Red" })
Write-Host "  Warnings: $WarningCount" -ForegroundColor $(if ($WarningCount -eq 0) { "Green" } else { "Yellow" })

if ($ErrorCount -eq 0) {
    Write-Host ""
    Write-Host "✓ API Gateway Stage Elimination is ready for deployment!" -ForegroundColor Green
    Write-Host "  All URLs are clean (no stage prefixes)" -ForegroundColor Green
    Write-Host "  Configuration files are updated" -ForegroundColor Green
    Write-Host "  System is validated and ready" -ForegroundColor Green
    
    if (-not $ValidateOnly) {
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor White
        Write-Host "  1. Review the deployment checklist" -ForegroundColor Gray
        Write-Host "  2. Execute the deployment in your AWS environment" -ForegroundColor Gray
        Write-Host "  3. Run post-deployment validation" -ForegroundColor Gray
        Write-Host "  4. Monitor system health" -ForegroundColor Gray
    }
    
    exit 0
} else {
    Write-Host ""
    Write-Host "✗ Issues found that need to be resolved before deployment" -ForegroundColor Red
    exit 1
}