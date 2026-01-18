# Package BFF for Lambda deployment
Write-Host "Building BFF Lambda package..." -ForegroundColor Cyan

# Clean previous builds
if (Test-Path "lambda-package.zip") {
    Remove-Item "lambda-package.zip" -Force
}

# Build TypeScript
Write-Host "Compiling TypeScript..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}

# Create a list of files to include
$filesToInclude = @(
    "dist",
    "node_modules",
    "package.json"
)

# Verify all required files exist
$missingFiles = @()
foreach ($file in $filesToInclude) {
    if (-not (Test-Path $file)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Host "ERROR: Missing required files/directories:" -ForegroundColor Red
    $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# Try to find 7-Zip first (best for long paths)
Write-Host "Creating deployment package..." -ForegroundColor Yellow

$7zipPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

$7zipExe = $null
foreach ($path in $7zipPaths) {
    if (Test-Path $path) {
        $7zipExe = $path
        break
    }
}

if ($7zipExe) {
    Write-Host "Using 7-Zip: $7zipExe" -ForegroundColor Cyan
    & $7zipExe a -tzip lambda-package.zip dist node_modules package.json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: 7-Zip failed to create package" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "7-Zip not found, using Python zipfile (if available)..." -ForegroundColor Yellow
    
    # Create a Python script to zip with long path support
    $pythonScript = @"
import zipfile
import os
import sys

def zipdir(path, ziph, base_path=''):
    for root, dirs, files in os.walk(path):
        for file in files:
            file_path = os.path.join(root, file)
            arcname = os.path.relpath(file_path, base_path) if base_path else file_path
            try:
                ziph.write(file_path, arcname)
            except Exception as e:
                print(f'Warning: Could not add {file_path}: {e}', file=sys.stderr)

try:
    with zipfile.ZipFile('lambda-package.zip', 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add dist directory
        if os.path.exists('dist'):
            zipdir('dist', zipf)
        
        # Add node_modules directory
        if os.path.exists('node_modules'):
            zipdir('node_modules', zipf)
        
        # Add package.json
        if os.path.exists('package.json'):
            zipf.write('package.json')
    
    print('Package created successfully')
    sys.exit(0)
except Exception as e:
    print(f'Error creating package: {e}', file=sys.stderr)
    sys.exit(1)
"@
    
    $pythonScript | Out-File -FilePath "create_zip.py" -Encoding UTF8
    
    # Try to run Python script
    try {
        python create_zip.py
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Python zip creation failed" -ForegroundColor Red
            Remove-Item "create_zip.py" -Force -ErrorAction SilentlyContinue
            exit 1
        }
        
        Remove-Item "create_zip.py" -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "ERROR: Python not available" -ForegroundColor Red
        Write-Host "Please install either:" -ForegroundColor Yellow
        Write-Host "  1. 7-Zip from https://www.7-zip.org/" -ForegroundColor Yellow
        Write-Host "  2. Python from https://www.python.org/" -ForegroundColor Yellow
        Remove-Item "create_zip.py" -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# Verify zip was created
if (Test-Path "lambda-package.zip") {
    $size = (Get-Item "lambda-package.zip").Length / 1MB
    Write-Host "Package created: lambda-package.zip ($([math]::Round($size, 2)) MB)" -ForegroundColor Green
    
    # Verify package has content
    if ($size -lt 0.1) {
        Write-Host "WARNING: Package size is suspiciously small ($([math]::Round($size, 2)) MB)" -ForegroundColor Red
        Write-Host "This likely means dependencies were not included properly." -ForegroundColor Red
        Write-Host "Expected size: ~10-50 MB" -ForegroundColor Yellow
        exit 1
    } elseif ($size -gt 50) {
        Write-Host "WARNING: Package size is large ($([math]::Round($size, 2)) MB)" -ForegroundColor Yellow
        Write-Host "Lambda has a 50MB direct upload limit. May need to use S3." -ForegroundColor Yellow
    } else {
        Write-Host "Package size looks good!" -ForegroundColor Green
    }
} else {
    Write-Host "ERROR: Failed to create lambda-package.zip" -ForegroundColor Red
    exit 1
}

Write-Host "Done! Ready to deploy lambda-package.zip" -ForegroundColor Green
