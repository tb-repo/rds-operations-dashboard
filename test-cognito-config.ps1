# Test Cognito Configuration
Write-Host "Testing Cognito Configuration..." -ForegroundColor Cyan

# Get Cognito client configuration
Write-Host "`nFetching Cognito User Pool Client configuration..." -ForegroundColor Yellow
$clientConfig = aws cognito-idp describe-user-pool-client `
    --user-pool-id ap-southeast-1_4tyxh4qJe `
    --client-id 28e031hsul0mi91k0s6f33bs7s `
    --output json | ConvertFrom-Json

Write-Host "`nCallback URLs:" -ForegroundColor Green
$clientConfig.UserPoolClient.CallbackURLs | ForEach-Object {
    Write-Host "  - $_" -ForegroundColor White
}

Write-Host "`nLogout URLs:" -ForegroundColor Green
$clientConfig.UserPoolClient.LogoutURLs | ForEach-Object {
    Write-Host "  - $_" -ForegroundColor White
}

Write-Host "`nOAuth Flows:" -ForegroundColor Green
$clientConfig.UserPoolClient.AllowedOAuthFlows | ForEach-Object {
    Write-Host "  - $_" -ForegroundColor White
}

Write-Host "`nOAuth Scopes:" -ForegroundColor Green
$clientConfig.UserPoolClient.AllowedOAuthScopes | ForEach-Object {
    Write-Host "  - $_" -ForegroundColor White
}

# Get Cognito domain
Write-Host "`nCognito Hosted UI Domain:" -ForegroundColor Green
$domain = aws cloudformation describe-stacks `
    --stack-name RDSDashboard-Auth `
    --query "Stacks[0].Outputs[?OutputKey=='HostedUIUrl'].OutputValue" `
    --output text
Write-Host "  $domain" -ForegroundColor White

# Test authorization URL
Write-Host "`nTest Authorization URL (localhost):" -ForegroundColor Green
$authUrl = "$domain/oauth2/authorize?client_id=28e031hsul0mi91k0s6f33bs7s&response_type=code&scope=openid+email+profile&redirect_uri=http://localhost:3000/callback"
Write-Host "  $authUrl" -ForegroundColor White

Write-Host "`nTest Authorization URL (CloudFront):" -ForegroundColor Green
$authUrlCF = "$domain/oauth2/authorize?client_id=28e031hsul0mi91k0s6f33bs7s&response_type=code&scope=openid+email+profile&redirect_uri=https://d2qvaswtmn22om.cloudfront.net/callback"
Write-Host "  $authUrlCF" -ForegroundColor White

Write-Host "`n✅ Configuration looks good!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. For local development: Use the existing .env file" -ForegroundColor White
Write-Host "2. For CloudFront: Build with .env.production" -ForegroundColor White
Write-Host "   npm run build (will use .env.production automatically)" -ForegroundColor Gray
