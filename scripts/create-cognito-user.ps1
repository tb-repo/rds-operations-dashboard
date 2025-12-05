# Create Cognito User and Assign to Group
# Helper script to create additional users in Cognito

param(
    [Parameter(Mandatory=$true)]
    [string]$Email,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Admin", "DBA", "ReadOnly")]
    [string]$Group,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod",
    
    [Parameter(Mandatory=$false)]
    [string]$FullName
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Create Cognito User" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get User Pool ID from CloudFormation
$stackName = "RDSDashboard-Auth-$Environment"
Write-Host "Getting User Pool ID from stack: $stackName" -ForegroundColor Yellow

$userPoolId = aws cloudformation describe-stacks `
    --stack-name $stackName `
    --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" `
    --output text

if (-not $userPoolId) {
    Write-Host "❌ Failed to get User Pool ID. Is the auth stack deployed?" -ForegroundColor Red
    exit 1
}

Write-Host "User Pool ID: $userPoolId" -ForegroundColor Green
Write-Host ""

# Generate temporary password
Write-Host "Generating temporary password..." -ForegroundColor Yellow
$tempPassword = -join ((65..90) + (97..122) + (48..57) + (33,35,36,37,38,42,43,45,61,63,64) | Get-Random -Count 16 | ForEach-Object {[char]$_})

# Prepare user attributes
$userAttributes = @(
    "Name=email,Value=$Email",
    "Name=email_verified,Value=true"
)

if ($FullName) {
    $userAttributes += "Name=name,Value=$FullName"
}

# Create user
Write-Host "Creating user: $Email" -ForegroundColor Yellow
$userAttributesString = $userAttributes -join " "

aws cognito-idp admin-create-user `
    --user-pool-id $userPoolId `
    --username $Email `
    --user-attributes $userAttributesString `
    --temporary-password $tempPassword `
    --message-action SUPPRESS

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create user" -ForegroundColor Red
    exit 1
}

Write-Host "✅ User created successfully!" -ForegroundColor Green
Write-Host ""

# Add user to group
Write-Host "Adding user to group: $Group" -ForegroundColor Yellow
aws cognito-idp admin-add-user-to-group `
    --user-pool-id $userPoolId `
    --username $Email `
    --group-name $Group

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to add user to group" -ForegroundColor Red
    exit 1
}

Write-Host "✅ User added to $Group group!" -ForegroundColor Green
Write-Host ""

# Display credentials
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "User Created Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Email:              $Email" -ForegroundColor White
Write-Host "Group:              $Group" -ForegroundColor White
Write-Host "Temporary Password: $tempPassword" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  IMPORTANT: Send these credentials to the user securely." -ForegroundColor Yellow
Write-Host "    They will be required to change the password on first login." -ForegroundColor Yellow
Write-Host ""

# Display group permissions
Write-Host "Group Permissions:" -ForegroundColor Cyan
switch ($Group) {
    "Admin" {
        Write-Host "  ✓ View all dashboards" -ForegroundColor Green
        Write-Host "  ✓ Execute operations (non-production)" -ForegroundColor Green
        Write-Host "  ✓ Generate CloudOps requests" -ForegroundColor Green
        Write-Host "  ✓ Trigger discovery scans" -ForegroundColor Green
        Write-Host "  ✓ Manage users and roles" -ForegroundColor Green
    }
    "DBA" {
        Write-Host "  ✓ View all dashboards" -ForegroundColor Green
        Write-Host "  ✓ Execute operations (non-production)" -ForegroundColor Green
        Write-Host "  ✓ Generate CloudOps requests" -ForegroundColor Green
        Write-Host "  ✓ Trigger discovery scans" -ForegroundColor Green
        Write-Host "  ✗ Manage users and roles" -ForegroundColor Red
    }
    "ReadOnly" {
        Write-Host "  ✓ View all dashboards" -ForegroundColor Green
        Write-Host "  ✗ Execute operations" -ForegroundColor Red
        Write-Host "  ✗ Generate CloudOps requests" -ForegroundColor Red
        Write-Host "  ✗ Trigger discovery scans" -ForegroundColor Red
        Write-Host "  ✗ Manage users and roles" -ForegroundColor Red
    }
}
Write-Host ""
