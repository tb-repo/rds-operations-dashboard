# Run RDS Discovery Lambda - Simple Version
Write-Host "Running RDS Discovery..." -ForegroundColor Cyan

# Create simple payload file with ASCII encoding
'{"operation":"discover"}' | Out-File -FilePath "payload.json" -Encoding ASCII -NoNewline

# Invoke Lambda
Write-Host "Invoking discovery Lambda..." -ForegroundColor Yellow
aws lambda invoke --function-name rds-discovery --payload file://payload.json response.json

# Show response
if (Test-Path response.json) {
    Write-Host "`nDiscovery Response:" -ForegroundColor Green
    Get-Content response.json
}

# Check inventory count
Write-Host "`nChecking inventory..." -ForegroundColor Yellow
$result = aws dynamodb scan --table-name rds-inventory --select COUNT --output json | ConvertFrom-Json
Write-Host "RDS Inventory has $($result.Count) items" -ForegroundColor Green

# Cleanup
Remove-Item payload.json -ErrorAction SilentlyContinue
Remove-Item response.json -ErrorAction SilentlyContinue

Write-Host "`nDone! Refresh your browser to see the data." -ForegroundColor Cyan
