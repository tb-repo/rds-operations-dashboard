# BFF Build Fix - Complete

## Issue Summary
The BFF Lambda deployment was failing because the Express app was calling `app.listen()` during module import, which caused issues when Lambda tried to import the module.

## Root Cause
In `bff/src/index.ts`, the Express server was starting immediately when the module was loaded:
```typescript
app.listen(port, () => {
  logger.info(`BFF server started`, { ... })
})

export default app
```

This caused problems because:
1. Lambda doesn't need the server to listen on a port
2. The `app.listen()` call happens during import, blocking Lambda initialization
3. The serverless-express wrapper expects just the app, not a running server

## Solution Implemented

### 1. Conditional Server Startup
Modified `bff/src/index.ts` to only start the server when NOT running in Lambda:

```typescript
// Export the app for Lambda or local server
export default app

// Only start server if not running in Lambda
if (process.env.AWS_EXECUTION_ENV === undefined) {
  app.listen(port, () => {
    logger.info(`BFF server started`, { ... })
  })
}
```

### 2. API Key Initialization for Lambda
Added initialization logic to load API keys on Lambda cold start:

```typescript
// Initialize API key on module load for Lambda
async function initializeApiKey() {
  if (!INTERNAL_API_KEY) {
    INTERNAL_API_KEY = await loadApiKeyFromSecretsManager()
    logger.info('API key initialized', { hasKey: !!INTERNAL_API_KEY })
  }
}

// For Lambda: Initialize on cold start
if (process.env.AWS_EXECUTION_ENV) {
  initializeApiKey().catch(error => {
    logger.error('Failed to initialize API key on Lambda cold start', { error: error.message })
  })
}
```

### 3. Lambda Handler
The `bff/src/lambda.ts` file correctly wraps the Express app:

```typescript
import serverlessExpress from '@vendia/serverless-express'
import app from './index'

// Create Lambda handler by wrapping Express app
export const handler = serverlessExpress({ app })
```

## Build Verification

### TypeScript Compilation
```bash
npm run build
```

Output:
- ✅ `dist/index.js` - Express app (conditionally starts server)
- ✅ `dist/lambda.js` - Lambda handler
- ✅ All middleware and routes compiled successfully

### Package Structure
```
dist/
├── config/
├── middleware/
├── routes/
├── security/
├── services/
├── utils/
├── index.js          # Express app
├── index.d.ts        # TypeScript declarations
├── lambda.js         # Lambda handler
└── lambda.d.ts       # TypeScript declarations
```

## Deployment Scripts

### 1. Package for Lambda
```powershell
./package-lambda.ps1
```

Creates `lambda-package.zip` with:
- Compiled JavaScript (`dist/`)
- Production dependencies (`node_modules/`)
- Package metadata (`package.json`)

### 2. Deploy to Lambda
```powershell
./deploy-to-lambda.ps1 -FunctionName "rds-dashboard-bff-production" -Region "ap-southeast-1"
```

Updates the Lambda function with the new code.

## Testing

### Local Testing
```bash
# Start local server (will listen on port 3000)
node dist/index.js
```

### Lambda Testing
```bash
# Test Lambda handler
aws lambda invoke \
  --function-name rds-dashboard-bff-production \
  --payload '{"httpMethod":"GET","path":"/health"}' \
  response.json
```

## Key Benefits

1. **Dual Mode Operation**: Same codebase works for both local development and Lambda
2. **Clean Separation**: Server startup logic separated from app creation
3. **Proper Initialization**: API keys loaded on Lambda cold start
4. **Type Safety**: Full TypeScript support maintained
5. **Easy Deployment**: Simple scripts for packaging and deployment

## Environment Detection

The code uses `process.env.AWS_EXECUTION_ENV` to detect Lambda environment:
- **Undefined**: Running locally → Start Express server
- **Defined**: Running in Lambda → Skip server startup, let serverless-express handle requests

## Next Steps

1. ✅ Build successful
2. ⏳ Package for Lambda deployment
3. ⏳ Deploy to Lambda function
4. ⏳ Test Lambda endpoints
5. ⏳ Verify API Gateway integration

## Files Modified

- `bff/src/index.ts` - Added conditional server startup
- `bff/src/lambda.ts` - Already correct (no changes needed)
- `bff/package-lambda.ps1` - New packaging script
- `bff/deploy-to-lambda.ps1` - New deployment script

## Status

✅ **BUILD FIXED** - TypeScript compilation successful
✅ **LAMBDA HANDLER** - Correctly exports handler
✅ **DEPLOYMENT READY** - Package scripts created

The BFF is now ready for Lambda deployment!
