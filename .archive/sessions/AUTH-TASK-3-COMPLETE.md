# Task 3 Complete: BFF Authorization Middleware ✅

## Summary

Successfully implemented complete authorization middleware with permission-based access control and production instance protection.

## What Was Implemented

### 1. Authorization Middleware (`bff/src/middleware/authorization.ts`)
- ✅ **AuthorizationMiddleware class** with comprehensive permission checking
- ✅ **authorize()** middleware function with automatic permission detection
- ✅ **Production instance protection** - blocks operations on production RDS instances
- ✅ **Instance environment verification** via internal API
- ✅ **Multiple authorization modes**: single permission, any permission, all permissions
- ✅ **Detailed error responses** with permission requirements
- ✅ **Comprehensive logging** of all authorization decisions

**Key Features**:
- Automatically determines required permission from endpoint
- Checks user permissions against requirements
- Fetches instance details to verify environment
- Blocks operations on production instances
- Provides clear error messages with required permissions
- Logs all authorization decisions for audit

### 2. Express Application (`bff/src/index.ts`)
- ✅ **Complete Express server** with all middleware integrated
- ✅ **Security headers** via Helmet
- ✅ **CORS configuration** for frontend
- ✅ **Request logging** for all incoming requests
- ✅ **Protected endpoints** for all API routes
- ✅ **User context injection** in operation requests
- ✅ **Error handling** middleware
- ✅ **Health check** endpoint (no auth)

**Protected Endpoints**:
- `GET /api/instances` - view_instances
- `GET /api/instances/:id` - view_instances
- `GET /api/metrics` - view_metrics
- `GET /api/compliance` - view_compliance
- `GET /api/costs` - view_costs
- `POST /api/operations` - execute_operations (+ production check)
- `POST /api/cloudops` - generate_cloudops
- `POST /api/discovery/trigger` - trigger_discovery
- `GET /api/users` - manage_users
- `GET /api/users/me` - authenticated (no specific permission)

### 3. Environment Configuration (`.env.example`)
- ✅ Cognito configuration variables
- ✅ Internal API configuration
- ✅ Frontend URL for CORS
- ✅ Server configuration
- ✅ Logging configuration

## Authorization Flow

```
Request → Authentication Middleware
    ↓
User Context Available (req.user)
    ↓
Authorization Middleware
    ↓
Determine Required Permission
    ├─→ From explicit parameter
    └─→ From endpoint pattern matching
    ↓
Check User Has Permission
    ├─→ Yes: Continue
    └─→ No: Return 403 Forbidden
    ↓
Additional Checks (if execute_operations)
    ├─→ Extract instance_id
    ├─→ Fetch instance details from API
    ├─→ Check environment
    ├─→ If production: Block (403)
    └─→ If non-production: Allow
    ↓
Log Authorization Decision
    ↓
Forward to Internal API
```

## Production Instance Protection

### How It Works

1. **Detect Operations**: When `execute_operations` permission is required
2. **Extract Instance ID**: From body, params, or query
3. **Fetch Instance Details**: Call internal API to get instance info
4. **Check Environment**: Verify if instance is production
5. **Block if Production**: Return 403 with clear message
6. **Allow if Non-Production**: Continue to internal API

### Error Response for Production

```json
{
  "error": "Forbidden",
  "message": "Operations on production instances are not allowed. Use CloudOps to generate a change request instead.",
  "code": "PRODUCTION_PROTECTED",
  "instanceId": "prod-db-01",
  "environment": "production"
}
```

### Fail-Safe Behavior

- If instance details cannot be fetched: **DENY** (fail closed)
- If environment cannot be determined: **DENY** (fail closed)
- Logs all failures for investigation

## Authorization Modes

### 1. Automatic Permission Detection

```typescript
// Permission automatically determined from endpoint
app.get('/api/instances', authorizationMiddleware.authorize())
```

### 2. Explicit Permission

```typescript
// Explicitly require specific permission
app.get('/api/instances', authorizationMiddleware.authorize('view_instances'))
```

### 3. Require Any Permission

```typescript
// User must have at least one of these permissions
app.get('/api/data', 
  authorizationMiddleware.requireAnyPermission([
    'view_instances',
    'view_metrics'
  ])
)
```

### 4. Require All Permissions

```typescript
// User must have all of these permissions
app.post('/api/admin/action',
  authorizationMiddleware.requireAllPermissions([
    'manage_users',
    'execute_operations'
  ])
)
```

## Error Responses

### 401 Unauthorized (Not Authenticated)

```json
{
  "error": "Unauthorized",
  "message": "Authentication required",
  "code": "AUTH_REQUIRED"
}
```

### 403 Forbidden (Insufficient Permissions)

```json
{
  "error": "Forbidden",
  "message": "Insufficient permissions to perform this action",
  "code": "INSUFFICIENT_PERMISSIONS",
  "requiredPermission": "execute_operations",
  "userPermissions": ["view_instances", "view_metrics"]
}
```

### 403 Forbidden (Production Protected)

```json
{
  "error": "Forbidden",
  "message": "Operations on production instances are not allowed",
  "code": "PRODUCTION_PROTECTED",
  "instanceId": "prod-db-01",
  "environment": "production"
}
```

### 500 Internal Server Error

```json
{
  "error": "Internal Server Error",
  "message": "Authorization service error",
  "code": "AUTHZ_SERVICE_ERROR"
}
```

## Logging

### Authorization Granted

```json
{
  "level": "debug",
  "message": "Authorization granted",
  "userId": "user-uuid",
  "email": "user@company.com",
  "permission": "view_instances",
  "path": "/api/instances",
  "method": "GET"
}
```

### Authorization Denied

```json
{
  "level": "warn",
  "message": "Authorization denied: Insufficient permissions",
  "userId": "user-uuid",
  "email": "user@company.com",
  "requiredPermission": "execute_operations",
  "userPermissions": ["view_instances"],
  "path": "/api/operations",
  "method": "POST"
}
```

### Production Instance Blocked

```json
{
  "level": "warn",
  "message": "Authorization denied: Production instance protection",
  "userId": "user-uuid",
  "email": "user@company.com",
  "instanceId": "prod-db-01",
  "operation": "reboot",
  "reason": "Operations on production instances are not allowed"
}
```

## Security Features

### Permission Enforcement
- ✅ All API endpoints protected by default
- ✅ Automatic permission detection from routes
- ✅ Explicit permission override available
- ✅ Multiple permission modes (any/all)

### Production Protection
- ✅ Automatic environment detection
- ✅ Blocks all operations on production instances
- ✅ Fail-closed security (deny if uncertain)
- ✅ Clear error messages guide users to CloudOps

### Audit Trail
- ✅ All authorization decisions logged
- ✅ User context included in logs
- ✅ Permission requirements logged
- ✅ Production blocks logged separately

### Error Handling
- ✅ Graceful degradation on API failures
- ✅ Detailed error codes for client handling
- ✅ Secure error messages (no sensitive data)
- ✅ Comprehensive error logging

## Testing

### Start BFF Server

```bash
cd bff
npm install
npm run dev
```

### Test Authorization

```bash
# Get token from Cognito
TOKEN="eyJraWQiOiJ..."

# Test with permission (should succeed)
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3001/api/instances

# Test without permission (should fail with 403)
# Login as ReadOnly user
curl -H "Authorization: Bearer $READONLY_TOKEN" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"instance_id":"test-db","operation":"reboot"}' \
  http://localhost:3001/api/operations

# Test production protection (should fail with 403)
curl -H "Authorization: Bearer $TOKEN" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"instance_id":"prod-db-01","operation":"reboot"}' \
  http://localhost:3001/api/operations
```

### Expected Responses

**Success (200)**:
```json
{
  "instances": [...]
}
```

**Insufficient Permissions (403)**:
```json
{
  "error": "Forbidden",
  "message": "Insufficient permissions to perform this action",
  "code": "INSUFFICIENT_PERMISSIONS",
  "requiredPermission": "execute_operations",
  "userPermissions": ["view_instances", "view_metrics"]
}
```

**Production Protected (403)**:
```json
{
  "error": "Forbidden",
  "message": "Operations on production instances are not allowed. Use CloudOps to generate a change request instead.",
  "code": "PRODUCTION_PROTECTED",
  "instanceId": "prod-db-01",
  "environment": "production"
}
```

## Integration with Internal API

### Request Forwarding

```typescript
// BFF adds user context to requests
const requestBody = {
  ...req.body,
  requested_by: req.user?.email,
  user_id: req.user?.userId,
}

// Forward to internal API with API key
const response = await axios.post(
  `${INTERNAL_API_URL}/operations`,
  requestBody,
  {
    headers: { 'x-api-key': INTERNAL_API_KEY },
  }
)
```

### Instance Details Fetching

```typescript
// Fetch instance to check environment
const instance = await axios.get(
  `${INTERNAL_API_URL}/instances/${instanceId}`,
  {
    headers: { 'x-api-key': INTERNAL_API_KEY },
    timeout: 5000,
  }
)

// Check environment
if (instance.data.environment === 'production') {
  // Block operation
}
```

## Files Created

```
bff/
├── .env.example                      # Environment variables template
└── src/
    ├── index.ts                      # Express app with all endpoints
    └── middleware/
        └── authorization.ts          # Authorization middleware
```

## Environment Variables

```bash
# Required
COGNITO_USER_POOL_ID=ap-southeast-1_xxxxxxxxx
COGNITO_REGION=ap-southeast-1
INTERNAL_API_URL=https://xxx.execute-api.ap-southeast-1.amazonaws.com/prod
INTERNAL_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxx

# Optional
COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx
FRONTEND_URL=http://localhost:3000
PORT=3001
NODE_ENV=development
LOG_LEVEL=info
```

## Next Steps

Now that authorization middleware is complete, proceed to:

1. **Task 4**: Implement audit logging service
   - Log authentication events
   - Log authorization decisions
   - CloudWatch integration

2. **Task 5**: Implement user management API
   - List users endpoint
   - Add/remove roles endpoints
   - Cognito admin operations

3. **Deploy and Test**:
   ```bash
   # Install dependencies
   cd bff
   npm install
   
   # Set environment variables
   cp .env.example .env
   # Edit .env with actual values
   
   # Run in development
   npm run dev
   
   # Build for production
   npm run build
   npm start
   ```

## Status: ✅ COMPLETE

Task 3 is fully implemented with:
- Authorization middleware with permission checking
- Production instance protection
- Complete Express application
- All endpoints protected
- Comprehensive error handling
- Detailed logging

Ready to proceed to Task 4 (Audit logging service)!
