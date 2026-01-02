# Test Internal API Endpoints
# Test the monitoring dashboard endpoints directly

$ApiUrl = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
$ApiKey = "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX"

Write-Host "Testing Internal API Endpoints" -ForegroundColor Green
Write-Host "API URL: $ApiUrl" -ForegroundColor Cyan

# Test endpoints
$endpoints = @(
    "/monitoring-dashboard/metrics",
    "/monitoring-dashboard/health", 
    "/error-resolution/statistics"
)

foreach ($endpoint in $endpoints) {
    Write-Host ""
    Write-Host "Testing: $endpoint" -ForegroundColor Yellow
    
    try {
        $headers = @{
            "x-api-key" = $ApiKey
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri "$ApiUrl$endpoint" -Method GET -Headers $headers -ErrorAction Stop
        
        Write-Host "✅ SUCCESS: $endpoint" -ForegroundColor Green
        Write-Host "Response keys: $($response.PSObject.Properties.Name -join ', ')" -ForegroundColor White
        
        # Show some sample data
        if ($response.widgets) {
            Write-Host "Widgets: $($response.widgets.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        }
        if ($response.statistics) {
            Write-Host "Statistics keys: $($response.statistics.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "❌ FAILED: $endpoint (Status: $statusCode)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Test completed!" -ForegroundColor Green