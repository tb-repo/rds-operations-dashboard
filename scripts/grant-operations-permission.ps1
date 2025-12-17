# Grant Operations Permission to User
# This script adds a user to the DBA group to allow RDS operations

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail
)

Write-Host "Granting operations permission to user: $UserEmail" -ForegroundColor Cyan
Write-Host ""

# Get Cognito User Pool ID
Write-Host "Finding Cognito User Pool..." -ForegroundColor Yellow
$userPoolId = aws cognito-idp list-user-pools --max-results 10 --query "UserPools[?Name=='rds-dashboard-users'].Id" --output text

if ([string]::IsNullOrEmpty($userPoolId)) {
    Write-Host "Error: Could not find Cognito User Pool 'rds-dashboard-users'" -ForegroundColor Red
    exit 1
}

Write-Host "User Pool ID: $userPoolId" -ForegroundColor Green
Write-Host ""

# Get username from email
Write-Host "Finding user..." -ForegroundColor Yellow
$username = aws cognito-idp list-users `
    --user-pool-id $userPoolId `
    --filter "email = \`"$UserEmail\`"" `
    --query "Users[0].Username" `
    --output text

if ([string]::IsNullOrEmpty($username) -or $username -eq "None") {
    Write-Host "Error: User with email $UserEmail not found" -ForegroundColor Red
    exit 1
}

Write-Host "Username: $username" -ForegroundColor Green
Write-Host ""

# Check current groups
Write-Host "Current groups:" -ForegroundColor Yellow
aws cognito-idp admin-list-groups-for-user `
    --user-pool-id $userPoolId `
    --username $username `
    --query "Groups[].GroupName" `
    --output table

Write-Host ""

# Add user to DBA group
Write-Host "Adding user to DBA group..." -ForegroundColor Cyan
aws cognito-idp admin-add-user-to-group `
    --user-pool-id $userPoolId `
    --username $username `
    --group-name DBA

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS! User added to DBA group" -ForegroundColor Green
    Write-Host ""
    Write-Host "The user now has the following permissions:" -ForegroundColor Cyan
    Write-Host "  - view_instances" -ForegroundColor White
    Write-Host "  - view_metrics" -ForegroundColor White
    Write-Host "  - view_compliance" -ForegroundColor White
    Write-Host "  - view_costs" -ForegroundColor White
    Write-Host "  - execute_operations (NEW!)" -ForegroundColor Green
    Write-Host "  - generate_cloudops" -ForegroundColor White
    Write-Host "  - trigger_discovery" -ForegroundColor White
    Write-Host ""
    Write-Host "User needs to log out and log back in for changes to take effect." -ForegroundColor Yellow
} else {
    Write-Host "Error: Failed to add user to DBA group" -ForegroundColor Red
    exit 1
}

# Verify
Write-Host ""
Write-Host "Verifying groups:" -ForegroundColor Yellow
aws cognito-idp admin-list-groups-for-user `
    --user-pool-id $userPoolId `
    --username $username `
    --query "Groups[].GroupName" `
    --output table
