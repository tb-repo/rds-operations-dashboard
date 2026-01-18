# API Gateway Stage Elimination Deployment Script
# Fixed version with proper PowerShell syntax

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
    param(
        [string]$Url, 
        [string]$Description
    )
    
    if ($Verbose) {
        Write-Host "  Testing: $Description" -ForegroundColor Cyan
        Write-Host "    URL: $Url" -ForegroundColor Gray
    }
    
    # Verify URL is clean (no stage prefixes)
    if ($Url -match "/prod/|/staging/|/dev/") {
        Write-Host "  X FAIL: $Description - URL contains stage prefix" -ForegroundColor Red
        $script:ErrorCount++
        return $false
    }
    
    try {
        $response = Invoke-RestMethod -Uri $Url -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  + PASS: $Description" -ForegroundColor Green
        return $true
    }
    catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "  + PASS: $Description (Expected auth error)" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "  X FAIL: $Description - $($_.Exception.Message)" -ForegroundColor Red
            $script:ErrorCount++
            return $false
        }
    }
}

Write-Host "1. Validating Clean URL Structure" -ForegroundColor Magenta
Write-Host "=================================" -ForegroundColor Magenta

# Test BFF endpoints
$bffEndpoints = @(
    @{ Url = "$BffApiUrl/health"; Description = "BFF Health Check" }
    @{ Url = "$BffApiUrl/cors-config"; Description = "CORS Configuration" }
    @{ Url = "$BffApiUrl/api/health"; Description = "API Health Check" }
)

foreach ($endpoint in $bffEndpoints) {
    Test-CleanUrl -Url $endpoint.Url -Description $endpoint.Description
}

# Test Internal API endpoints
$internalEndpoints = @(
    @{ Url = "$InternalApiUrl/instances"; Description = "RDS Instances" }
    @{ Url = "$InternalApiUrl/operations"; Description = "RDS Operations" }
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
    "frontend/.env"
    "frontend/.env.production"
    "frontend/.env.example"
)

foreach ($envFile in $envFiles) {
    if (Test-Path $envFile) {
        $content = Get-Content $envFile -Raw
        if ($content -match "/prod|/staging|/dev") {
            Write-Host "  X FAIL: $envFile contains stage prefixes" -ForegroundColor Red
            $ErrorCount++
        } else {
            Write-Host "  + PASS: $envFile has clean URLs" -ForegroundColor Green
        }
    } else {
        Write-Host "  ! WARNING: $envFile not found" -ForegroundColor Yellow
        $WarningCount++
    }
}

Write-Host ""
Write-Host "3. Summary" -ForegroundColor Magenta
Write-Host "==========" -ForegroundColor Magenta

Write-Host "Validation Results:" -ForegroundColor Cyan
if ($ErrorCount -eq 0) {
    Write-Host "  Errors: $ErrorCount" -ForegroundColor Green
} else {
    Write-Host "  Errors: $ErrorCount" -ForegroundColor Red
}

if ($WarningCount -eq 0) {
    Write-Host "  Warnings: $WarningCount" -ForegroundColor Green
} else {
    Write-Host "  Warnings: $WarningCount" -ForegroundColor Yellow
}

if ($ErrorCount -eq 0) {
    Write-Host ""
    Write-Host "+ API Gateway Stage Elimination validation PASSED!" -ForegroundColor Green
    Write-Host "  All URLs are clean (no stage prefixes)" -ForegroundColor Green
    Write-Host "  Configuration files are updated" -ForegroundColor Green
    Write-Host "  System is validated and ready" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "X Issues found that need to be resolved" -ForegroundColor Red
    exit 1
}