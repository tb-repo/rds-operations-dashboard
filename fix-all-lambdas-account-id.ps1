# Fix all Lambda functions with AWS_ACCOUNT_ID environment variable
Write-Host "Updating all RDS Lambda functions with AWS_ACCOUNT_ID..." -ForegroundColor Cyan

$accountId = "876595225096"
$functions = @(
    "rds-operations-prod",
    "rds-health-monitor-prod",
    "rds-discovery-prod",
    "rds-query-handler-prod",
    "rds-cloudops-generator-prod",
    "rds-compliance-checker-prod",
    "rds-cost-analyzer-prod"
)

foreach ($func in $functions) {
    Write-Host "`nUpdating $func..." -ForegroundColor Yellow
    try {
        aws lambda update-function-configuration `
            --function-name $func `
            --environment "Variables={AWS_ACCOUNT_ID=$accountId}" `
            --output json | Out-Null
        Write-Host "✓ Updated $func" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed to update $func : $_" -ForegroundColor Red
    }
}

Write-Host "`nWaiting for updates to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "`nAll Lambda functions updated!" -ForegroundColor Green
Write-Host "Refresh your browser to test the fixes." -ForegroundColor Cyan
