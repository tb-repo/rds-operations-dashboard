# Test Health Endpoint
Write-Host "Testing health endpoint..." -ForegroundColor Cyan

# Wait for Lambda update to complete
Write-Host "Waiting for Lambda update to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Get the instance ID from inventory
$inventory = aws dynamodb scan --table-name rds-inventory --output json | ConvertFrom-Json
$instanceId = $inventory.Items[0].instance_id.S

Write-Host "Instance ID: $instanceId" -ForegroundColor Green

# Test the BFF health endpoint
$bffUrl = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod"
$healthUrl = "$bffUrl/api/health/$instanceId"

Write-Host "`nTesting: $healthUrl" -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri $healthUrl -Method GET -UseBasicParsing
    Write-Host "`nSuccess! Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor Cyan
    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response Body: $responseBody" -ForegroundColor Yellow
    }
}
