# CORS Issues Diagnostic Script
# Provides detailed diagnostic information and resolution steps for CORS problems
# Requirements: 3.4, 3.5

param(
    [string]$BffUrl = "https://api.rds-dashboard.example.com",
    [string]$FrontendUrl = "https://d2qvaswtmn22om.cloudfront.net",
    [switch]$CheckLambda = $false,
    [switch]$CheckApiGateway = $false,
    [switch]$Verbose = $false
)

Write-Host "=== CORS Issues Diagnostic Tool ===" -ForegroundColor Cyan
Write-Host "BFF URL: $BffUrl" -ForegroundColor Yellow
Write-Host "Frontend URL: $FrontendUrl" -ForegroundColor Yellow
Write-Host ""

$diagnostics = @()

function Add-Diagnostic {
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,
        [string]$Details,
        [string]$Resolution = ""
    )
    
    $global:diagnostics += @{
        Category = $Category
        Check = $Check
        Status = $Status
        Details = $Details
        Resolution = $Resolution
    }
    
    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "White" }
    }
    
    Write-Host "[$Status] $Category - $Check" -ForegroundColor $color
    if ($Details) {
        Write-Host "  Details: $Details" -ForegroundColor Gray
    }
    if ($Resolution -and $Status -ne "PASS") {
        Write-Host "  Resolution: $Resolution" -ForegroundColor Cyan
    }
    Write-Host ""
}

# 1. Basic Connectivity Test
Write-Host "=== 1. Basic Connectivity ===" -ForegroundColor Magenta
try {
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Add-Diagnostic -Category "Connectivity" -Check "BFF Health Endpoint" -Status "PASS" -Details "BFF is accessible (Status: $($response.StatusCode))"
} catch {
    Add-Diagnostic -Category "Connectivity" -Check "BFF Health Endpoint" -Status "FAIL" -Details "Cannot reach BFF: $($_.Exception.Message)" -Resolution "Check BFF deployment status and URL"
}

# 2. CORS Headers Analysis
Write-Host "=== 2. CORS Headers Analysis ===" -ForegroundColor Magenta
try {
    $headers = @{
        "Origin" = $FrontendUrl
        "Access-Control-Request-Method" = "GET"
        "Access-Control-Request-Headers" = "Content-Type,Authorization"
    }
    
    $response = Invoke-WebRequest -Uri "$BffUrl/api/health" -Method OPTIONS -Headers $headers -UseBasicParsing -ErrorAction Stop
    
    $corsOrigin = $response.Headers["Access-Control-Allow-Origin"]
    $corsCredentials = $response.Headers["Access-Control-Allow-Credentials"]
    $corsMethods = $response.Headers["Access-Control-Allow-Methods"]
    $corsHeaders = $response.Headers["Access-Control-Allow-Headers"]
    $corsMaxAge = $response.Headers["Access-Control-Max-Age"]
    
    # Check Access-Control-Allow-Origin
    if ($corsOrigin) {
        if ($corsOrigin -eq $FrontendUrl -or $corsOrigin -eq "*") {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Origin" -Status "PASS" -Details "Correctly set to: $corsOrigin"
        } else {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Origin" -Status "FAIL" -Details "Incorrect origin: $corsOrigin (Expected: $FrontendUrl)" -Resolution "Update CORS_ORIGINS environment variable"
        }
    } else {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Origin" -Status "FAIL" -Details "Missing Access-Control-Allow-Origin header" -Resolution "Configure CORS middleware in BFF"
    }
    
    # Check Access-Control-Allow-Credentials
    if ($corsCredentials -eq "true") {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Credentials" -Status "PASS" -Details "Credentials enabled"
    } else {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Credentials" -Status "WARN" -Details "Credentials not enabled" -Resolution "Enable credentials in CORS configuration if authentication is needed"
    }
    
    # Check Access-Control-Allow-Methods
    if ($corsMethods) {
        $requiredMethods = @("GET", "POST", "PUT", "DELETE", "OPTIONS")
        $allowedMethods = $corsMethods -split ",\s*"
        $missingMethods = $requiredMethods | Where-Object { $_ -notin $allowedMethods }
        
        if ($missingMethods.Count -eq 0) {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Methods" -Status "PASS" -Details "All required methods allowed: $corsMethods"
        } else {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Methods" -Status "WARN" -Details "Missing methods: $($missingMethods -join ', ')" -Resolution "Add missing HTTP methods to CORS configuration"
        }
    } else {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Methods" -Status "FAIL" -Details "Missing Access-Control-Allow-Methods header" -Resolution "Configure allowed methods in CORS middleware"
    }
    
    # Check Access-Control-Allow-Headers
    if ($corsHeaders) {
        $requiredHeaders = @("Content-Type", "Authorization", "X-Api-Key")
        $allowedHeaders = $corsHeaders -split ",\s*"
        $missingHeaders = $requiredHeaders | Where-Object { $_ -notin $allowedHeaders }
        
        if ($missingHeaders.Count -eq 0) {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Headers" -Status "PASS" -Details "All required headers allowed"
        } else {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Headers" -Status "WARN" -Details "Missing headers: $($missingHeaders -join ', ')" -Resolution "Add missing headers to CORS configuration"
        }
    } else {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Allow-Headers" -Status "FAIL" -Details "Missing Access-Control-Allow-Headers header" -Resolution "Configure allowed headers in CORS middleware"
    }
    
    # Check Access-Control-Max-Age
    if ($corsMaxAge) {
        $maxAge = [int]$corsMaxAge
        if ($maxAge -gt 0 -and $maxAge -le 86400) {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Max-Age" -Status "PASS" -Details "Preflight cache set to $maxAge seconds"
        } else {
            Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Max-Age" -Status "WARN" -Details "Unusual max age: $maxAge" -Resolution "Consider setting max age between 300-86400 seconds"
        }
    } else {
        Add-Diagnostic -Category "CORS Headers" -Check "Access-Control-Max-Age" -Status "WARN" -Details "No preflight cache configured" -Resolution "Set Access-Control-Max-Age for better performance"
    }
    
} catch {
    Add-Diagnostic -Category "CORS Headers" -Check "OPTIONS Request" -Status "FAIL" -Details "OPTIONS request failed: $($_.Exception.Message)" -Resolution "Check BFF CORS middleware configuration"
}

# 3. Environment Configuration Check
Write-Host "=== 3. Environment Configuration ===" -ForegroundColor Magenta
if ($CheckLambda) {
    try {
        # This would require AWS CLI and appropriate permissions
        $lambdaConfig = aws lambda get-function-configuration --function-name "rds-dashboard-bff" --query "Environment.Variables" --output json 2>$null | ConvertFrom-Json
        
        if ($lambdaConfig) {
            $corsOrigins = $lambdaConfig.CORS_ORIGINS
            $frontendUrl = $lambdaConfig.FRONTEND_URL
            $nodeEnv = $lambdaConfig.NODE_ENV
            
            if ($corsOrigins) {
                if ($corsOrigins -like "*$FrontendUrl*") {
                    Add-Diagnostic -Category "Environment" -Check "CORS_ORIGINS" -Status "PASS" -Details "Frontend URL found in CORS_ORIGINS"
                } else {
                    Add-Diagnostic -Category "Environment" -Check "CORS_ORIGINS" -Status "FAIL" -Details "Frontend URL not in CORS_ORIGINS: $corsOrigins" -Resolution "Update CORS_ORIGINS to include $FrontendUrl"
                }
            } else {
                Add-Diagnostic -Category "Environment" -Check "CORS_ORIGINS" -Status "WARN" -Details "CORS_ORIGINS not set, using defaults" -Resolution "Set CORS_ORIGINS environment variable"
            }
            
            if ($frontendUrl) {
                if ($frontendUrl -eq $FrontendUrl) {
                    Add-Diagnostic -Category "Environment" -Check "FRONTEND_URL" -Status "PASS" -Details "FRONTEND_URL correctly set"
                } else {
                    Add-Diagnostic -Category "Environment" -Check "FRONTEND_URL" -Status "WARN" -Details "FRONTEND_URL mismatch: $frontendUrl vs $FrontendUrl" -Resolution "Update FRONTEND_URL environment variable"
                }
            } else {
                Add-Diagnostic -Category "Environment" -Check "FRONTEND_URL" -Status "WARN" -Details "FRONTEND_URL not set" -Resolution "Set FRONTEND_URL environment variable"
            }
            
            if ($nodeEnv) {
                Add-Diagnostic -Category "Environment" -Check "NODE_ENV" -Status "PASS" -Details "NODE_ENV set to: $nodeEnv"
            } else {
                Add-Diagnostic -Category "Environment" -Check "NODE_ENV" -Status "WARN" -Details "NODE_ENV not set" -Resolution "Set NODE_ENV to appropriate environment"
            }
        }
    } catch {
        Add-Diagnostic -Category "Environment" -Check "Lambda Configuration" -Status "WARN" -Details "Cannot check Lambda config (AWS CLI required)" -Resolution "Install AWS CLI and configure credentials"
    }
} else {
    Add-Diagnostic -Category "Environment" -Check "Lambda Configuration" -Status "SKIP" -Details "Use -CheckLambda flag to check Lambda environment variables"
}

# 4. Browser Compatibility Test
Write-Host "=== 4. Browser Compatibility ===" -ForegroundColor Magenta
$browserTestHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>CORS Browser Test</title>
</head>
<body>
    <h1>CORS Browser Test</h1>
    <div id="results"></div>
    <script>
        async function testCors() {
            const results = document.getElementById('results');
            const testUrl = '$BffUrl/api/health';
            
            try {
                const response = await fetch(testUrl, {
                    method: 'GET',
                    credentials: 'include',
                    headers: {
                        'Content-Type': 'application/json'
                    }
                });
                
                if (response.ok) {
                    results.innerHTML = '<p style="color: green;">✓ CORS test passed! Status: ' + response.status + '</p>';
                } else {
                    results.innerHTML = '<p style="color: red;">✗ CORS test failed! Status: ' + response.status + '</p>';
                }
            } catch (error) {
                results.innerHTML = '<p style="color: red;">✗ CORS test failed! Error: ' + error.message + '</p>';
            }
        }
        
        testCors();
    </script>
</body>
</html>
"@

$browserTestPath = "cors-browser-test.html"
$browserTestHtml | Out-File -FilePath $browserTestPath -Encoding UTF8
Add-Diagnostic -Category "Browser Test" -Check "Test File Created" -Status "PASS" -Details "Browser test file created: $browserTestPath" -Resolution "Open this file in a browser from $FrontendUrl domain to test CORS"

# 5. Summary and Recommendations
Write-Host "=== Diagnostic Summary ===" -ForegroundColor Cyan
$passCount = ($diagnostics | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($diagnostics | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = ($diagnostics | Where-Object { $_.Status -eq "WARN" }).Count
$totalCount = $diagnostics.Count

Write-Host "Total Checks: $totalCount" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Warnings: $warnCount" -ForegroundColor Yellow
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "=== Critical Issues Requiring Immediate Attention ===" -ForegroundColor Red
    $diagnostics | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "❌ $($_.Category) - $($_.Check)" -ForegroundColor Red
        Write-Host "   Problem: $($_.Details)" -ForegroundColor White
        Write-Host "   Solution: $($_.Resolution)" -ForegroundColor Cyan
        Write-Host ""
    }
}

if ($warnCount -gt 0) {
    Write-Host "=== Recommendations for Improvement ===" -ForegroundColor Yellow
    $diagnostics | Where-Object { $_.Status -eq "WARN" } | ForEach-Object {
        Write-Host "⚠️  $($_.Category) - $($_.Check)" -ForegroundColor Yellow
        Write-Host "   Issue: $($_.Details)" -ForegroundColor White
        Write-Host "   Recommendation: $($_.Resolution)" -ForegroundColor Cyan
        Write-Host ""
    }
}

Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Address all FAIL status issues first" -ForegroundColor White
Write-Host "2. Consider implementing WARN recommendations" -ForegroundColor White
Write-Host "3. Run comprehensive CORS test: .\test-cors-comprehensive.ps1" -ForegroundColor White
Write-Host "4. Test in browser using the generated HTML file" -ForegroundColor White
Write-Host "5. Monitor CloudWatch logs for CORS-related errors" -ForegroundColor White

if ($failCount -eq 0) {
    Write-Host "`n🎉 No critical CORS issues detected!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n❌ Critical CORS issues found. Please address them before proceeding." -ForegroundColor Red
    exit 1
}