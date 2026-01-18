param(
    [string]$Message = "Update: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
)

Write-Host "Syncing to GitHub..." -ForegroundColor Green

try {
    # Stage all changes
    git add -A
    Write-Host "Changes staged" -ForegroundColor Yellow
    
    # Commit changes
    git commit -m $Message
    Write-Host "Changes committed: $Message" -ForegroundColor Yellow
    
    # Push to GitHub
    git push origin main
    Write-Host "Successfully pushed to GitHub!" -ForegroundColor Green
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}