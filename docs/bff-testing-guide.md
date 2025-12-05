# BFF Testing Guide

## Overview

This guide provides comprehensive testing procedures for the Express BFF authentication and authorization flows.

## Prerequisites

Before testing:
- [ ] BFF stack deployed (`cdk deploy RDSDashboard-BFF`)
- [ ] Auth stack deployed (`cdk deploy RDSDashboard-Auth`)
- [ ] Cognito users created with appropriate groups
- [ ] Frontend configured with BFF API URL
- [ ] API key stored in Secrets Manager

## Test Scenarios

### 1. JWT Validation Tests

#### 1.1 Valid JWT Token

**Objective:** Verify that valid JWT tokens are accepted

**Steps:**
1. Log in through Cognito Hosted UI
2. Obtain JWT access token
3. Make request to `/api/instances` with `Authorization: Bearer <token>`
4. Verify response is 200 OK

**Expected Result:**
- Request succeeds
- User information extracted from token
- Request proxied to backend API

**Validation:**
```bash
# Get token from Cognito
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $COGNITO_CLIENT_ID \
  --auth-parameters USERNAME=$USERNAME,PASSWORD=$PASSWORD \
  --query 'AuthenticationResult.AccessToken' \
  --output text)

# Test API call
curl -H "Authorization: Bearer $TOKEN" \
  https://<bff-api-id>.execute-api.<region>.amazonaws.com/prod/api/instances
```

#### 1.2 Expired JWT Token

**Objective:** Verify that expired tokens are rejected

**Steps:**
1. Use an expired JWT token
2. Make request to `/api/instances`
3. Verify response is 401 Unauthorized

**Expected Result:**
- Request rejected
- Error message indicates token expired

#### 1.3 Invalid JWT Signature

**Objective:** Verify that tokens with invalid signatures are rejected

**Steps:**
1. Modify a valid JWT token (change signature)
2. Make request to `/api/instances`
3. Verify response is 401 Unauthorized

**Expected Result:**
- Request rejected
- Error message indicates invalid signature

#### 1.4 Missing JWT Token

**Objective:** Verify that requests without tokens are rejected

**Steps:**
1. Make request to `/api/instances` without Authorization header
2. Verify response is 401 Unauthorized

**Expected Result:**
- Request rejected
- Error message indicates missing token

### 2. RBAC Middleware Tests

#### 2.1 Admin User - Full Access

**Objective:** Verify admin users can access all endpoints

**Test Matrix:**
| Endpoint | Permission Required | Expected Result |
|----------|-------------------|-----------------|
| GET /api/instances | view_instances | ✅ 200 OK |
| POST /api/operations | execute_operations | ✅ 200 OK |
| POST /api/cloudops | generate_cloudops | ✅ 200 OK |
| GET /api/costs | view_costs | ✅ 200 OK |
| GET /api/compliance | view_compliance | ✅ 200 OK |
| GET /api/users | manage_users | ✅ 200 OK |

**Steps:**
1. Log in as user in `Administrators` group
2. Test each endpoint
3. Verify all requests succeed

#### 2.2 Operator User - Limited Access

**Objective:** Verify operators have appropriate permissions

**Test Matrix:**
| Endpoint | Permission Required | Expected Result |
|----------|-------------------|-----------------|
| GET /api/instances | view_instances | ✅ 200 OK |
| POST /api/operations | execute_operations | ✅ 200 OK |
| POST /api/cloudops | generate_cloudops | ❌ 403 Forbidden |
| GET /api/costs | view_costs | ✅ 200 OK |
| GET /api/compliance | view_compliance | ✅ 200 OK |
| GET /api/users | manage_users | ❌ 403 Forbidden |

**Steps:**
1. Log in as user in `Operators` group
2. Test each endpoint
3. Verify appropriate access/denial

#### 2.3 Viewer User - Read-Only Access

**Objective:** Verify viewers have read-only permissions

**Test Matrix:**
| Endpoint | Permission Required | Expected Result |
|----------|-------------------|-----------------|
| GET /api/instances | view_instances | ✅ 200 OK |
| POST /api/operations | execute_operations | ❌ 403 Forbidden |
| POST /api/cloudops | generate_cloudops | ❌ 403 Forbidden |
| GET /api/costs | view_costs | ✅ 200 OK |
| GET /api/compliance | view_compliance | ✅ 200 OK |
| GET /api/users | manage_users | ❌ 403 Forbidden |

**Steps:**
1. Log in as user in `Viewers` group
2. Test each endpoint
3. Verify read-only access

#### 2.4 Unauthorized User - No Group Membership

**Objective:** Verify users without group membership are denied

**Steps:**
1. Log in as user not in any group
2. Attempt to access any protected endpoint
3. Verify response is 403 Forbidden

**Expected Result:**
- All requests denied
- Error message indicates insufficient permissions

### 3. Audit Logging Tests

#### 3.1 Authentication Events

**Objective:** Verify authentication events are logged

**Steps:**
1. Log in through Cognito
2. Make authenticated request
3. Check CloudWatch Logs for audit events

**Expected Log Entries:**
```json
{
  "timestamp": "2025-12-01T10:00:00.000Z",
  "level": "info",
  "message": "Incoming request",
  "method": "GET",
  "path": "/api/instances",
  "userId": "user-123",
  "email": "user@example.com"
}
```

#### 3.2 Operation Execution Events

**Objective:** Verify operation executions are logged

**Steps:**
1. Execute an operation (e.g., restart RDS instance)
2. Check audit log table in DynamoDB
3. Verify event details are recorded

**Expected Audit Record:**
```json
{
  "event_id": "evt-123",
  "event_type": "OPERATION_EXECUTED",
  "timestamp": "2025-12-01T10:00:00.000Z",
  "user_id": "user-123",
  "user_email": "user@example.com",
  "resource_id": "instance:db-instance-1",
  "action": "restart",
  "status": "success",
  "ip_address": "203.0.113.1",
  "user_agent": "Mozilla/5.0...",
  "details": {
    "instanceId": "db-instance-1",
    "operation": "restart"
  }
}
```

#### 3.3 Authorization Denial Events

**Objective:** Verify authorization denials are logged

**Steps:**
1. Attempt unauthorized operation
2. Check CloudWatch Logs
3. Verify denial is logged

**Expected Log Entry:**
```json
{
  "timestamp": "2025-12-01T10:00:00.000Z",
  "level": "warn",
  "message": "Authorization denied",
  "userId": "user-123",
  "email": "user@example.com",
  "requiredPermission": "manage_users",
  "userPermissions": ["view_instances", "view_costs"]
}
```

### 4. Integration Tests

#### 4.1 End-to-End Flow

**Objective:** Verify complete request flow from frontend to backend

**Steps:**
1. User logs in via frontend
2. Frontend obtains JWT token
3. Frontend makes API request to BFF
4. BFF validates JWT
5. BFF checks permissions
6. BFF proxies to backend API
7. BFF returns response to frontend
8. Audit event logged

**Validation Points:**
- [ ] JWT validation succeeds
- [ ] Permission check passes
- [ ] Backend API receives request with API key
- [ ] Response returned to frontend
- [ ] Audit log entry created

#### 4.2 Token Refresh Flow

**Objective:** Verify token refresh works correctly

**Steps:**
1. User logs in and obtains tokens
2. Access token expires
3. Frontend uses refresh token to get new access token
4. New access token works for API requests

**Expected Result:**
- Token refresh succeeds
- New access token is valid
- API requests work with new token

#### 4.3 Concurrent Requests

**Objective:** Verify BFF handles concurrent requests correctly

**Steps:**
1. Make 10 concurrent requests to different endpoints
2. Verify all requests succeed
3. Check for race conditions or errors

**Expected Result:**
- All requests complete successfully
- No errors or timeouts
- Audit logs show all requests

### 5. Error Handling Tests

#### 5.1 Backend API Unavailable

**Objective:** Verify graceful handling when backend is down

**Steps:**
1. Stop backend API
2. Make request through BFF
3. Verify appropriate error response

**Expected Result:**
- BFF returns 500 or 503 error
- Error message is user-friendly
- Error logged in CloudWatch

#### 5.2 Secrets Manager Unavailable

**Objective:** Verify handling when Secrets Manager is unavailable

**Steps:**
1. Simulate Secrets Manager failure
2. Make request through BFF
3. Verify appropriate error response

**Expected Result:**
- BFF returns 500 error
- Error logged
- Request fails gracefully

#### 5.3 Cognito JWKS Endpoint Unavailable

**Objective:** Verify handling when JWKS endpoint is down

**Steps:**
1. Simulate Cognito JWKS endpoint failure
2. Make authenticated request
3. Verify appropriate error response

**Expected Result:**
- BFF returns 401 or 503 error
- Error logged
- Cached JWKS used if available

## Automated Testing

### Unit Tests

Run unit tests for middleware:

```bash
cd bff
npm test
```

### Integration Tests

Run integration tests against deployed BFF:

```bash
cd bff
npm run test:integration
```

### Load Tests

Run load tests to verify performance:

```bash
# Using artillery
artillery run load-test.yml

# Or using ab
ab -n 1000 -c 10 -H "Authorization: Bearer $TOKEN" \
  https://<bff-api-id>.execute-api.<region>.amazonaws.com/prod/api/instances
```

## Test Data Setup

### Create Test Users

```bash
# Admin user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username admin@example.com \
  --user-attributes Name=email,Value=admin@example.com \
  --temporary-password TempPass123!

aws cognito-idp admin-add-user-to-group \
  --user-pool-id $USER_POOL_ID \
  --username admin@example.com \
  --group-name Administrators

# Operator user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username operator@example.com \
  --user-attributes Name=email,Value=operator@example.com \
  --temporary-password TempPass123!

aws cognito-idp admin-add-user-to-group \
  --user-pool-id $USER_POOL_ID \
  --username operator@example.com \
  --group-name Operators

# Viewer user
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username viewer@example.com \
  --user-attributes Name=email,Value=viewer@example.com \
  --temporary-password TempPass123!

aws cognito-idp admin-add-user-to-group \
  --user-pool-id $USER_POOL_ID \
  --username viewer@example.com \
  --group-name Viewers
```

## Monitoring During Tests

### CloudWatch Logs

Monitor logs in real-time:

```bash
# BFF logs
aws logs tail /aws/lambda/rds-dashboard-bff --follow

# Audit logs
aws logs tail /aws/rds-dashboard/audit --follow
```

### CloudWatch Metrics

Monitor key metrics:
- Lambda invocations
- Lambda errors
- Lambda duration
- API Gateway 4xx/5xx errors
- API Gateway latency

### X-Ray Traces

View distributed traces:
1. Open AWS X-Ray console
2. View service map
3. Analyze traces for slow requests
4. Identify bottlenecks

## Success Criteria

All tests must pass:
- [ ] JWT validation works correctly
- [ ] RBAC middleware enforces permissions
- [ ] Audit logging captures all events
- [ ] Error handling is graceful
- [ ] Performance meets requirements (<1s P99 latency)
- [ ] No security vulnerabilities
- [ ] All user roles work as expected

## Troubleshooting

### JWT Validation Failures

Check:
- Token is not expired
- Token signature is valid
- JWKS endpoint is accessible
- User Pool ID is correct

### Permission Denials

Check:
- User is in correct Cognito group
- Group has required permissions
- Permission mapping is correct

### Audit Log Missing

Check:
- Audit logging is enabled
- CloudWatch Logs permissions
- DynamoDB table exists
- Audit service is working

---

**Metadata:**
```json
{
  "generated_by": "claude-3.5-sonnet",
  "timestamp": "2025-12-01T11:15:00Z",
  "version": "1.0.0",
  "policy_version": "v1.0.0",
  "traceability": "REQ-1.2, REQ-1.4 → DESIGN-BFF → TASK-1.5",
  "review_status": "Pending",
  "risk_level": "Level 2",
  "reviewed_by": null,
  "approved_by": null
}
```
