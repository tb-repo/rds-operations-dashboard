# Diagnose User Permissions Script
# This script helps diagnose why operations are returning 403 Forbidden

Write-Host "=== RDS Dashboard User Permissions Diagnostic ===" -ForegroundColor Green
Write-Host ""

# Function to check Cognito user groups
function Check-CognitoUser {
    param(
        [string]$UserPoolId,
        [string]$Username
    )
    
    Write-Host "Checking Cognito user: $Username" -ForegroundColor Yellow
    
    try {
        # Get user details
        $userDetails = aws cognito-idp admin-get-user `
            --user-pool-id $UserPoolId `
            --username $Username `
            --output json | ConvertFrom-Json
        
        Write-Host "✅ User found: $($userDetails.Username)" -ForegroundColor Green
        Write-Host "   Status: $($userDetails.UserStatus)" -ForegroundColor Cyan
        Write-Host "   Enabled: $($userDetails.Enabled)" -ForegroundColor Cyan
        
        # Get user groups
        $userGroups = aws cognito-idp admin-list-groups-for-user `
            --user-pool-id $UserPoolId `
            --username $Username `
            --output json | ConvertFrom-Json
        
        if ($userGroups.Groups.Count -eq 0) {
            Write-Host "❌ User has NO groups assigned!" -ForegroundColor Red
            Write-Host "   This is why operations return 403 Forbidden" -ForegroundColor Red
            return $false
        } else {
            Write-Host "✅ User groups:" -ForegroundColor Green
            foreach ($group in $userGroups.Groups) {
                Write-Host "   - $($group.GroupName)" -ForegroundColor Cyan
                
                # Check if group has execute_operations permission
                if ($group.GroupName -eq "Admin" -or $group.GroupName -eq "DBA") {
                    Write-Host "     ✅ Has execute_operations permission" -ForegroundColor Green
                } elseif ($group.GroupName -eq "ReadOnly") {
                    Write-Host "     ❌ ReadOnly - NO execute_operations permission" -ForegroundColor Red
                } else {
                    Write-Host "     ⚠️  Unknown group - check permissions" -ForegroundColor Yellow
                }
            }
            return $true
        }
    } catch {
        Write-Host "❌ Error checking user: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to list all available groups
function List-CognitoGroups {
    param([string]$UserPoolId)
    
    Write-Host "Available Cognito groups:" -ForegroundColor Yellow
    
    try {
        $groups = aws cognito-idp list-groups `
            --user-pool-id $UserPoolId `
            --output json | ConvertFrom-Json
        
        if ($groups.Groups.Count -eq 0) {
            Write-Host "❌ No groups found in user pool!" -ForegroundColor Red
            return
        }
        
        foreach ($group in $groups.Groups) {
            Write-Host "  - $($group.GroupName): $($group.Description)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "❌ Error listing groups: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to add user to group
function Add-UserToGroup {
    param(
        [string]$UserPoolId,
        [string]$Username,
        [string]$GroupName
    )
    
    Write-Host "Adding user $Username to group $GroupName..." -ForegroundColor Yellow
    
    try {
        aws cognito-idp admin-add-user-to-group `
            --user-pool-id $UserPoolId `
            --username $Username `
            --group-name $GroupName
        
        Write-Host "✅ Successfully added user to group!" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "❌ Error adding user to group: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main diagnostic flow
try {
    # Get Cognito configuration
    Write-Host "Getting Cognito configuration..." -ForegroundColor Yellow
    
    # Try to get from BFF environment variables
    $bffFunction = "rds-dashboard-bff"
    $envVars = aws lambda get-function-configuration `
        --function-name $bffFunction `
        --query "Environment.Variables" `
        --output json | ConvertFrom-Json
    
    $userPoolId = $envVars.COGNITO_USER_POOL_ID
    $region = $envVars.COGNITO_REGION
    
    if (-not $userPoolId) {
        Write-Host "❌ Could not get Cognito User Pool ID from BFF Lambda" -ForegroundColor Red
        Write-Host "Please provide it manually:" -ForegroundColor Yellow
        $userPoolId = Read-Host "Enter Cognito User Pool ID"
    }
    
    Write-Host "✅ User Pool ID: $userPoolId" -ForegroundColor Green
    Write-Host "✅ Region: $region" -ForegroundColor Green
    Write-Host ""
    
    # List available groups
    List-CognitoGroups -UserPoolId $userPoolId
    Write-Host ""
    
    # Get username to check
    Write-Host "Enter the username/email of the user experiencing 403 errors:" -ForegroundColor Yellow
    $username = Read-Host "Username"
    
    if (-not $username) {
        Write-Host "❌ No username provided" -ForegroundColor Red
        exit 1
    }
    
    # Check user permissions
    $hasGroups = Check-CognitoUser -UserPoolId $userPoolId -Username $username
    Write-Host ""
    
    # If user has no groups or only ReadOnly, offer to fix
    if (-not $hasGroups) {
        Write-Host "🔧 SOLUTION: Add user to Admin or DBA group" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "Available options:" -ForegroundColor Yellow
        Write-Host "1. Admin - Full access including user management" -ForegroundColor Cyan
        Write-Host "2. DBA - Database operations (recommended for most users)" -ForegroundColor Cyan
        Write-Host "3. ReadOnly - View only (cannot perform operations)" -ForegroundColor Cyan
        Write-Host ""
        
        $choice = Read-Host "Add user to which group? (1=Admin, 2=DBA, 3=ReadOnly, N=No)"
        
        switch ($choice) {
            "1" { 
                if (Add-UserToGroup -UserPoolId $userPoolId -Username $username -GroupName "Admin") {
                    Write-Host "✅ User now has Admin permissions and can perform operations!" -ForegroundColor Green
                }
            }
            "2" { 
                if (Add-UserToGroup -UserPoolId $userPoolId -Username $username -GroupName "DBA") {
                    Write-Host "✅ User now has DBA permissions and can perform operations!" -ForegroundColor Green
                }
            }
            "3" { 
                if (Add-UserToGroup -UserPoolId $userPoolId -Username $username -GroupName "ReadOnly") {
                    Write-Host "✅ User now has ReadOnly permissions (cannot perform operations)" -ForegroundColor Green
                }
            }
            default {
                Write-Host "No changes made. User will continue to get 403 errors for operations." -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host ""
    Write-Host "=== Diagnostic Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "- Operations require 'execute_operations' permission" -ForegroundColor Cyan
    Write-Host "- Only Admin and DBA groups have this permission" -ForegroundColor Cyan
    Write-Host "- ReadOnly users cannot perform operations (by design)" -ForegroundColor Cyan
    Write-Host "- User must log out and log back in for group changes to take effect" -ForegroundColor Magenta
    
} catch {
    Write-Host "❌ Diagnostic failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual steps to fix 403 errors:" -ForegroundColor Yellow
    Write-Host "1. Get your Cognito User Pool ID from AWS Console" -ForegroundColor Cyan
    Write-Host "2. Find your username in Cognito Users" -ForegroundColor Cyan
    Write-Host "3. Add the user to 'Admin' or 'DBA' group" -ForegroundColor Cyan
    Write-Host "4. User must log out and log back in" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")