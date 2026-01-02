# Test Error Resolution Endpoints
# Quick test script to verify the 500 error fix

param(
    [Parameter(Mandatory=$false)]
    [string]$BffUrl = ""
)

Write-Host "Testing Error Resolution Endpoints" -ForegroundColor Green

# Get BFF URL if not provided
if ([string]::IsNullOrEmpty($BffUrl)) {
    Write-Host "Getting BFF URL from CloudFormation..." -ForegroundColor Yellow
    $BffUrl = aws cloudformation describe-stacks `
        --stack-name "RDSDashboard-BFF" `
        --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' `
        --output text
    
    if ([string]::IsNullOrEmpty($BffUrl)) {
        Write-Host "Error: Could not get BFF URL. Please provide it manually." -ForegroundColor Red
        exit 1
    }
}

Write-Host "BFF URL: $BffUrl" -ForegroundColor Cyan

# Test endpoints
$endpoints = @(
    "/api/errors/dashboard",
    "/api/errors/statistics"
)

foreach ($endpoint in $endpoints) {
    Write-Host ""
    Write-Host "Testing: $endpoint" -ForegroundColor Yellow
    
    try {
        $response = Invoke-RestMethod -Uri "$BffUrl$endpoint" -Method GET -Headers @{
            "Content-Type" = "application/json"
        } -ErrorAction Stop
        
        Write-Host "✅ SUCCESS: $endpoint" -ForegroundColor Green
        Write-Host "Response keys: $($response.PSObject.Properties.Name -join ', ')" -ForegroundColor White
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "❌ FAILED: $endpoint (Status: $statusCode)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Test completed!" -ForegroundColor Green