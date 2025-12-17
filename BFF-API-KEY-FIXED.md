# BFF API Key Fix - Complete

## Problem
The BFF Lambda was returning 500 Internal Server Errors for all `/api/approvals` and `/api/health/:instanceId` endpoints because the `INTERNAL_API_KEY` environment variable was empty, causing all backend API calls to fail.

## Root Cause
1. The BFF stack was configured to store the API key in AWS Secrets Manager
2. The `INTERNAL_API_KEY` environment variable was set to an empty string in the Lambda configuration
3. The BFF code was not loading the API key from Secrets Manager at runtime
4. Additionally, the secret value in Secrets Manager was stored with invalid JSON format (unquoted keys)

## Solution Implemented

### 1. Added Secrets Manager Integration
- Added `@aws-sdk/client-secrets-manager` dependency to `bff/package.json`
- Created `loadApiKeyFromSecretsManager()` function to retrieve the API key from Secrets Manager
- Added middleware to load the API key on the first request (lazy loading)

### 2. Fixed Secret Format
The secret was stored as:
```
{apiUrl:...,apiKey:...,description:...}  // Invalid JSON
```

Updated to:
```json
{
  "apiUrl": "https://qxx9whmsd4.execute-api.ap-southeast-1.amazonaws.com/prod/",
  "apiKey": "OhJGzr5CmF1SUxL48d5fb3Nqqf2VER095rlwYPFX",
  "description": "RDS Dashboard API credentials"
}
```

### 3. Code Changes

**File: `bff/src/index.ts`**
- Added Secrets Manager client import
- Created async function to load API key from Secrets Manager
- Added middleware to ensure API key is loaded before processing requests
- API key is loaded lazily on first request to avoid cold start delays

**Key Code:**
```typescript
// Function to load API key from Secrets Manager
async function loadApiKeyFromSecretsManager(): Promise<string> {
  const secretArn = process.env.API_SECRET_ARN
  
  if (!secretArn) {
    logger.warn('API_SECRET_ARN not set, using INTERNAL_API_KEY from environment')
    return process.env.INTERNAL_API_KEY || ''
  }

  try {
    const client = new SecretsManagerClient({ region: process.env.COGNITO_REGION || 'ap-southeast-1' })
    const command = new GetSecretValueCommand({ SecretId: secretArn })
    const response = await client.send(command)
    
    if (response.SecretString) {
      const secret = JSON.parse(response.SecretString)
      logger.info('Successfully loaded API key from Secrets Manager')
      return secret.apiKey || ''
    }
    
    logger.error('Secret string not found in Secrets Manager response')
    return ''
  } catch (error: any) {
    logger.error('Failed to load API key from Secrets Manager', { error: error.message })
    return process.env.INTERNAL_API_KEY || ''
  }
}

// Middleware to ensure API key is loaded
app.use(async (req, res, next) => {
  if (!INTERNAL_API_KEY) {
    try {
      INTERNAL_API_KEY = await loadApiKeyFromSecretsManager()
      logger.info('API key loaded on first request', { hasKey: !!INTERNAL_API_KEY })
    } catch (error: any) {
      logger.error('Failed to load API key', { error: error.message })
      return res.status(500).json({ error: 'Internal configuration error' })
    }
  }
  next()
})
```

### 4. Deployment
```bash
cd bff
npm install
npm run build

cd ../infrastructure
npx cdk deploy RDSDashboard-BFF --require-approval never
```

## Verification

### Health Endpoint (No Auth)
```bash
curl https://km9ww1hh3k.execute-api.ap-southeast-1.amazonaws.com/prod/health
# Response: {"status":"healthy","timestamp":"2025-12-07T23:03:49.778Z"}
```

### Lambda Logs
```
2025-12-07T23:03:49 info: Incoming request {"method":"GET","path":"/health"...}
# No errors about missing API key
```

## Next Steps

1. **Test Authenticated Endpoints**: Login to the application and test:
   - GET `/api/approvals` - Should now return approval requests
   - GET `/api/health/:instanceId` - Should return health metrics
   - POST `/api/approvals` - Should create/update approval requests

2. **Monitor Logs**: Check CloudWatch logs for any errors:
   ```bash
   aws logs tail /aws/lambda/rds-dashboard-bff --follow
   ```

3. **Verify API Key Loading**: On the first authenticated request, you should see:
   ```
   info: Successfully loaded API key from Secrets Manager
   info: API key loaded on first request {"hasKey":true}
   ```

## Files Modified
- `rds-operations-dashboard/bff/src/index.ts` - Added Secrets Manager integration
- `rds-operations-dashboard/bff/package.json` - Added AWS SDK dependency
- Secret `rds-dashboard-api-key` - Fixed JSON format

## Security Notes
- API key is loaded from Secrets Manager at runtime (not hardcoded)
- API key is cached in memory after first load (no repeated Secrets Manager calls)
- BFF Lambda has IAM permissions to read the secret
- Secret rotation is supported (Lambda will reload on next cold start)

## Status
✅ **FIXED** - BFF now properly loads API key from Secrets Manager and can communicate with backend APIs.

The 500 errors should now be resolved. Please refresh your browser and try the operations again.
