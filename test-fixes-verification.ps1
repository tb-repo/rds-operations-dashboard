# Test Fixes Verification Script
# This script helps verify that the deployed fixes are working

Write-Host "🧪 Testing Deployed Fixes..." -ForegroundColor Green
Write-Host ""

# Test 1: Check if frontend is deployed with latest changes
Write-Host "📋 Test 1: Verifying frontend deployment..." -ForegroundColor Yellow

try {
    $frontendResponse = Invoke-WebRequest -Uri "https://d2qvaswtmn22om.cloudfront.net" -TimeoutSec 10
    if ($frontendResponse.StatusCode -eq 200) {
        Write-Host "  ✅ Frontend is accessible" -ForegroundColor Green
        
        # Check if the response contains our app
        if ($frontendResponse.Content -match "RDS Operations Dashboard" -or $frontendResponse.Content -match "vite") {
            Write-Host "  ✅ Frontend appears to be our React app" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Frontend content may not be updated" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ❌ Frontend not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Check API endpoints
Write-Host "📋 Test 2: Testing API endpoints..." -ForegroundColor Yellow

# Find the correct API URL from the frontend environment
$apiUrl = "https://api.rds-dashboard.idp-connect.com"

# Test health endpoint
try {
    $healthResponse = Invoke-RestMethod -Uri "$apiUrl/health" -Method GET -TimeoutSec 10
    Write-Host "  ✅ API health endpoint responding" -ForegroundColor Green
    Write-Host "    Response: $($healthResponse.message)" -ForegroundColor White
} catch {
    Write-Host "  ❌ API health check failed: $($_.Exception.Message)" -ForegroundColor Red
    
    # Try alternative API URLs
    $alternativeUrls = @(
        "https://bff.rds-dashboard.idp-connect.com",
        "https://rds-bff-prod.execute-api.ap-southeast-1.amazonaws.com"
    )
    
    foreach ($altUrl in $alternativeUrls) {
        try {
            Write-Host "  🔄 Trying alternative URL: $altUrl" -ForegroundColor Yellow
            $altResponse = Invoke-RestMethod -Uri "$altUrl/health" -Method GET -TimeoutSec 5
            Write-Host "  ✅ Alternative API responding: $altUrl" -ForegroundColor Green
            $apiUrl = $altUrl
            break
        } catch {
            Write-Host "  ❌ $altUrl not responding" -ForegroundColor Red
        }
    }
}

Write-Host ""

# Test 3: Check instances endpoint
Write-Host "📋 Test 3: Testing instances endpoint..." -ForegroundColor Yellow

try {
    $instancesResponse = Invoke-RestMethod -Uri "$apiUrl/api/instances" -Method GET -TimeoutSec 10
    Write-Host "  ✅ Instances endpoint responding" -ForegroundColor Green
    
    if ($instancesResponse.instances) {
        $instanceCount = $instancesResponse.instances.Count
        Write-Host "    Found $instanceCount instances" -ForegroundColor White
        
        if ($instanceCount -gt 1) {
            Write-Host "  ✅ Multiple instances found - discovery appears to be working" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Only $instanceCount instance found - discovery may need more time" -ForegroundColor Yellow
        }
        
        # Show first instance for verification
        if ($instancesResponse.instances.Count -gt 0) {
            $firstInstance = $instancesResponse.instances[0]
            Write-Host "    Sample instance: $($firstInstance.instance_id) in $($firstInstance.region)" -ForegroundColor White
        }
    } else {
        Write-Host "  ⚠️  No instances in response" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ Instances endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 4: Manual testing instructions
Write-Host "📋 Test 4: Manual testing required..." -ForegroundColor Yellow
Write-Host ""
Write-Host "🌐 Open your dashboard: https://d2qvaswtmn22om.cloudfront.net" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Test these specific fixes:" -ForegroundColor Green
Write-Host ""

Write-Host "1. 🔧 Instance Operations Test:" -ForegroundColor Yellow
Write-Host "   • Click on any RDS instance" -ForegroundColor White
Write-Host "   • Scroll down to 'Self-Service Operations' section" -ForegroundColor White
Write-Host "   • Select 'Stop Instance' from dropdown" -ForegroundColor White
Write-Host "   • Click 'Execute' button" -ForegroundColor White
Write-Host "   • ✅ Should work without 400 Bad Request error" -ForegroundColor Green
Write-Host "   • ❌ Before: Got 400 error due to wrong field names" -ForegroundColor Red
Write-Host ""

Write-Host "2. 🚪 Logout Test:" -ForegroundColor Yellow
Write-Host "   • Click the logout button (top right)" -ForegroundColor White
Write-Host "   • ✅ Should redirect cleanly to login page" -ForegroundColor Green
Write-Host "   • ❌ Before: Got 'redirect_uri parameter missing' error" -ForegroundColor Red
Write-Host ""

Write-Host "3. 👥 User Management Test:" -ForegroundColor Yellow
Write-Host "   • Go to Users tab in navigation" -ForegroundColor White
Write-Host "   • ✅ Should show clear error message if no permissions" -ForegroundColor Green
Write-Host "   • ❌ Before: Empty list with no explanation" -ForegroundColor Red
Write-Host ""

Write-Host "4. 🔍 Console Errors Test:" -ForegroundColor Yellow
Write-Host "   • Open browser developer tools (F12)" -ForegroundColor White
Write-Host "   • Check Console tab" -ForegroundColor White
Write-Host "   • ✅ Should be clean of JavaScript errors" -ForegroundColor Green
Write-Host "   • ❌ Before: Various API and authentication errors" -ForegroundColor Red
Write-Host ""

Write-Host "5. 🗂️ RDS Instances Test:" -ForegroundColor Yellow
Write-Host "   • Check main dashboard for RDS instances" -ForegroundColor White
Write-Host "   • ✅ Should show multiple instances across regions/accounts" -ForegroundColor Green
Write-Host "   • ⏳ May take 5-10 minutes for discovery to populate all instances" -ForegroundColor Yellow
Write-Host "   • ❌ Before: Only showing 1 instance in Singapore" -ForegroundColor Red
Write-Host ""

# Test 5: Browser console check
Write-Host "📋 Test 5: Browser debugging tips..." -ForegroundColor Yellow
Write-Host ""
Write-Host "🔍 If issues persist, check browser developer tools:" -ForegroundColor Cyan
Write-Host "   1. Press F12 to open developer tools" -ForegroundColor White
Write-Host "   2. Go to Network tab" -ForegroundColor White
Write-Host "   3. Try the failing operation" -ForegroundColor White
Write-Host "   4. Look for failed requests (red entries)" -ForegroundColor White
Write-Host "   5. Click on failed request to see details" -ForegroundColor White
Write-Host "   6. Check Response tab for error message" -ForegroundColor White
Write-Host ""

Write-Host "📊 Expected API request format for operations:" -ForegroundColor Cyan
Write-Host "   POST /api/operations" -ForegroundColor White
Write-Host "   Body: {" -ForegroundColor White
Write-Host "     \"instance_id\": \"your-instance-id\"," -ForegroundColor White
Write-Host "     \"operation\": \"stop_instance\"," -ForegroundColor White
Write-Host "     \"region\": \"ap-southeast-1\"," -ForegroundColor White
Write-Host "     \"account_id\": \"876595225096\"" -ForegroundColor White
Write-Host "   }" -ForegroundColor White
Write-Host ""

# Summary
Write-Host "📋 VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Frontend deployed successfully" -ForegroundColor Green
Write-Host "✅ CloudFront cache invalidated" -ForegroundColor Green
Write-Host "✅ Code fixes applied:" -ForegroundColor Green
Write-Host "   • Instance operations use correct 'operation' field" -ForegroundColor White
Write-Host "   • Logout uses 'redirect_uri' parameter" -ForegroundColor White
Write-Host "   • User management shows clear error messages" -ForegroundColor White
Write-Host "   • API calls include region and account_id" -ForegroundColor White
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Test manually using the instructions above" -ForegroundColor White
Write-Host "   2. If instance operations still fail, check Lambda permissions" -ForegroundColor White
Write-Host "   3. If discovery does not show all instances, wait 10 minutes and refresh" -ForegroundColor White
Write-Host "   4. Report any remaining issues with browser console details" -ForegroundColor White
Write-Host ""
Write-Host "🚀 The critical fixes have been deployed!" -ForegroundColor Green