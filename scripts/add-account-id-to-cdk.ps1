# Add AWS_ACCOUNT_ID to all Lambda functions in CDK
Write-Host "🔧 Adding AWS_ACCOUNT_ID to Lambda environment variables in CDK..." -ForegroundColor Cyan

$cdkFile = "infrastructure\lib\compute-stack.ts"

# Backup original file
Copy-Item $cdkFile "$cdkFile.backup"

# Read the file
$content = Get-Content $cdkFile -Raw

# Add AWS_ACCOUNT_ID as first environment variable
# Replace "environment: {" with "environment: {\n        AWS_ACCOUNT_ID: cdk.Stack.of(this).account,"
$newContent = $content -replace '(environment: \{)', "`$1`n        AWS_ACCOUNT_ID: cdk.Stack.of(this).account,  // Auto-detect account ID"

# Write back
$newContent | Set-Content $cdkFile

Write-Host "✅ Updated $cdkFile" -ForegroundColor Green
Write-Host "📝 Backup saved to $cdkFile.backup" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review the changes: git diff $cdkFile"
Write-Host "2. Deploy: cd infrastructure; cdk deploy --all"
