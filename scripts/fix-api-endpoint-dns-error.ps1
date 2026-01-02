#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fix DNS resolution errors for API Gateway endpoints

.DESCRIPTION
This script identifies the correct API Gateway endpoints and updates the frontend configuration
to use the working endpoints instead of the non-existent ones causing DNS errors.

.EXAMPLE
./fix-api-endpoint-dns-error.ps1
#>

param(
    [switch]$DryRun = $false
)

Write-Host "🔍 Diagnosing API Gateway DNS Resolution Issues..." -ForegroundColor Cyan

# Get current region
$region = "ap-southeast-1"

Write-Host "`n📋 Step 1: Checking current frontend configuration..." -ForegroundColor Yellow

# Read current frontend config
$envFile = "frontend/.env"
if (Test-Path $envFile) {
    $currentConfig = Get-Content $envFile -Raw
    Write-Host "Current BFF API URL:" -ForegroundColor White
    $currentBffUrl = ($currentConfig | Select-String "VITE_BFF_API_URL=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
    Write-Host "  $currentBffUrl" -ForegroundColor Red
    
    $currentApiUrl = ($currentConfig | Select-String "# VITE_API_BASE_URL=(.+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
    Write-Host "Current Direct API URL (commented):" -ForegroundColor White
    Write-Host "  $currentApiUrl" -ForegroundColor Yellow
} else {
    Write-Host "❌ Frontend .env file not found!" -ForegroundColor Red
    exit 1
}

Write-Host "`n🔍 Step 2: Discovering available API Gateway endpoints..." -ForegroundColor Yellow

# Get all API Gateway REST APIs
try {
    $apis = aws apigateway get-rest-apis --region $region --query "items[?contains(name, ``'RDS``) || contains(name, ``'Dashboard``)].{Name:name,Id:id,CreatedDate:createdDate}" --output json | ConvertFrom-Json
    
    if ($apis.Count -eq 0) {
        Write-Host "❌ No RDS Dashboard API Gateways found!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Found $($apis.Count) API Gateway(s):" -ForegroundColor Green
    foreach ($api in $apis) {
        Write-Host "  - Name: $($api.Name)" -ForegroundColor White
        Write-Host "    ID: $($api.Id)" -ForegroundColor Cyan
        Write-Host "    Created: $($api.CreatedDate)" -ForegroundColor Gray
        Write-Host "    URL: https://$($api.Id).execute-api.$region.amazonaws.com" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Failed to get API Gateway list: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n🧪 Step 3: Testing API Gateway endpoints..." -ForegroundColor Yellow

$workingApis = @()
foreach ($api in $apis) {
    $testUrl = "https://$($api.Id).execute-api.$region.amazonaws.com/prod/api/health"
    Write-Host "Testing: $testUrl" -ForegroundColor White
    
    try {
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  ✅ Status: $($response.StatusCode) - Working" -ForegroundColor Green
        $workingApis += @{
            Id = $api.Id
            Name = $api.Name
            Status = $response.StatusCode
            Type = "Working"
        }
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        if ($statusCode -eq 403) {
            Write-Host "  ⚠️  Status: 403 Forbidden - API exists but requires auth (likely BFF)" -ForegroundColor Yellow
            $workingApis += @{
                Id = $api.Id
                Name = $api.Name
                Status = 403
                Type = "BFF"
            }
        } elseif ($statusCode -eq 401) {
            Write-Host "  ⚠️  Status: 401 Unauthorized - API exists but requires auth" -ForegroundColor Yellow
            $workingApis += @{
                Id = $api.Id
                Name = $api.Name
                Status = 401
                Type = "Direct API"
            }
        } else {
            Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if ($workingApis.Count -eq 0) {
    Write-Host "❌ No working API Gateway endpoints found!" -ForegroundColor Red
    exit 1
}

Write-Host "`n📊 Step 4: Analyzing results..." -ForegroundColor Yellow

# Sort APIs by creation date (newer first) and prefer BFF over Direct API
$sortedApis = $apis | Sort-Object CreatedDate -Descending
$bffApi = $workingApis | Where-Object { $_.Type -eq "BFF" } | Select-Object -First 1
$directApi = $workingApis | Where-Object { $_.Type -eq "Direct API" -or $_.Type -eq "Working" } | Select-Object -First 1

# If no BFF found, use the newest API as BFF
if (-not $bffApi -and $workingApis.Count -gt 0) {
    $newestApi = $sortedApis[0]
    $bffApi = $workingApis | Where-Object { $_.Id -eq $newestApi.Id } | Select-Object -First 1
    if ($bffApi) {
        $bffApi.Type = "BFF (assumed)"
    }
}

# If no direct API found, use the second newest or same as BFF
if (-not $directApi -and $workingApis.Count -gt 0) {
    if ($sortedApis.Count -gt 1) {
        $secondApi = $sortedApis[1]
        $directApi = $workingApis | Where-Object { $_.Id -eq $secondApi.Id } | Select-Object -First 1
    } else {
        $directApi = $bffApi
    }
    if ($directApi) {
        $directApi.Type = "Direct API (assumed)"
    }
}

Write-Host "Recommended configuration:" -ForegroundColor Green
if ($bffApi) {
    Write-Host "  BFF API: https://$($bffApi.Id).execute-api.$region.amazonaws.com ($($bffApi.Type))" -ForegroundColor Cyan
}
if ($directApi) {
    Write-Host "  Direct API: https://$($directApi.Id).execute-api.$region.amazonaws.com ($($directApi.Type))" -ForegroundColor Cyan
}

Write-Host "`n🔧 Step 5: Updating frontend configuration..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "DRY RUN - Would update frontend/.env with:" -ForegroundColor Yellow
    if ($bffApi) {
        Write-Host "  VITE_BFF_API_URL=https://$($bffApi.Id).execute-api.$region.amazonaws.com" -ForegroundColor Cyan
    }
    if ($directApi) {
        Write-Host "  # VITE_API_BASE_URL=https://$($directApi.Id).execute-api.$region.amazonaws.com" -ForegroundColor Cyan
    }
} else {
    # Create backup
    $backupFile = "frontend/.env.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $envFile $backupFile
    Write-Host "✅ Created backup: $backupFile" -ForegroundColor Green
    
    # Update the configuration
    $newConfig = $currentConfig
    
    if ($bffApi) {
        $newBffUrl = "https://$($bffApi.Id).execute-api.$region.amazonaws.com"
        $newConfig = $newConfig -replace "VITE_BFF_API_URL=.*", "VITE_BFF_API_URL=$newBffUrl"
        Write-Host "✅ Updated BFF API URL to: $newBffUrl" -ForegroundColor Green
    }
    
    if ($directApi) {
        $newDirectUrl = "https://$($directApi.Id).execute-api.$region.amazonaws.com"
        $newConfig = $newConfig -replace "# VITE_API_BASE_URL=.*", "# VITE_API_BASE_URL=$newDirectUrl"
        Write-Host "✅ Updated Direct API URL to: $newDirectUrl" -ForegroundColor Green
    }
    
    # Write the updated configuration
    Set-Content -Path $envFile -Value $newConfig -Encoding UTF8
    Write-Host "✅ Updated frontend/.env configuration" -ForegroundColor Green
}

Write-Host "`n🧪 Step 6: Testing updated configuration..." -ForegroundColor Yellow

if (-not $DryRun -and $bffApi) {
    $testUrl = "https://$($bffApi.Id).execute-api.$region.amazonaws.com/prod/api/health"
    Write-Host "Testing updated BFF endpoint: $testUrl" -ForegroundColor White
    
    try {
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "✅ BFF endpoint test successful: $($response.StatusCode)" -ForegroundColor Green
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        if ($statusCode -eq 403 -or $statusCode -eq 401) {
            Write-Host "⚠️  BFF endpoint requires authentication (expected): $statusCode" -ForegroundColor Yellow
        } else {
            Write-Host "❌ BFF endpoint test failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "1. If you're running the frontend locally, restart the development server" -ForegroundColor White
Write-Host "2. If deployed, redeploy the frontend with the updated configuration" -ForegroundColor White
Write-Host "3. Clear browser cache and refresh the dashboard" -ForegroundColor White
Write-Host "4. Check browser developer tools for any remaining network errors" -ForegroundColor White

Write-Host "`n✅ API endpoint DNS error fix completed!" -ForegroundColor Green

if (-not $DryRun) {
    Write-Host "`n💡 If issues persist, you can restore the backup:" -ForegroundColor Cyan
    Write-Host "   Copy-Item `"$backupFile`" `"frontend/.env`"" -ForegroundColor Gray
}