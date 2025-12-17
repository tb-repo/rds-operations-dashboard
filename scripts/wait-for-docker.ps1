# Wait for Docker Desktop to be ready
# This script checks if Docker is running and waits until it's ready

param(
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 120
)

Write-Host "Waiting for Docker Desktop to start..." -ForegroundColor Yellow
Write-Host ""

$elapsed = 0
$interval = 5

while ($elapsed -lt $TimeoutSeconds) {
    try {
        $result = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Docker Desktop is ready!" -ForegroundColor Green
            Write-Host ""
            docker --version
            Write-Host ""
            return 0
        }
    }
    catch {
        # Docker not ready yet
    }
    
    Write-Host "⏳ Waiting for Docker... ($elapsed/$TimeoutSeconds seconds)" -ForegroundColor Yellow
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

Write-Host "❌ Docker Desktop did not start within $TimeoutSeconds seconds" -ForegroundColor Red
Write-Host "Please check Docker Desktop manually" -ForegroundColor Yellow
exit 1
