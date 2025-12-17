# Multi-Account Testing Setup Script
# This script helps you set up a new AWS account for testing multi-account RDS discovery

param(
    [Parameter(Mandatory=$false)]
    [string]$NewAccountId,
    
    [Parameter(Mandatory=$false)]
    [string]$NewAccountEmail,
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateOrganization,
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateTestInstances
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  RDS Dashboard Multi-Account Testing Setup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Get current account ID
$currentAccountId = (aws sts get-caller-identity --query Account --output text)
Write-Host "`nCurrent Account ID: $currentAccountId" -ForegroundColor Green

# Step 1: Create AWS Organization (optional)
if ($CreateOrganization) {
    Write-Host "`n[1/6] Creating AWS Organization..." -ForegroundColor Yellow
    
    try {
        $orgId = aws organizations describe-organization --query 'Organization.Id' --output text 2>$null
        Write-Host "✓ Organization already exists: $orgId" -ForegroundColor Green
    } catch {
        Write-Host "Creating new organization..." -ForegroundColor Gray
        aws organizations create-organization --feature-set ALL
        Write-Host "✓ Organization created successfully" -ForegroundColor Green
    }
}

# Step 2: Create new account (if email provided)
if ($NewAccountEmail) {
    Write-Host "`n[2/6] Creating new AWS account..." -ForegroundColor Yellow
    Write-Host "Email: $NewAccountEmail" -ForegroundColor Gray
    
    $createResult = aws organizations create-account `
        --email $NewAccountEmail `
        --account-name "RDS-Dashboard-Test" `
        --role-name "OrganizationAccountAccessRole" `
        --output json | ConvertFrom-Json
    
    $requestId = $createResult.CreateAccountStatus.Id
    Write-Host "Account creation request ID: $requestId" -ForegroundColor Gray
    
    # Wait for account creation
    Write-Host "Waiting for account creation (this may take a few minutes)..." -ForegroundColor Gray
    $maxAttempts = 30
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        $status = aws organizations describe-create-account-status `
            --create-account-request-id $requestId `
            --query 'CreateAccountStatus.State' `
            --output text
        
        if ($status -eq "SUCCEEDED") {
            $NewAccountId = aws organizations describe-create-account-status `
                --create-account-request-id $requestId `
                --query 'CreateAccountStatus.AccountId' `
                --output text
            Write-Host "✓ Account created successfully: $NewAccountId" -ForegroundColor Green
            break
        } elseif ($status -eq "FAILED") {
            $failureReason = aws organizations describe-create-account-status `
                --create-account-request-id $requestId `
                --query 'CreateAccountStatus.FailureReason' `
                --output text
            Write-Host "✗ Account creation failed: $failureReason" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "Status: $status (attempt $($attempt + 1)/$maxAttempts)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
        $attempt++
    }
    
    if ($attempt -eq $maxAttempts) {
        Write-Host "✗ Account creation timed out" -ForegroundColor Red
        exit 1
    }
}

# Step 3: Update configuration
if ($NewAccountId) {
    Write-Host "`n[3/6] Updating dashboard configuration..." -ForegroundColor Yellow
    
    $configPath = "config/dashboard-config.json"
    $config = Get-Content $configPath | ConvertFrom-Json
    
    # Check if account already exists
    $existingAccount = $config.cross_account.target_accounts | Where-Object { $_.account_id -eq $NewAccountId }
    
    if ($existingAccount) {
        Write-Host "Account $NewAccountId already in configuration" -ForegroundColor Gray
        $existingAccount.enabled = $true
    } else {
        $newAccount = @{
            account_id = $NewAccountId
            account_name = "Test-Account"
            enabled = $true
        }
        $config.cross_account.target_accounts += $newAccount
        Write-Host "✓ Added account $NewAccountId to configuration" -ForegroundColor Green
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath
    Write-Host "✓ Configuration updated" -ForegroundColor Green
}

# Step 4: Display cross-account role setup instructions
Write-Host "`n[4/6] Cross-Account Role Setup" -ForegroundColor Yellow
Write-Host "You need to create a cross-account role in the new account." -ForegroundColor Gray
Write-Host "`nOption 1: Using AWS Console" -ForegroundColor Cyan
Write-Host "1. Log into the new account ($NewAccountId)"
Write-Host "2. Go to IAM > Roles > Create Role"
Write-Host "3. Select 'Another AWS account'"
Write-Host "4. Enter trusted account ID: $currentAccountId"
Write-Host "5. Require external ID: rds-dashboard-unique-id-12345"
Write-Host "6. Attach policy: ReadOnlyAccess + RDS full access"
Write-Host "7. Name the role: RDSDashboardCrossAccountRole"

Write-Host "`nOption 2: Using AWS CLI (in new account)" -ForegroundColor Cyan
Write-Host @"
# Switch to new account
aws sts assume-role \
  --role-arn "arn:aws:iam::${NewAccountId}:role/OrganizationAccountAccessRole" \
  --role-session-name "setup-cross-account"

# Create the role
aws iam create-role \
  --role-name RDSDashboardCrossAccountRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::${currentAccountId}:root"},
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {"sts:ExternalId": "rds-dashboard-unique-id-12345"}
      }
    }]
  }'

# Attach policies
aws iam attach-role-policy \
  --role-name RDSDashboardCrossAccountRole \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

aws iam attach-role-policy \
  --role-name RDSDashboardCrossAccountRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
"@

# Step 5: Create test RDS instances (optional)
if ($CreateTestInstances -and $NewAccountId) {
    Write-Host "`n[5/6] Creating test RDS instances..." -ForegroundColor Yellow
    Write-Host "This will create 4 db.t4g.micro instances (~$50/month)" -ForegroundColor Gray
    
    $confirmation = Read-Host "Continue? (yes/no)"
    if ($confirmation -eq "yes") {
        $regions = @(
            @{name="ap-southeast-1"; label="Singapore"},
            @{name="eu-west-2"; label="London"},
            @{name="ap-south-1"; label="Mumbai"},
            @{name="us-east-1"; label="Virginia"}
        )
        
        foreach ($region in $regions) {
            Write-Host "Creating instance in $($region.label)..." -ForegroundColor Gray
            $instanceId = "test-rds-$($region.name)"
            
            Write-Host @"
aws rds create-db-instance \
  --db-instance-identifier $instanceId \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --master-username testadmin \
  --master-user-password 'TestPassword123!' \
  --allocated-storage 20 \
  --region $($region.name) \
  --tags Key=Environment,Value=Test Key=Project,Value=RDS-Dashboard \
  --profile <new-account-profile>
"@
        }
        
        Write-Host "`n✓ Commands generated. Run them in the new account." -ForegroundColor Green
    }
}

# Step 6: Summary and next steps
Write-Host "`n[6/6] Setup Summary" -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Cyan

if ($NewAccountId) {
    Write-Host "✓ New Account ID: $NewAccountId" -ForegroundColor Green
    Write-Host "✓ Configuration updated" -ForegroundColor Green
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Create cross-account role in new account (see instructions above)"
Write-Host "2. Create test RDS instances in multiple regions"
Write-Host "3. Wait for instances to be available (~10 minutes)"
Write-Host "4. Run discovery: .\run-discovery.ps1"
Write-Host "5. Check dashboard for instances from all regions"

Write-Host "`nVerification Commands:" -ForegroundColor Cyan
Write-Host "# Test cross-account access"
Write-Host "aws sts assume-role --role-arn arn:aws:iam::${NewAccountId}:role/RDSDashboardCrossAccountRole --role-session-name test --external-id rds-dashboard-unique-id-12345"
Write-Host ""
Write-Host "# List RDS instances in new account"
Write-Host "aws rds describe-db-instances --region ap-southeast-1 --profile <new-account-profile>"

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
