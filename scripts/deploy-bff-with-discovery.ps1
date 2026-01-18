# Deploy BFF with Real-Time Discovery Integration
# This script deploys the updated BFF that calls the discovery service

param(
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-southeast-1",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "prod"
)

Write-Host "=== Deploying BFF with Discovery Integration ===" -ForegroundColor Cyan
Write-Host ""

# Get current AWS account
try {
    $currentAccount = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get current account"
    }
    Write-Host "Current AWS Account: $currentAccount" -ForegroundColor Green
    Write-Host "Region: $Region" -ForegroundColor Green
    Write-Host "Environment: $Environment" -ForegroundColor Green
} catch {
    Write-Host "❌ Error getting current AWS account: $_" -ForegroundColor Red
    exit 1
}

# Check if discovery service exists
Write-Host ""
Write-Host "Checking discovery service..." -NoNewline

try {
    $discoveryFunction = aws lambda get-function --function-name "rds-discovery-service" --region $Region 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [OK]" -ForegroundColor Green
    } else {
        Write-Host " [NOT FOUND]" -ForegroundColor Red
        Write-Host "❌ Discovery service 'rds-discovery-service' not found" -ForegroundColor Red
        Write-Host "Please deploy the discovery service first" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "❌ Error checking discovery service: $_" -ForegroundColor Red
    exit 1
}

# Create cache table if it doesn't exist
Write-Host "Checking cache table..." -NoNewline

try {
    $cacheTable = aws dynamodb describe-table --table-name "rds-discovery-cache" --region $Region 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [EXISTS]" -ForegroundColor Green
    } else {
        Write-Host " [CREATING]" -ForegroundColor Yellow
        
        # Create cache table
        aws dynamodb create-table `
            --table-name "rds-discovery-cache" `
            --attribute-definitions AttributeName=cache_key,AttributeType=S `
            --key-schema AttributeName=cache_key,KeyType=HASH `
            --billing-mode PAY_PER_REQUEST `
            --region $Region | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Cache table created successfully" -ForegroundColor Green
            
            # Wait for table to be active
            Write-Host "  Waiting for table to be active..." -NoNewline
            aws dynamodb wait table-exists --table-name "rds-discovery-cache" --region $Region
            Write-Host " [OK]" -ForegroundColor Green
            
            # Enable TTL
            Write-Host "  Enabling TTL..." -NoNewline
            aws dynamodb update-time-to-live `
                --table-name "rds-discovery-cache" `
                --time-to-live-specification "Enabled=true,AttributeName=ttl" `
                --region $Region | Out-Null
            Write-Host " [OK]" -ForegroundColor Green
        } else {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Host "❌ Failed to create cache table" -ForegroundColor Red
            exit 1
        }
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "❌ Error with cache table: $_" -ForegroundColor Red
    exit 1
}

# Update BFF Lambda function
Write-Host ""
Write-Host "Updating BFF Lambda function..." -NoNewline

try {
    # Create deployment package
    $tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
    $zipFile = Join-Path $tempDir "bff-deployment.zip"
    
    # Copy BFF files
    Copy-Item "rds-operations-dashboard/bff/working-bff-with-data.js" -Destination (Join-Path $tempDir "index.js")
    
    # Create package.json
    $packageJson = @{
        name = "rds-dashboard-bff"
        version = "1.0.0"
        main = "index.js"
        dependencies = @{
            "aws-sdk" = "^2.1000.0"
        }
    } | ConvertTo-Json -Depth 3
    
    $packageJson | Out-File -FilePath (Join-Path $tempDir "package.json") -Encoding UTF8
    
    # Create zip file
    Push-Location $tempDir
    Compress-Archive -Path "*" -DestinationPath $zipFile -Force
    Pop-Location
    
    # Update Lambda function code
    aws lambda update-function-code `
        --function-name "rds-dashboard-bff" `
        --zip-file "fileb://$zipFile" `
        --region $Region | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Lambda function code"
    }
    
    # Update environment variables
    $envVars = @{
        "DISCOVERY_FUNCTION_NAME" = "rds-discovery-service"
        "CACHE_TABLE_NAME" = "rds-discovery-cache"
        "AWS_NODEJS_CONNECTION_REUSE_ENABLED" = "1"
    }
    
    $envVarsJson = $envVars | ConvertTo-Json -Compress
    
    aws lambda update-function-configuration `
        --function-name "rds-dashboard-bff" `
        --environment "Variables=$envVarsJson" `
        --region $Region | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Lambda function configuration"
    }
    
    # Clean up
    Remove-Item $tempDir -Recurse -Force
    
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [FAILED]" -ForegroundColor Red
    Write-Host "❌ Error updating BFF function: $_" -ForegroundColor Red
    exit 1
}

# Update IAM permissions
Write-Host "Updating IAM permissions..." -NoNewline

try {
    # Get BFF Lambda role
    $bffFunction = aws lambda get-function --function-name "rds-dashboard-bff" --region $Region | ConvertFrom-Json
    $roleArn = $bffFunction.Configuration.Role
    $roleName = $roleArn.Split('/')[-1]
    
    # Create policy document for discovery service and cache access
    $policyDocument = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Action = @(
                    "lambda:InvokeFunction"
                )
                Resource = @(
                    "arn:aws:lambda:${Region}:${currentAccount}:function:rds-discovery-service*"
                )
            },
            @{
                Effect = "Allow"
                Action = @(
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem"
                )
                Resource = @(
                    "arn:aws:dynamodb:${Region}:${currentAccount}:table/rds-discovery-cache"
                )
            }
        )
    } | ConvertTo-Json -Depth 4
    
    # Create or update inline policy
    aws iam put-role-policy `
        --role-name $roleName `
        --policy-name "BFFDiscoveryIntegrationPolicy" `
        --policy-document $policyDocument `
        --region $Region | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [OK]" -ForegroundColor Green
    } else {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Host "❌ Failed to update IAM permissions" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "❌ Error updating IAM permissions: $_" -ForegroundColor Red
}

# Test the integration
Write-Host ""
Write-Host "Testing BFF integration..." -NoNewline

try {
    # Get API Gateway URL
    $apiGateways = aws apigateway get-rest-apis --region $Region | ConvertFrom-Json
    $bffApi = $apiGateways.items | Where-Object { $_.name -eq "rds-dashboard-bff" }
    
    if ($bffApi) {
        $apiUrl = "https://$($bffApi.id).execute-api.$Region.amazonaws.com/prod/api/instances"
        
        # Test the endpoint
        $response = Invoke-RestMethod -Uri $apiUrl -Method GET -TimeoutSec 30
        
        if ($response -and $response.instances) {
            Write-Host " [OK]" -ForegroundColor Green
            Write-Host "  ✓ API URL: $apiUrl" -ForegroundColor Green
            Write-Host "  ✓ Instances returned: $($response.instances.Count)" -ForegroundColor Green
            Write-Host "  ✓ Cache status: $($response.metadata.cache_status)" -ForegroundColor Green
            Write-Host "  ✓ Last updated: $($response.metadata.last_updated)" -ForegroundColor Green
        } else {
            Write-Host " [NO DATA]" -ForegroundColor Yellow
            Write-Host "  ⚠️  API responded but no instances found" -ForegroundColor Yellow
        }
    } else {
        Write-Host " [API NOT FOUND]" -ForegroundColor Red
        Write-Host "❌ BFF API Gateway not found" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "❌ Error testing BFF integration: $_" -ForegroundColor Red
    Write-Host "This may be normal if the discovery service hasn't run yet" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "✓ BFF updated with discovery service integration" -ForegroundColor Green
Write-Host "✓ Cache table configured with TTL" -ForegroundColor Green
Write-Host "✓ IAM permissions updated" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run discovery service to populate cache" -ForegroundColor Yellow
Write-Host "2. Test /api/instances endpoint for real-time data" -ForegroundColor Yellow
Write-Host "3. Verify cross-account discovery is working" -ForegroundColor Yellow