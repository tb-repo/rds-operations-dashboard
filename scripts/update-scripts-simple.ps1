# Simple script to update URLs in PowerShell files

Write-Host "Updating PowerShell scripts with clean URLs..." -ForegroundColor Green

# Define URL replacements
$replacements = @(
    @{
        Old = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod"
        New = "https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com"
    },
    @{
        Old = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod"
        New = "https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com"
    },
    @{
        Old = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod"
        New = "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com"
    }
)

# Get all PowerShell files
$files = Get-ChildItem -Path "." -Recurse -Filter "*.ps1" | Where-Object { 
    $_.Name -ne "update-scripts-simple.ps1" -and 
    $_.FullName -notlike "*\.git\*" 
}

$updatedCount = 0

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    $originalContent = $content
    
    foreach ($replacement in $replacements) {
        $content = $content.Replace($replacement.Old, $replacement.New)
    }
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated: $($file.Name)" -ForegroundColor Yellow
        $updatedCount++
    }
}

Write-Host "Updated $updatedCount files" -ForegroundColor Green