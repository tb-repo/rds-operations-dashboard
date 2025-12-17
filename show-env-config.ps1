# Show Current Environment Configuration
Write-Host "=== RDS Dashboard Environment Configuration ===" -ForegroundColor Cyan

Write-Host "`nLocal Development (.env):" -ForegroundColor Yellow
if (Test-Path "frontend/.env") {
    Get-Content "frontend/.env" | Select-String "VITE_COGNITO" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor White
    }
} else {
    Write-Host "  File not found" -ForegroundColor Red
}

Write-Host "`nProduction (.env.production):" -ForegroundColor Yellow
if (Test-Path "frontend/.env.production") {
    Get-Content "frontend/.env.production" | Select-String "VITE_COGNITO" | ForEach-Object {
        Write-Host "  $_" -ForegroundColor White
    }
} else {
    Write-Host "  File not found" -ForegroundColor Red
}

Write-Host "`nAWS Cognito Configuration:" -ForegroundColor Yellow
$domain = aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Auth `
    --query "Stacks[0].Outputs[?OutputKey=='HostedUIUrl'].OutputValue" `
    --output text 2>$null

if ($domain) {
    Write-Host "  Domain: $domain" -ForegroundColor White
} else {
    Write-Host "  Could not fetch from AWS" -ForegroundColor Red
}

Write-Host "`nCallback URLs in Cognito:" -ForegroundColor Yellow
$callbacks = aws cognito-idp describe-user-pool-client `
    --user-pool-id ap-southeast-1_4tyxh4qJe `
    --client-id 28e031hsul0mi91k0s6f33bs7s `
    --query "UserPoolClient.CallbackURLs" `
    --output json 2>$null | ConvertFrom-Json

if ($callbacks) {
    $callbacks | ForEach-Object {
        Write-Host "  OK: $_" -ForegroundColor Green
    }
} else {
    Write-Host "  Could not fetch from AWS" -ForegroundColor Red
}

Write-Host "`nConfiguration Status:" -ForegroundColor Cyan
Write-Host "  Local dev ready: http://localhost:3000" -ForegroundColor White
Write-Host "  CloudFront ready: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor White
Write-Host "`nNext: Restart your dev server to apply changes" -ForegroundColor Yellow
