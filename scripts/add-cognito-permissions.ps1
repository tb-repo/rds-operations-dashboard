#!/usr/bin/env pwsh

# Add Cognito Admin Permissions to BFF Lambda
# Simple script to add the necessary Cognito permissions

$ErrorActionPreference = "Continue"

Write-Host "Adding Cognito Admin Permissions to BFF Lambda..." -ForegroundColor Cyan

# Get BFF Lambda role
try {
    Write-Host "Getting BFF Lambda role information..."
    
    $bffConfig = aws lambda get-function-configuration `
        --function-name "rds-dashboard-bff-prod" `
        --output json | ConvertFrom-Json
    
    $roleName = ($bffConfig.Role -split '/')[-1]
    Write-Host "BFF Lambda role: $roleName" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Could not get BFF Lambda configuration: $_" -ForegroundColor Red
    exit 1
}

# Create policy document
$policyDocument = @'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:ListUsers",
                "cognito-idp:AdminGetUser",
                "cognito-idp:AdminListGroupsForUser",
                "cognito-idp:AdminCreateUser",
                "cognito-idp:AdminDeleteUser",
                "cognito-idp:AdminUpdateUserAttributes",
                "cognito-idp:AdminSetUserPassword",
                "cognito-idp:AdminAddUserToGroup",
                "cognito-idp:AdminRemoveUserFromGroup",
                "cognito-idp:ListGroups",
                "cognito-idp:GetGroup"
            ],
            "Resource": "*"
        }
    ]
}
'@

# Save policy to file
$policyDocument | Out-File -FilePath "cognito-admin-policy.json" -Encoding utf8

# Create policy
$policyName = "RDSDashboardCognitoAdminPolicy"
$accountId = (aws sts get-caller-identity --query Account --output text)
$policyArn = "arn:aws:iam::${accountId}:policy/${policyName}"

Write-Host "Creating Cognito Admin policy..."

$createResult = aws iam create-policy `
    --policy-name $policyName `
    --policy-document file://cognito-admin-policy.json `
    --description "Cognito Admin permissions for RDS Dashboard BFF" `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Cognito Admin policy created" -ForegroundColor Green
} else {
    if ($createResult -like "*EntityAlreadyExists*") {
        Write-Host "Policy already exists, continuing..." -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: Failed to create policy: $createResult" -ForegroundColor Red
    }
}

# Attach policy to role
Write-Host "Attaching Cognito Admin policy to BFF Lambda role..."

$attachResult = aws iam attach-role-policy `
    --role-name $roleName `
    --policy-arn $policyArn `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Cognito Admin policy attached to BFF Lambda role" -ForegroundColor Green
} else {
    if ($attachResult -like "*already attached*" -or $attachResult -like "*NoSuchEntity*") {
        Write-Host "Policy may already be attached or role issue, continuing..." -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: Policy attachment issue: $attachResult" -ForegroundColor Yellow
    }
}

# Clean up
Remove-Item "cognito-admin-policy.json" -Force -ErrorAction SilentlyContinue

Write-Host "Cognito permissions setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test user management API"
Write-Host "  2. Check dashboard user management tab"
Write-Host "  3. Verify Cognito user pool access"