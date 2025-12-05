# BFF Architecture

## Overview

The Backend-for-Frontend (BFF) is implemented as an Express.js application deployed as a Lambda container. This architecture provides sophisticated authentication, authorization, and audit logging capabilities.

## Architecture Decision

**Chosen Approach:** Express BFF in Lambda Container

### Why Express Container?

1. **Sophisticated Authentication** - JWT validation using jwks-rsa library
2. **Fine-grained RBAC** - Custom authorization middleware with permission checks
3. **Comprehensive Audit Logging** - Detailed request tracking and compliance logging
4. **Maintainability** - Proper TypeScript codebase with clear separation of concerns
5. **Development Experience** - Can run locally for testing and debugging
6. **Flexibility** - Easy to add new endpoints, middleware, and business logic

### Trade-offs

- **Cold Start**: Slightly higher cold start time compared to inline Lambda (mitigated by container caching)
- **Complexity**: Requires Docker build step in deployment
- **Size**: Larger deployment package than simple proxy

## Components

### 1. Express Application (`bff/src/index.ts`)

The main Express application that:
- Handles HTTP routing
- Applies security middleware (helmet, CORS)
- Validates JWT tokens
- Enforces RBAC permissions
- Logs audit events
- Proxies requests to internal API

### 2. Authentication Middleware (`bff/src/middleware/auth.ts`)

Validates JWT tokens from Cognito:
- Fetches JWKS from Cognito
- Verifies token signature
- Checks token expiration
- Extracts user claims

### 3. Authorization Middleware (`bff/src/middleware/authorization.ts`)

Enforces role-based access control:
- Checks user permissions
- Maps permissions to Cognito groups
- Denies unauthorized requests

### 4. Audit Service (`bff/src/services/audit.ts`)

Logs security and operational events:
- User authentication events
- Operation executions
- Permission denials
- CloudOps request generations

### 5. Lambda Container (Dockerfile)

Packages the Express app for Lambda:
- Uses AWS Lambda Node.js 18 base image
- Installs dependencies
- Builds TypeScript to JavaScript
- Includes Lambda Web Adapter for Express compatibility

## Request Flow

```
┌─────────┐
│ Frontend│
└────┬────┘
     │ HTTPS + JWT
     ▼
┌─────────────────┐
│  API Gateway    │
│  (BFF API)      │
└────┬────────────┘
     │ Proxy all requests
     ▼
┌─────────────────────────────┐
│  Lambda Container           │
│  ┌───────────────────────┐  │
│  │  Express BFF          │  │
│  │  ┌─────────────────┐  │  │
│  │  │ Auth Middleware │  │  │
│  │  │ - Validate JWT  │  │  │
│  │  └────────┬────────┘  │  │
│  │           ▼            │  │
│  │  ┌─────────────────┐  │  │
│  │  │ RBAC Middleware │  │  │
│  │  │ - Check Perms   │  │  │
│  │  └────────┬────────┘  │  │
│  │           ▼            │  │
│  │  ┌─────────────────┐  │  │
│  │  │ Route Handler   │  │  │
│  │  │ - Business Logic│  │  │
│  │  └────────┬────────┘  │  │
│  │           ▼            │  │
│  │  ┌─────────────────┐  │  │
│  │  │ Audit Logging   │  │  │
│  │  └─────────────────┘  │  │
│  └───────────────────────┘  │
└─────────────┬───────────────┘
              │ HTTPS + API Key
              ▼
┌─────────────────────────────┐
│  Internal API Gateway       │
│  (Backend Lambda Functions) │
└─────────────────────────────┘
```

## Authentication Flow

1. **User Login**: Frontend redirects to Cognito Hosted UI
2. **Token Issuance**: Cognito issues JWT access token
3. **Request**: Frontend sends request with `Authorization: Bearer <token>`
4. **Validation**: BFF validates JWT signature and expiration
5. **Authorization**: BFF checks user permissions for requested operation
6. **Proxy**: BFF forwards request to internal API with API key
7. **Response**: BFF returns response to frontend

## Environment Variables

The BFF requires these environment variables:

### Cognito Configuration
- `COGNITO_USER_POOL_ID` - User pool for authentication
- `COGNITO_REGION` - AWS region for Cognito
- `COGNITO_CLIENT_ID` - Client ID for OAuth flow

### Internal API Configuration
- `INTERNAL_API_URL` - Backend API endpoint
- `API_SECRET_ARN` - Secrets Manager ARN for API key
- `INTERNAL_API_KEY` - API key (loaded from Secrets Manager)

### Server Configuration
- `PORT` - Server port (8080 for Lambda)
- `NODE_ENV` - Environment (production)
- `LOG_LEVEL` - Logging level (info)

### Frontend Configuration
- `FRONTEND_URL` - CORS origin

### Audit Configuration
- `AUDIT_LOG_GROUP` - CloudWatch log group
- `ENABLE_AUDIT_LOGGING` - Enable audit logs

## Deployment

The BFF is deployed via CDK:

```bash
# Build and deploy
cd infrastructure
cdk deploy RDSDashboard-BFF
```

The deployment:
1. Builds Docker image from `bff/Dockerfile`
2. Pushes image to ECR
3. Creates Lambda function from container image
4. Configures API Gateway integration
5. Sets up IAM roles and permissions

## Security

### IAM Permissions

The BFF Lambda has least-privilege IAM permissions:
- Read Secrets Manager (for API key)
- Read Cognito User Pool (for JWT validation)
- Write CloudWatch Logs (for audit logging)

### Network Security

- API Gateway enforces HTTPS
- CORS configured for specific frontend origin
- Rate limiting (1000 req/sec, 2000 burst)

### Application Security

- Helmet middleware for security headers
- JWT signature validation
- Token expiration checks
- Permission-based authorization
- Audit logging for compliance

## Monitoring

### CloudWatch Logs

- Application logs: `/aws/lambda/rds-dashboard-bff`
- Audit logs: `/aws/rds-dashboard/audit`

### Metrics

- Lambda duration
- Lambda errors
- Lambda throttles
- API Gateway 4xx/5xx errors
- API Gateway latency

## Local Development

Run the BFF locally:

```bash
cd bff

# Install dependencies
npm install

# Set environment variables
cp .env.example .env
# Edit .env with your values

# Run in development mode
npm run dev

# Build for production
npm run build
npm start
```

## Testing

```bash
# Run tests
npm test

# Run linter
npm run lint
```

## Troubleshooting

### Cold Start Issues

If experiencing slow cold starts:
- Consider provisioned concurrency for critical paths
- Optimize Docker image size
- Use Lambda layers for shared dependencies

### Authentication Failures

Check:
- JWT token is valid and not expired
- Cognito User Pool ID is correct
- JWKS endpoint is accessible
- Token signature matches

### Authorization Failures

Check:
- User has required Cognito group membership
- Permission mapping is correct
- RBAC middleware is applied to route

### API Proxy Failures

Check:
- Internal API URL is correct
- API key is valid in Secrets Manager
- Backend Lambda functions are healthy
- Network connectivity between BFF and backend

---

**Metadata:**
```json
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-01T11:00:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.3, REQ-1.5 → DESIGN-BFF → TASK-1.4",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
```
