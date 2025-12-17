# Run RDS Discovery Lambda
Write-Host "Running RDS Discovery..." -ForegroundColor Cyan

# Create payload file
$payload = @{
    operation = "discover"
} | ConvertTo-Json

$payload | Out-File -FilePath "discovery-payload.json" -Encoding UTF8

# Invoke Lambda
try {
    Write-Host "Invoking discovery Lambda..." -ForegroundColor Yellow
    aws lambda invoke `
        --function-name rds-discovery `
        --payload file://discovery-payload.json `
        discovery-response.json
    
    Write-Host "Discovery completed. Response:" -ForegroundColor Green
    Get-Content discovery-response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
    
    # Clean up
    Remove-Item discovery-payload.json -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "Error running discovery: $_" -ForegroundColor Red
}

# Check if inventory has data now
Write-Host "`nChecking inventory table..." -ForegroundColor Yellow
try {
    $count = aws dynamodb scan --table-name rds-inventory --select COUNT --output json | ConvertFrom-Json | Select-Object -ExpandProperty Count
    Write-Host "RDS Inventory now has $count items" -ForegroundColor Green
} catch {
    Write-Host "Could not check inventory: $_" -ForegroundColor Red
}

Write-Host "`nDiscovery process complete!" -ForegroundColor Cyan
Write-Host "You can now refresh your browser and try the operations again." -ForegroundColor Green
