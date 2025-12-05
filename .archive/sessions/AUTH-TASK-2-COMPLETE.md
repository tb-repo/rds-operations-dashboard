# Task 2 Complete: BFF Authentication Middleware ✅

## Summary

Successfully implemented complete JWT token validation and authentication middleware for the BFF layer with Cognito integration.

## What Was Implemented

### 1. Project Setup (`bff/package.json`, `bff/tsconfig.json`)
- ✅ TypeScript configuration for Node.js 18+
- ✅ Dependencies: express, jsonwebtoken, jwks-rsa, axios, cors, helmet, winston
- ✅ Dev dependencies: TypeScript, Jest, ESLint
- ✅ Build and test scripts configured

### 2. JWT Token Validation Service (`bff/src/services/jwt-validator.ts`)
- ✅ **JwtValidator class** with full Cognito token validation
- ✅ **JWKS client integration** to fetch Cognito public keys
- ✅ **Key caching** with 1-hour TTL for performance
- ✅ **Signature verification** using RS256 algorithm
- ✅ **Claims validation**: issuer, expiration, audience, required fields
- ✅ **Token expiry checking** utility method
- ✅ **Decode token** utility for debugging
- ✅ **Comprehensive error handling** with detailed error messages

**Key Features**:
- Validates JWT signature using Cognito public keys
- Caches public keys to reduce JWKS endpoint calls
- Verifies token expiration and not-before claims
- Validates issuer matches Cognito User Pool
- Extracts user information and groups from token

### 3. Authentication Middleware (`bff/src/middleware/auth.ts`)
- ✅ **AuthMiddleware class** for Express integration
- ✅ **authenticate()** middleware function
- ✅ **Token extraction** from Authorization header (Bearer token)
- ✅ **User context extraction** from validated token
- ✅ **Request augmentation** with user context
- ✅ **Permission mapping** from groups to permissions
- ✅ **Error handling** with specific error codes
- ✅ **Token expiry warning** middleware (optional)

**User Context Structure**:
```typescript
interface UserContext {
  userId: string
  email: string
  name?: string
  groups: string[]
  permissions: string[]
  sessionId: string
  authTime: number
  tokenExpiry: number
}
```

**Error Codes**:
- `AUTH_REQUIRED` - No token provided
- `TOKEN_EXPIRED` - Token has expired
- `INVALID_TOKEN` - Token format or signature invalid
- `INVALID_SIGNATURE` - Signature verification failed
- `INVALID_ISSUER` - Token from wrong issuer
- `AUTH_SERVICE_ERROR` - Internal authentication error

### 4. Permission Mapping Service (`bff/src/services/permissions.ts`)
- ✅ **PermissionService class** with comprehensive permission management
- ✅ **Role-to-Permission mapping** for Admin, DBA, ReadOnly
- ✅ **Endpoint-to-Permission mapping** for all API routes
- ✅ **Permission checking** utilities (has, hasAny, hasAll)
- ✅ **Pattern matching** for parameterized routes
- ✅ **Role and permission descriptions** for UI display
- ✅ **Singleton export** for easy import

**Permissions Defined**:
- `view_instances` - View RDS instances
- `view_metrics` - View performance metrics
- `view_compliance` - View compliance status
- `view_costs` - View cost analysis
- `execute_operations` - Execute operations
- `generate_cloudops` - Generate change requests
- `trigger_discovery` - Trigger discovery scans
- `manage_users` - Manage users and roles

**Role Permissions Matrix**:
| Permission | Admin | DBA | ReadOnly |
|------------|-------|-----|----------|
| view_instances | ✓ | ✓ | ✓ |
| view_metrics | ✓ | ✓ | ✓ |
| view_compliance | ✓ | ✓ | ✓ |
| view_costs | ✓ | ✓ | ✓ |
| execute_operations | ✓ | ✓ | ✗ |
| generate_cloudops | ✓ | ✓ | ✗ |
| trigger_discovery | ✓ | ✓ | ✗ |
| manage_users | ✓ | ✗ | ✗ |

### 5. Logger Utility (`bff/src/utils/logger.ts`)
- ✅ Winston logger configuration
- ✅ JSON format for production
- ✅ Pretty format for development
- ✅ Configurable log levels
- ✅ Structured logging with metadata

## Architecture

```
Request with JWT Token
    ↓
AuthMiddleware.authenticate()
    ↓
Extract token from Authorization header
    ↓
JwtValidator.validateToken()
    ├─→ Fetch Cognito public keys (cached)
    ├─→ Verify token signature
    ├─→ Validate claims (exp, iss, etc.)
    └─→ Return validated payload
    ↓
Extract user context
    ├─→ userId, email, name
    ├─→ groups from cognito:groups
    └─→ permissions from PermissionService
    ↓
Attach user context to req.user
    ↓
Next middleware / Route handler
```

## Usage Examples

### Initialize Auth Middleware

```typescript
import { AuthMiddleware } from './middleware/auth'

const authMiddleware = new AuthMiddleware(
  process.env.COGNITO_USER_POOL_ID!,
  process.env.COGNITO_REGION!,
  process.env.COGNITO_CLIENT_ID
)

// Apply to all routes
app.use(authMiddleware.authenticate())

// Or apply to specific routes
app.get('/api/instances', authMiddleware.authenticate(), (req, res) => {
  // req.user is available here
  console.log(req.user.email, req.user.permissions)
})
```

### Check Token Expiry

```typescript
// Warn users when token is about to expire
app.use(authMiddleware.checkTokenExpiry(5)) // 5 minutes warning
```

### Use Permission Service

```typescript
import { permissionService } from './services/permissions'

// Get permissions for user groups
const permissions = permissionService.getPermissionsForGroups(['DBA'])

// Check if user has permission
const canExecute = permissionService.hasPermission(
  req.user.permissions,
  'execute_operations'
)

// Get required permission for endpoint
const required = permissionService.getRequiredPermission('POST', '/api/operations')
```

## Environment Variables Required

```bash
# Cognito Configuration
COGNITO_USER_POOL_ID=ap-southeast-1_xxxxxxxxx
COGNITO_REGION=ap-southeast-1
COGNITO_CLIENT_ID=xxxxxxxxxxxxxxxxxxxxxxxxxx

# Optional
LOG_LEVEL=info
NODE_ENV=production
```

## Testing

### Manual Testing

```bash
# Install dependencies
cd bff
npm install

# Run in development mode
npm run dev

# Build for production
npm run build
npm start
```

### Test with cURL

```bash
# Get token from Cognito (after login)
TOKEN="eyJraWQiOiJ..."

# Test authenticated endpoint
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/instances

# Test without token (should return 401)
curl http://localhost:3000/api/instances
```

### Expected Responses

**Success (200)**:
```json
{
  "instances": [...]
}
```

**No Token (401)**:
```json
{
  "error": "Unauthorized",
  "message": "Authentication required",
  "code": "AUTH_REQUIRED"
}
```

**Invalid Token (401)**:
```json
{
  "error": "Unauthorized",
  "message": "Invalid authentication token",
  "code": "INVALID_TOKEN"
}
```

**Expired Token (401)**:
```json
{
  "error": "Unauthorized",
  "message": "Token has expired",
  "code": "TOKEN_EXPIRED"
}
```

## Security Features

### Token Validation
- ✅ Signature verification using Cognito public keys
- ✅ Expiration checking
- ✅ Issuer validation
- ✅ Audience validation (optional)
- ✅ Not-before claim validation

### Performance Optimization
- ✅ Public key caching (1 hour TTL)
- ✅ Rate limiting on JWKS requests (10/minute)
- ✅ Efficient permission lookups

### Error Handling
- ✅ Detailed error codes for client handling
- ✅ Secure error messages (no sensitive data)
- ✅ Comprehensive logging for debugging
- ✅ Graceful degradation on errors

## Integration Points

### With Cognito
- Fetches public keys from `/.well-known/jwks.json`
- Validates tokens issued by Cognito User Pool
- Extracts user groups from `cognito:groups` claim

### With Express
- Middleware pattern for easy integration
- Augments Request object with user context
- Compatible with other Express middleware

### With Authorization Middleware (Next Task)
- Provides user context with permissions
- Enables permission-based access control
- Supports production instance protection

## Files Created

```
bff/
├── package.json                    # Dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
└── src/
    ├── services/
    │   ├── jwt-validator.ts        # JWT token validation
    │   └── permissions.ts          # Permission mapping
    ├── middleware/
    │   └── auth.ts                 # Authentication middleware
    └── utils/
        └── logger.ts               # Winston logger
```

## Next Steps

Now that authentication middleware is complete, proceed to:

1. **Task 3**: Implement BFF authorization middleware
   - Permission checking for endpoints
   - Production instance protection
   - Authorization logging

2. **Task 4**: Implement audit logging service
   - Log authentication events
   - Log authorization decisions
   - CloudWatch integration

3. **Integration**: Wire up middleware in Express app
   ```typescript
   app.use(authMiddleware.authenticate())
   app.use(authorizationMiddleware.authorize())
   ```

## Status: ✅ COMPLETE

Task 2 is fully implemented with:
- JWT token validation service
- Authentication middleware
- Permission mapping service
- Comprehensive error handling
- Production-ready logging

Ready to proceed to Task 3 (Authorization middleware)!
