# Deploy Authentication Stack and Create Initial Admin User
# This script deploys the Cognito User Pool and creates the first admin user

param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminEmail,
    
    [Parameter(Mandatory=$false)]
    [string]$FrontendDomain
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RDS Dashboard - Auth Stack Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Change to infrastructure directory
Set-Location -Path "$PSScriptRoot/../infrastructure"

# Set environment variable for frontend domain if provided
if ($FrontendDomain) {
    $env:FRONTEND_DOMAIN = $FrontendDomain
    Write-Host "Frontend Domain: $FrontendDomain" -ForegroundColor Green
}

Write-Host "Step 1: Deploying Auth Stack..." -ForegroundColor Yellow
Write-Host ""

# Deploy the auth stack
npx aws-cdk deploy "RDSDashboard-Auth-$Environment" --require-approval never

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Auth stack deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Auth stack deployed successfully!" -ForegroundColor Green
Write-Host ""

# Get stack outputs
Write-Host "Step 2: Retrieving Cognito configuration..." -ForegroundColor Yellow
$stackName = "RDSDashboard-Auth-$Environment"

$userPoolId = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" `
    --output text

$userPoolClientId = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" `
    --output text

$userPoolDomain = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolDomain'].OutputValue" `
    --output text

$hostedUIUrl = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='HostedUIUrl'].OutputValue" `
    --output text

$jwtIssuer = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='JwtIssuer'].OutputValue" `
    --output text

$region = aws configure get region

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cognito Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "User Pool ID:       $userPoolId" -ForegroundColor White
Write-Host "Client ID:          $userPoolClientId" -ForegroundColor White
Write-Host "Domain:             $userPoolDomain" -ForegroundColor White
Write-Host "Hosted UI URL:      $hostedUIUrl" -ForegroundColor White
Write-Host "JWT Issuer:         $jwtIssuer" -ForegroundColor White
Write-Host "Region:             $region" -ForegroundColor White
Write-Host ""

# Create initial admin user if email provided
if ($AdminEmail) {
    Write-Host "Step 3: Creating initial admin user..." -ForegroundColor Yellow
    Write-Host "Admin Email: $AdminEmail" -ForegroundColor White
    Write-Host ""
    
    # Generate temporary password
    $tempPassword = -join ((65..90) + (97..122) + (48..57) + (33,35,36,37,38,42,43,45,61,63,64) | Get-Random -Count 16 | ForEach-Object {[char]$_})
    
    # Create user
    aws cognito-idp admin-create-user `
        --user-pool-id $userPoolId `
        --username $AdminEmail `
        --user-attributes Name=email,Value=$AdminEmail Name=email_verified,Value=true `
        --temporary-password $tempPassword `
        --message-action SUPPRESS
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Admin user created successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Add user to Admin group
        Write-Host "Adding user to Admin group..." -ForegroundColor Yellow
        aws cognito-idp admin-add-user-to-group `
            --user-pool-id $userPoolId `
            --username $AdminEmail `
            --group-name Admin
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ User added to Admin group!" -ForegroundColor Green
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "Admin User Credentials" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "Email:              $AdminEmail" -ForegroundColor White
            Write-Host "Temporary Password: $tempPassword" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "⚠️  IMPORTANT: Save this password! You'll need to change it on first login." -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Host "❌ Failed to add user to Admin group" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ Failed to create admin user" -ForegroundColor Red
    }
} else {
    Write-Host "Step 3: Skipping admin user creation (no email provided)" -ForegroundColor Yellow
    Write-Host "To create an admin user later, run:" -ForegroundColor White
    Write-Host "  .\scripts\create-cognito-user.ps1 -Email admin@company.com -Group Admin" -ForegroundColor Cyan
    Write-Host ""
}

# Update frontend .env file
Write-Host "Step 4: Updating frontend configuration..." -ForegroundColor Yellow
$envFile = "$PSScriptRoot/../frontend/.env"

# Read existing .env or create new
$envContent = @()
if (Test-Path $envFile) {
    $envContent = Get-Content $envFile
}

# Remove old Cognito config if exists
$envContent = $envContent | Where-Object { 
    $_ -notmatch "^VITE_COGNITO_" 
}

# Add new Cognito config
$envContent += ""
$envContent += "# Cognito Configuration"
$envContent += "VITE_COGNITO_USER_POOL_ID=$userPoolId"
$envContent += "VITE_COGNITO_CLIENT_ID=$userPoolClientId"
$envContent += "VITE_COGNITO_DOMAIN=$userPoolDomain"
$envContent += "VITE_COGNITO_REGION=$region"
if ($FrontendDomain) {
    $envContent += "VITE_COGNITO_REDIRECT_URI=https://$FrontendDomain/callback"
    $envContent += "VITE_COGNITO_LOGOUT_URI=https://$FrontendDomain/"
} else {
    $envContent += "VITE_COGNITO_REDIRECT_URI=http://localhost:3000/callback"
    $envContent += "VITE_COGNITO_LOGOUT_URI=http://localhost:3000/"
}

# Write updated .env
$envContent | Out-File -FilePath $envFile -Encoding UTF8

Write-Host "✅ Frontend .env file updated!" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Update BFF with Cognito environment variables" -ForegroundColor White
Write-Host "2. Deploy BFF stack: .\scripts\deploy-bff.ps1" -ForegroundColor White
Write-Host "3. Deploy frontend with authentication enabled" -ForegroundColor White
if ($AdminEmail) {
    Write-Host "4. Login at: $hostedUIUrl" -ForegroundColor White
    Write-Host "   Email: $AdminEmail" -ForegroundColor White
    Write-Host "   Password: (temporary password shown above)" -ForegroundColor White
}
Write-Host ""
