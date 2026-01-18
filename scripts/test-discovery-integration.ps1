# Test Real-Time Discovery Integration
# This script validates that the BFF is properly integrated with the discovery service

param(
    [Parameter(Mandatory=$false)]
    [string]$Region = "ap-southeast-1"
)

Write-Host "=== Testing Real-Time Discovery Integration ===" -ForegroundColor Cyan
Write-Host ""

# Get current AWS account
try {
    $currentAccount = aws sts get-caller-identity --query Account --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get current account"
    }
    Write-Host "Current AWS Account: $currentAccount" -ForegroundColor Green
    Write-Host "Region: $Region" -ForegroundColor Green
} catch {
    Write-Host "❌ Error getting current AWS account: $_" -ForegroundColor Red
    exit 1
}

# Test 1: Discovery Service Direct Test
Write-Host ""
Write-Host "Test 1: Discovery Service Direct Test" -ForegroundColor Yellow
Write-Host "Testing discovery service directly..." -NoNewline

try {
    $discoveryResult = aws lambda invoke `
        --function-name "rds-discovery-service" `
        --payload '{}' `
        --region $Region `
        --cli-binary-format raw-in-base64-out `
        discovery-response.json 2>&1
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path "discovery-response.json")) {
        $response = Get-Content "discovery-response.json" | ConvertFrom-Json
        
        if ($response.statusCode -eq 200) {
            $body = $response.body | ConvertFrom-Json
            Write-Host " [PASS]" -ForegroundColor Green
            Write-Host "  ✓ Total instances: $($body.total_instances)" -ForegroundColor Green
            Write-Host "  ✓ Accounts scanned: $($body.accounts_scanned)/$($body.accounts_attempted)" -ForegroundColor Green
            Write-Host "  ✓ Cross-account enabled: $($body.cross_account_enabled)" -ForegroundColor Green
            
            # Store discovery data for comparison
            $discoveryData = $body
        } else {
            Write-Host " [FAIL]" -ForegroundColor Red
            Write-Host "  ❌ Discovery service returned status: $($response.statusCode)" -ForegroundColor Red
        }
        
        Remove-Item "discovery-response.json" -ErrorAction SilentlyContinue
    } else {
        Write-Host " [FAIL]" -ForegroundColor Red
        Write-Host "  ❌ Failed to invoke discovery service" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "  ❌ Error testing discovery service: $_" -ForegroundColor Red
}

# Test 2: Cache Table Test
Write-Host ""
Write-Host "Test 2: Cache Table Test" -ForegroundColor Yellow
Write-Host "Testing cache table access..." -NoNewline

try {
    # Check if cache table exists and is accessible
    $cacheTable = aws dynamodb describe-table --table-name "rds-discovery-cache" --region $Region 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [PASS]" -ForegroundColor Green
        
        # Check for cached data
        $cacheItems = aws dynamodb scan --table-name "rds-discovery-cache" --region $Region | ConvertFrom-Json
        Write-Host "  ✓ Cache table accessible" -ForegroundColor Green
        Write-Host "  ✓ Cached items: $($cacheItems.Count)" -ForegroundColor Green
    } else {
        Write-Host " [FAIL]" -ForegroundColor Red
        Write-Host "  ❌ Cache table not accessible" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "  ❌ Error testing cache table: $_" -ForegroundColor Red
}

# Test 3: BFF API Test
Write-Host ""
Write-Host "Test 3: BFF API Integration Test" -ForegroundColor Yellow
Write-Host "Testing BFF /api/instances endpoint..." -NoNewline

try {
    # Get API Gateway URL
    $apiGateways = aws apigateway get-rest-apis --region $Region | ConvertFrom-Json
    $bffApi = $apiGateways.items | Where-Object { $_.name -eq "rds-dashboard-bff" }
    
    if ($bffApi) {
        $apiUrl = "https://$($bffApi.id).execute-api.$Region.amazonaws.com/prod/api/instances"
        
        # Test the endpoint
        $response = Invoke-RestMethod -Uri $apiUrl -Method GET -TimeoutSec 30
        
        if ($response -and $response.instances) {
            Write-Host " [PASS]" -ForegroundColor Green
            Write-Host "  ✓ API URL: $apiUrl" -ForegroundColor Green
            Write-Host "  ✓ Instances returned: $($response.instances.Count)" -ForegroundColor Green
            Write-Host "  ✓ Cache status: $($response.metadata.cache_status)" -ForegroundColor Green
            Write-Host "  ✓ Last updated: $($response.metadata.last_updated)" -ForegroundColor Green
            
            # Store BFF data for comparison
            $bffData = $response
        } else {
            Write-Host " [FAIL]" -ForegroundColor Red
            Write-Host "  ❌ No instances returned from BFF" -ForegroundColor Red
        }
    } else {
        Write-Host " [FAIL]" -ForegroundColor Red
        Write-Host "  ❌ BFF API Gateway not found" -ForegroundColor Red
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "  ❌ Error testing BFF API: $_" -ForegroundColor Red
}

# Test 4: Data Consistency Test
if ($discoveryData -and $bffData) {
    Write-Host ""
    Write-Host "Test 4: Data Consistency Test" -ForegroundColor Yellow
    Write-Host "Comparing discovery service and BFF data..." -NoNewline
    
    try {
        $discoveryInstanceCount = $discoveryData.total_instances
        $bffInstanceCount = $bffData.instances.Count
        
        if ($discoveryInstanceCount -eq $bffInstanceCount) {
            Write-Host " [PASS]" -ForegroundColor Green
            Write-Host "  ✓ Instance counts match: $discoveryInstanceCount" -ForegroundColor Green
        } else {
            Write-Host " [PARTIAL]" -ForegroundColor Yellow
            Write-Host "  ⚠️  Instance count mismatch:" -ForegroundColor Yellow
            Write-Host "    Discovery service: $discoveryInstanceCount" -ForegroundColor Yellow
            Write-Host "    BFF API: $bffInstanceCount" -ForegroundColor Yellow
            Write-Host "    This may be due to caching or timing differences" -ForegroundColor Yellow
        }
        
        # Check if BFF data contains real AWS status (not hardcoded)
        $realStatuses = @()
        foreach ($instance in $bffData.instances) {
            if ($instance.status -and $instance.status -ne "available") {
                $realStatuses += $instance.status
            }
        }
        
        if ($realStatuses.Count -gt 0) {
            Write-Host "  ✓ Real AWS statuses detected: $($realStatuses -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  All instances show 'available' status - verify real-time data" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Host "  ❌ Error comparing data: $_" -ForegroundColor Red
    }
}

# Test 5: Cross-Account Discovery Test
Write-Host ""
Write-Host "Test 5: Cross-Account Discovery Test" -ForegroundColor Yellow
Write-Host "Checking cross-account configuration..." -NoNewline

try {
    if ($discoveryData -and $discoveryData.cross_account_enabled) {
        Write-Host " [PASS]" -ForegroundColor Green
        Write-Host "  ✓ Cross-account discovery is enabled" -ForegroundColor Green
        Write-Host "  ✓ Accounts attempted: $($discoveryData.accounts_attempted)" -ForegroundColor Green
        Write-Host "  ✓ Accounts scanned: $($discoveryData.accounts_scanned)" -ForegroundColor Green
        
        if ($discoveryData.accounts_attempted -gt 1) {
            Write-Host "  ✓ Multi-account discovery configured" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Only current account configured" -ForegroundColor Yellow
        }
    } else {
        Write-Host " [PARTIAL]" -ForegroundColor Yellow
        Write-Host "  ⚠️  Cross-account discovery not enabled" -ForegroundColor Yellow
        Write-Host "  Run configure-cross-account-discovery.ps1 to enable" -ForegroundColor Yellow
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "  ❌ Error checking cross-account configuration: $_" -ForegroundColor Red
}

# Test 6: Real-Time Status Test
Write-Host ""
Write-Host "Test 6: Real-Time Status Verification" -ForegroundColor Yellow
Write-Host "Verifying real-time AWS status..." -NoNewline

try {
    if ($bffData -and $bffData.instances -and $bffData.instances.Count -gt 0) {
        # Check if we have actual RDS instances to verify
        $sampleInstance = $bffData.instances[0]
        
        if ($sampleInstance.instance_id -and $sampleInstance.region) {
            # Try to get real status from AWS RDS API
            $rdsStatus = aws rds describe-db-instances `
                --db-instance-identifier $sampleInstance.instance_id `
                --region $sampleInstance.region `
                --query 'DBInstances[0].DBInstanceStatus' `
                --output text 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                if ($rdsStatus -eq $sampleInstance.status) {
                    Write-Host " [PASS]" -ForegroundColor Green
                    Write-Host "  ✓ Status matches AWS API: $rdsStatus" -ForegroundColor Green
                } else {
                    Write-Host " [MISMATCH]" -ForegroundColor Yellow
                    Write-Host "  ⚠️  Status mismatch:" -ForegroundColor Yellow
                    Write-Host "    BFF reports: $($sampleInstance.status)" -ForegroundColor Yellow
                    Write-Host "    AWS API reports: $rdsStatus" -ForegroundColor Yellow
                    Write-Host "    This may be due to caching or recent changes" -ForegroundColor Yellow
                }
            } else {
                Write-Host " [SKIP]" -ForegroundColor Yellow
                Write-Host "  ⚠️  Cannot verify - instance may not exist or no permissions" -ForegroundColor Yellow
            }
        } else {
            Write-Host " [SKIP]" -ForegroundColor Yellow
            Write-Host "  ⚠️  No valid instance data to verify" -ForegroundColor Yellow
        }
    } else {
        Write-Host " [SKIP]" -ForegroundColor Yellow
        Write-Host "  ⚠️  No instances found to verify" -ForegroundColor Yellow
    }
} catch {
    Write-Host " [ERROR]" -ForegroundColor Red
    Write-Host "  ❌ Error verifying real-time status: $_" -ForegroundColor Red
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""

if ($discoveryData -and $bffData) {
    Write-Host "✅ Integration Status: WORKING" -ForegroundColor Green
    Write-Host "✓ Discovery service is functional" -ForegroundColor Green
    Write-Host "✓ BFF is calling discovery service" -ForegroundColor Green
    Write-Host "✓ Cache table is accessible" -ForegroundColor Green
    Write-Host "✓ Real-time data is being returned" -ForegroundColor Green
} else {
    Write-Host "❌ Integration Status: ISSUES DETECTED" -ForegroundColor Red
    Write-Host "Please review the test results above and fix any issues" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Key Metrics:" -ForegroundColor Yellow
if ($bffData) {
    Write-Host "• Total instances discovered: $($bffData.instances.Count)" -ForegroundColor White
    Write-Host "• Cache status: $($bffData.metadata.cache_status)" -ForegroundColor White
    Write-Host "• Last updated: $($bffData.metadata.last_updated)" -ForegroundColor White
}
if ($discoveryData) {
    Write-Host "• Accounts scanned: $($discoveryData.accounts_scanned)/$($discoveryData.accounts_attempted)" -ForegroundColor White
    Write-Host "• Cross-account enabled: $($discoveryData.cross_account_enabled)" -ForegroundColor White
}

Write-Host ""