#!/bin/bash
# Add AWS_ACCOUNT_ID to all Lambda functions in CDK

set -e

CDK_FILE="infrastructure/lib/compute-stack.ts"

echo "🔧 Adding AWS_ACCOUNT_ID to Lambda environment variables in CDK..."

# Backup original file
cp $CDK_FILE ${CDK_FILE}.backup

# Add AWS_ACCOUNT_ID as first environment variable in each Lambda
# This uses sed to insert the line after "environment: {"
sed -i.tmp '/environment: {/a\
        AWS_ACCOUNT_ID: cdk.Stack.of(this).account,  // Auto-detect account ID
' $CDK_FILE

# Remove temp file
rm ${CDK_FILE}.tmp 2>/dev/null || true

echo "✅ Updated $CDK_FILE"
echo "📝 Backup saved to ${CDK_FILE}.backup"
echo ""
echo "Next steps:"
echo "1. Review the changes: git diff $CDK_FILE"
echo "2. Deploy: cd infrastructure && cdk deploy --all"
