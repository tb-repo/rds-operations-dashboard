#!/usr/bin/env pwsh
<#
.SYNOPSIS
Simple fix for DNS resolution errors in API Gateway endpoints

.DESCRIPTION
Updates the frontend configuration to use working API Gateway endpoints
#>

Write-Host "🔍 Fixing API Gateway DNS Resolution Issues..." -ForegroundColor Cyan

# Get current region
$region = "ap-southeast-1"

Write-Host "`n📋 Current frontend configuration:" -ForegroundColor Yellow
$envFile = "frontend/.env"
if (Test-Path $envFile) {
    $content = Get-Content $envFile
    $bffLine = $content | Where-Object { $_ -match "VITE_BFF_API_URL=" }
    Write-Host "  $bffLine" -ForegroundColor Red
} else {
    Write-Host "❌ Frontend .env file not found!" -ForegroundColor Red
    exit 1
}

Write-Host "`n🔍 Available API Gateway endpoints:" -ForegroundColor Yellow

# Test the known working endpoints
$workingEndpoints = @(
    "0pjyr8lkpl",  # From our earlier discovery
    "qxx9whmsd4"   # From our earlier discovery
)

$bestEndpoint = $null
foreach ($endpoint in $workingEndpoints) {
    $testUrl = "https://$endpoint.execute-api.$region.amazonaws.com/prod/api/health"
    Write-Host "Testing: $testUrl" -ForegroundColor White
    
    try {
        $response = Invoke-WebRequest -Uri $testUrl -Method GET -TimeoutSec 10 -ErrorAction Stop
        Write-Host "  ✅ Status: $($response.StatusCode) - Working" -ForegroundColor Green
        $bestEndpoint = $endpoint
        break
    } catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -eq 403) {
                Write-Host "  ⚠️  Status: 403 Forbidden - API exists but requires auth (this is good!)" -ForegroundColor Yellow
                $bestEndpoint = $endpoint
                break
            } elseif ($statusCode -eq 401) {
                Write-Host "  ⚠️  Status: 401 Unauthorized - API exists but requires auth" -ForegroundColor Yellow
                $bestEndpoint = $endpoint
                break
            }
        }
        Write-Host "  ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $bestEndpoint) {
    Write-Host "❌ No working API Gateway endpoints found!" -ForegroundColor Red
    exit 1
}

Write-Host "`n🔧 Updating frontend configuration..." -ForegroundColor Yellow

# Create backup
$backupFile = "frontend/.env.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $envFile $backupFile
Write-Host "✅ Created backup: $backupFile" -ForegroundColor Green

# Read current content
$currentContent = Get-Content $envFile -Raw

# Update BFF URL
$newBffUrl = "https://$bestEndpoint.execute-api.$region.amazonaws.com"
$updatedContent = $currentContent -replace "VITE_BFF_API_URL=.*", "VITE_BFF_API_URL=$newBffUrl"

# Also update the commented direct API URL for reference
$newDirectUrl = "https://$bestEndpoint.execute-api.$region.amazonaws.com"
$updatedContent = $updatedContent -replace "# VITE_API_BASE_URL=.*", "# VITE_API_BASE_URL=$newDirectUrl"

# Write updated content
Set-Content -Path $envFile -Value $updatedContent -Encoding UTF8

Write-Host "✅ Updated BFF API URL to: $newBffUrl" -ForegroundColor Green
Write-Host "✅ Updated Direct API URL to: $newDirectUrl" -ForegroundColor Green

Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "1. If running frontend locally, restart the development server" -ForegroundColor White
Write-Host "2. Clear browser cache and refresh the dashboard" -ForegroundColor White
Write-Host "3. Check browser developer tools - DNS errors should be resolved" -ForegroundColor White

Write-Host "`n✅ DNS error fix completed!" -ForegroundColor Green
Write-Host "💡 If issues persist, restore the backup file created above" -ForegroundColor Cyan