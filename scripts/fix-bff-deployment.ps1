#!/usr/bin/env pwsh
# Fix BFF deployment issue

Write-Host "=== FIXING BFF DEPLOYMENT ISSUE ===" -ForegroundColor Yellow
Write-Host ""

# Configuration
$region = "ap-southeast-1"
$stackName = "RDSDashboard-BFF"

Write-Host "1. Checking current BFF stack status..." -ForegroundColor Cyan
try {
    $stackStatus = aws cloudformation describe-stacks --stack-name $stackName --region $region --query 'Stacks[0].StackStatus' --output text 2>$null
    
    if ($stackStatus) {
        Write-Host "   Current stack status: $stackStatus" -ForegroundColor Gray
        
        if ($stackStatus -eq "UPDATE_ROLLBACK_COMPLETE" -or $stackStatus -eq "CREATE_FAILED" -or $stackStatus -eq "ROLLBACK_COMPLETE") {
            Write-Host "   Stack is in a failed state - needs to be deleted and recreated" -ForegroundColor Yellow
            
            Write-Host "2. Deleting failed BFF stack..." -ForegroundColor Cyan
            Set-Location infrastructure
            npx aws-cdk destroy $stackName --force
            Set-Location ..
            
            Write-Host "   Waiting for stack deletion to complete..." -ForegroundColor Gray
            do {
                Start-Sleep -Seconds 15
                $stackStatus = aws cloudformation describe-stacks --stack-name $stackName --region $region --query 'Stacks[0].StackStatus' --output text 2>$null
                if ($stackStatus) {
                    Write-Host "     Stack status: $stackStatus" -ForegroundColor Gray
                }
            } while ($stackStatus -and $stackStatus -ne "DELETE_COMPLETE")
            
            Write-Host "   ✅ Stack deleted successfully" -ForegroundColor Green
        }
    } else {
        Write-Host "   No existing BFF stack found" -ForegroundColor Gray
    }
} catch {
    Write-Host "   No existing BFF stack found or error checking: $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "3. Deploying new BFF stack..." -ForegroundColor Cyan
try {
    Set-Location infrastructure
    npx aws-cdk deploy $stackName --require-approval never
    Set-Location ..
    
    Write-Host "   ✅ BFF stack deployed successfully" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Failed to deploy BFF stack: $($_.Exception.Message)" -ForegroundColor Red
    Set-Location ..
    exit 1
}

Write-Host ""
Write-Host "4. Getting new BFF URL..." -ForegroundColor Cyan
try {
    $bffUrl = aws cloudformation describe-stacks --stack-name $stackName --region $region --query 'Stacks[0].Outputs[?OutputKey==`BffApiUrl`].OutputValue' --output text
    
    if ($bffUrl) {
        Write-Host "   New BFF URL: $bffUrl" -ForegroundColor Green
        
        # Update frontend .env file
        Write-Host "5. Updating frontend .env file..." -ForegroundColor Cyan
        $envContent = Get-Content "frontend/.env" -Raw
        $envContent = $envContent -replace "VITE_BFF_API_URL=.*", "VITE_BFF_API_URL=$bffUrl"
        Set-Content "frontend/.env" $envContent
        
        Write-Host "   ✅ Frontend .env updated with new BFF URL" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  Could not retrieve BFF URL from stack outputs" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ❌ Failed to get BFF URL: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "6. Testing new BFF deployment..." -ForegroundColor Cyan
if ($bffUrl) {
    Start-Sleep -Seconds 10  # Wait for deployment to settle
    
    try {
        $response = Invoke-RestMethod -Uri "$bffUrl/api/health" -Method GET -TimeoutSec 15
        Write-Host "   ✅ BFF health check successful" -ForegroundColor Green
        Write-Host "   Response: $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
        
        # Test if it's properly routing (not just returning generic messages)
        if ($response.status -eq "healthy") {
            Write-Host "   ✅ BFF appears to be properly deployed" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  BFF may still be in fallback mode" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ❌ BFF health check failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Test operations endpoint (should require auth)
    try {
        $body = @{
            instance_id = "test"
            operation = "stop"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$bffUrl/api/operations" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
        Write-Host "   ⚠️  Operations endpoint responded without auth (unexpected)" -ForegroundColor Yellow
    } catch {
        if ($_.Exception.Response.StatusCode -eq 401) {
            Write-Host "   ✅ Operations endpoint requires authentication (expected)" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  Operations endpoint error: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "   ⚠️  Cannot test BFF - URL not available" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== BFF DEPLOYMENT FIX COMPLETE ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Test the dashboard in browser" -ForegroundColor White
Write-Host "2. Try logging in and performing operations" -ForegroundColor White
Write-Host "3. Check if all 5 critical issues are resolved" -ForegroundColor White