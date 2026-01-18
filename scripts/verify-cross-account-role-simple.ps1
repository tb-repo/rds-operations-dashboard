# Simple verification script for cross-account role
# Run this after deploying the role via AWS Console

param(
    [string]$SecondaryAccount = "817214535871",
    [string]$RoleName = "RDSDashboardCrossAccountRole",
    [string]$ExternalId = "rds-dashboard-unique-external-id"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Cross-Account Role Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Testing role assumption..." -ForegroundColor Yellow
$roleArn = "arn:aws:iam::${SecondaryAccount}:role/${RoleName}"

$result = aws sts assume-role `
    --role-arn $roleArn `
    --role-session-name "verification-test" `
    --external-id $ExternalId `
    --duration-seconds 900 `
    2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ SUCCESS! Cross-account role is working!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Trigger discovery to find instances in secondary account:" -ForegroundColor White
    Write-Host "   aws lambda invoke --function-name rds-discovery-prod --region ap-southeast-1 response.json" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Wait 2-3 minutes for discovery to complete" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Refresh your dashboard to see all instances" -ForegroundColor White
    Write-Host "   URL: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Gray
} else {
    Write-Host "❌ FAILED: Cannot assume cross-account role" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host $result -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify CloudFormation stack created successfully in account $SecondaryAccount" -ForegroundColor White
    Write-Host "2. Check that role name is exactly: $RoleName" -ForegroundColor White
    Write-Host "3. Verify trust policy allows account 876595225096" -ForegroundColor White
    Write-Host "4. Confirm external ID matches: $ExternalId" -ForegroundColor White
}

Write-Host ""
