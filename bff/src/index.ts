import express, { Request, Response } from 'express'
import cors from 'cors'
import helmet from 'helmet'
import dotenv from 'dotenv'
import { AuthMiddleware } from './middleware/auth'
import { AuthorizationMiddleware } from './middleware/authorization'
import { CognitoAdminService } from './services/cognito-admin'
import { createUserRoutes } from './routes/users'
import { createErrorResolutionRoutes } from './routes/error-resolution'
import { logger } from './utils/logger'
import { auditService } from './services/audit'
import { initializeCorsConfig } from './config/cors'
import { createOptionsHandler, addCorsHeaders, handleAllOptions } from './middleware/options-handler'
import axios from 'axios'
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager'

// Helper function to create standard headers for internal API calls
const createInternalApiHeaders = (apiKey: string) => ({
  'x-api-key': apiKey,
  'User-Agent': 'RDS-Dashboard-BFF/1.0',
  'x-bff-request': 'true'
})

// Load environment variables
dotenv.config()

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
    // Fallback to environment variable
    return process.env.INTERNAL_API_KEY || ''
  }
}

// Validate required environment variables
const requiredEnvVars = [
  'COGNITO_USER_POOL_ID',
  'COGNITO_REGION',
  'INTERNAL_API_URL',
]

for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    logger.error(`Missing required environment variable: ${envVar}`)
    process.exit(1)
  }
}

// Cache environment variables at startup
const INTERNAL_API_URL = process.env.INTERNAL_API_URL!.replace(/\/$/, '')
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID!
const COGNITO_REGION = process.env.COGNITO_REGION!
const COGNITO_CLIENT_ID = process.env.COGNITO_CLIENT_ID
const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:3000'
const AUDIT_LOG_GROUP = process.env.AUDIT_LOG_GROUP

// Global variable for API key (loaded at startup)
let INTERNAL_API_KEY = ''

// Create Express app
const app = express()
const port = process.env.PORT || 3000

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", 'data:', 'https:'],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true,
  },
}))

// CORS configuration - Environment-aware with enhanced security
let corsConfig: { allowedOrigins: string[], corsOptions: any, originValidator?: any }
try {
  corsConfig = initializeCorsConfig()
  logger.info('CORS configuration loaded', { 
    allowedOrigins: corsConfig.allowedOrigins,
    environment: process.env.NODE_ENV || 'development'
  })
} catch (error: any) {
  logger.error('Failed to initialize CORS configuration, using fallback', { error: error.message })
  // Fallback CORS configuration for emergency situations
  const fallbackOrigins = [
    process.env.FRONTEND_URL || 'https://d2qvaswtmn22om.cloudfront.net',
    'http://localhost:3000'
  ].filter(Boolean)
  
  corsConfig = {
    allowedOrigins: fallbackOrigins,
    corsOptions: {
      origin: fallbackOrigins,
      credentials: true,
      optionsSuccessStatus: 200
    }
  }
}

app.use(cors(corsConfig.corsOptions))

// Enhanced OPTIONS handling middleware
const optionsConfig = {
  allowedOrigins: corsConfig.allowedOrigins,
  allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH', 'HEAD'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-Api-Key',
    'X-Amz-Date',
    'X-Amz-Security-Token',
    'X-Requested-With',
    'Accept',
    'Origin',
    'Cache-Control'
  ],
  exposedHeaders: [
    'X-Total-Count',
    'X-Request-ID',
    'X-RateLimit-Limit',
    'X-RateLimit-Remaining',
    'X-RateLimit-Reset'
  ],
  maxAge: 86400,
  credentials: true
}

// Apply enhanced OPTIONS handling
app.use(createOptionsHandler(optionsConfig))
app.use(addCorsHeaders(optionsConfig))

// Body parsing middleware
app.use(express.json())
app.use(express.urlencoded({ extended: true }))

// Request logging middleware
app.use((req, res, next) => {
  logger.info('Incoming request', {
    method: req.method,
    path: req.path,
    ip: req.ip,
    userAgent: req.get('user-agent'),
  })
  next()
})

// Initialize auth and authorization middleware
const authMiddleware = new AuthMiddleware(
  COGNITO_USER_POOL_ID,
  COGNITO_REGION,
  COGNITO_CLIENT_ID
)

const authorizationMiddleware = new AuthorizationMiddleware(
  INTERNAL_API_URL,
  INTERNAL_API_KEY  // Will be empty initially, but updated before first request
)

const cognitoAdminService = new CognitoAdminService(
  COGNITO_REGION,
  COGNITO_USER_POOL_ID
)

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

// Health check endpoint (no auth required)
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() })
})

// Health check endpoint with /api prefix (for consistency)
app.get('/api/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() })
})

// CORS configuration endpoint (for debugging - no auth required)
app.get('/cors-config', (req, res) => {
  res.json({
    allowedOrigins: corsConfig.allowedOrigins,
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
    corsEnabled: true
  })
})

// Security monitoring endpoint (no auth required for monitoring)
app.get('/security/cors-stats', (req, res) => {
  if (!corsConfig.originValidator) {
    return res.status(503).json({
      error: 'Origin validator not available',
      message: 'CORS security monitoring is not enabled'
    })
  }
  
  const stats = corsConfig.originValidator.getSecurityStats()
  const recentEvents = corsConfig.originValidator.getRecentSecurityEvents(10)
  
  res.json({
    statistics: stats,
    recentEvents: recentEvents.map((event: any) => ({
      type: event.type,
      origin: event.origin,
      reason: event.reason,
      timestamp: event.timestamp
      // Exclude sensitive info like IP/userAgent from public endpoint
    })),
    timestamp: new Date().toISOString()
  })
})

// Health metrics endpoint for specific instances
app.get(
  '/api/health/:instanceId',
  authMiddleware.authenticate(),
  authorizationMiddleware.authorize('view_metrics'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(
        `${INTERNAL_API_URL}/health/${req.params.instanceId}`,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
        }
      )
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching health metrics', { error, instanceId: req.params.instanceId })
      res.status(500).json({ error: 'Failed to fetch health metrics' })
    }
  }
)

// Apply authentication to all /api routes
app.use('/api', authMiddleware.authenticate())
app.use('/api', authMiddleware.checkTokenExpiry(5))

// ========================================
// Instance Endpoints
// ========================================
app.get(
  '/api/instances',
  authorizationMiddleware.authorize('view_instances'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(`${INTERNAL_API_URL}/instances`, {
        headers: createInternalApiHeaders(INTERNAL_API_KEY),
        params: req.query,
      })
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching instances', { error })
      res.status(500).json({ error: 'Failed to fetch instances' })
    }
  }
)

app.get(
  '/api/instances/:id',
  authorizationMiddleware.authorize('view_instances'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(
        `${INTERNAL_API_URL}/instances/${req.params.id}`,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
        }
      )
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching instance', { error, instanceId: req.params.id })
      res.status(500).json({ error: 'Failed to fetch instance' })
    }
  }
)

// ========================================
// Metrics Endpoints
// ========================================
app.get(
  '/api/metrics',
  authorizationMiddleware.authorize('view_metrics'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(`${INTERNAL_API_URL}/metrics`, {
        headers: createInternalApiHeaders(INTERNAL_API_KEY),
        params: req.query,
      })
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching metrics', { error })
      res.status(500).json({ error: 'Failed to fetch metrics' })
    }
  }
)

// ========================================
// Compliance Endpoints
// ========================================
app.get(
  '/api/compliance',
  authorizationMiddleware.authorize('view_compliance'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(`${INTERNAL_API_URL}/compliance`, {
        headers: createInternalApiHeaders(INTERNAL_API_KEY),
        params: req.query,
      })
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching compliance', { error })
      res.status(500).json({ error: 'Failed to fetch compliance data' })
    }
  }
)

// ========================================
// Cost Endpoints
// ========================================
app.get(
  '/api/costs',
  authorizationMiddleware.authorize('view_costs'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(`${INTERNAL_API_URL}/costs`, {
        headers: createInternalApiHeaders(INTERNAL_API_KEY),
        params: req.query,
      })
      res.json(response.data)
    } catch (error) {
      logger.error('Error fetching costs', { error })
      res.status(500).json({ error: 'Failed to fetch cost data' })
    }
  }
)

// ========================================
// Operations Endpoints
// ========================================
app.post(
  '/api/operations',
  authorizationMiddleware.authorize('execute_operations'),
  async (req: Request, res: Response) => {
    try {
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        user_id: req.user?.userId,
        user_groups: req.user?.groups || [],
        user_permissions: req.user?.permissions || [],
      }

      const response = await axios.post(
        `${INTERNAL_API_URL}/operations`,
        requestBody,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
        }
      )
      
      logger.info('Operation executed', {
        userId: req.user?.userId,
        email: req.user?.email,
        operation: req.body.operation,
        instanceId: req.body.instance_id,
      })

      auditService.logOperationEvent(
        'OPERATION_EXECUTED',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `instance:${req.body.instance_id}`,
        req.body.operation,
        'success',
        undefined,
        {
          instanceId: req.body.instance_id,
          operation: req.body.operation,
          parameters: req.body.parameters,
        }
      )

      res.json(response.data)
    } catch (error) {
      logger.error('Error executing operation', { error })
      res.status(500).json({ error: 'Failed to execute operation' })
    }
  }
)

// ========================================
// CloudOps Endpoints
// ========================================
app.post(
  '/api/cloudops',
  authorizationMiddleware.authorize('generate_cloudops'),
  async (req: Request, res: Response) => {
    try {
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        user_id: req.user?.userId,
      }

      const response = await axios.post(
        `${INTERNAL_API_URL}/cloudops`,
        requestBody,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
        }
      )
      
      logger.info('CloudOps request generated', {
        userId: req.user?.userId,
        email: req.user?.email,
        instanceId: req.body.instance_id,
        requestType: req.body.request_type,
      })

      auditService.logOperationEvent(
        'CLOUDOPS_GENERATED',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `instance:${req.body.instance_id}`,
        req.body.request_type,
        'success',
        undefined,
        {
          instanceId: req.body.instance_id,
          requestType: req.body.request_type,
          changeDetails: req.body.change_details,
        }
      )

      res.json(response.data)
    } catch (error) {
      logger.error('Error generating CloudOps request', { error })
      res.status(500).json({ error: 'Failed to generate CloudOps request' })
    }
  }
)

// ========================================
// Discovery Endpoints
// ========================================
app.post(
  '/api/discovery/trigger',
  authorizationMiddleware.authorize('trigger_discovery'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.post(
        `${INTERNAL_API_URL}/discovery/trigger`,
        req.body,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
        }
      )
      
      logger.info('Discovery triggered', {
        userId: req.user?.userId,
        email: req.user?.email,
      })

      auditService.logOperationEvent(
        'DISCOVERY_TRIGGERED',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        'discovery',
        'trigger',
        'success'
      )

      res.json(response.data)
    } catch (error) {
      logger.error('Error triggering discovery', { error })
      res.status(500).json({ error: 'Failed to trigger discovery' })
    }
  }
)

// ========================================
// Monitoring Endpoints
// ========================================
app.post(
  '/api/monitoring',
  authorizationMiddleware.authorize('view_metrics'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.post(
        `${INTERNAL_API_URL}/monitoring`,
        req.body,
        {
          headers: { 
            ...createInternalApiHeaders(INTERNAL_API_KEY),
            'Content-Type': 'application/json',
          },
        }
      )
      
      logger.info('Monitoring data fetched', {
        userId: req.user?.userId,
        email: req.user?.email,
        operation: req.body.operation,
        instanceId: req.body.instance_id,
      })

      res.json(response.data)
    } catch (error: any) {
      logger.error('Error fetching monitoring data', { 
        error: error.message,
        instanceId: req.body.instance_id,
        operation: req.body.operation,
      })
      res.status(500).json({ error: 'Failed to fetch monitoring data' })
    }
  }
)

// ========================================
// Approval Workflow Endpoints
// ========================================
app.post(
  '/api/approvals',
  authorizationMiddleware.authorize('execute_operations'),
  async (req: Request, res: Response) => {
    try {
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        approved_by: req.user?.email,
        rejected_by: req.user?.email,
        cancelled_by: req.user?.email,
        user_email: req.user?.email,
      }

      const response = await axios.post(
        `${INTERNAL_API_URL}/approvals`,
        requestBody,
        {
          headers: { 
            ...createInternalApiHeaders(INTERNAL_API_KEY),
            'Content-Type': 'application/json',
          },
        }
      )
      
      logger.info('Approval workflow operation', {
        userId: req.user?.userId,
        email: req.user?.email,
        operation: req.body.operation,
        requestId: req.body.request_id,
      })

      const operation = req.body.operation
      if (operation === 'create_request') {
        auditService.logOperationEvent(
          'APPROVAL_REQUEST_CREATED',
          req.user?.userId || 'unknown',
          req.user?.email || 'unknown',
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          `instance:${req.body.instance_id}`,
          req.body.operation_type,
          'success',
          undefined,
          {
            requestId: response.data.request_id,
            riskLevel: req.body.risk_level,
            environment: req.body.environment,
          }
        )
      } else if (operation === 'approve_request') {
        auditService.logOperationEvent(
          'APPROVAL_GRANTED',
          req.user?.userId || 'unknown',
          req.user?.email || 'unknown',
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          `approval:${req.body.request_id}`,
          'approve',
          'success'
        )
      } else if (operation === 'reject_request') {
        auditService.logOperationEvent(
          'APPROVAL_REJECTED',
          req.user?.userId || 'unknown',
          req.user?.email || 'unknown',
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          `approval:${req.body.request_id}`,
          'reject',
          'success',
          undefined,
          { reason: req.body.reason }
        )
      }

      res.json(response.data)
    } catch (error: any) {
      logger.error('Error in approval workflow', { 
        error: error.message,
        operation: req.body.operation,
        requestId: req.body.request_id,
      })
      res.status(500).json({ error: 'Failed to process approval workflow operation' })
    }
  }
)

app.get(
  '/api/approvals',
  authorizationMiddleware.authorize('execute_operations'),
  async (req: Request, res: Response) => {
    try {
      const response = await axios.get(
        `${INTERNAL_API_URL}/approvals`,
        {
          headers: createInternalApiHeaders(INTERNAL_API_KEY),
          params: {
            user_email: req.user?.email,
          },
        }
      )
      
      res.json(response.data)
    } catch (error: any) {
      logger.error('Error fetching approvals', { error: error.message })
      res.status(500).json({ error: 'Failed to fetch approvals' })
    }
  }
)

// ========================================
// Error Resolution Endpoints
// ========================================
const errorResolutionRoutes = createErrorResolutionRoutes(
  INTERNAL_API_URL,
  () => INTERNAL_API_KEY
)

app.use(
  '/api/errors',
  authorizationMiddleware.authorize('view_metrics'),
  errorResolutionRoutes
)

// ========================================
// User Management Endpoints (Admin only)
// ========================================
const userRoutes = createUserRoutes(cognitoAdminService)

app.use(
  '/api/users',
  (req, res, next) => {
    if (req.path === '/me') {
      return next()
    }
    return authorizationMiddleware.authorize('manage_users')(req, res, next)
  },
  userRoutes
)

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: any) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
  })

  res.status(500).json({
    error: 'Internal Server Error',
    message: 'An unexpected error occurred',
  })
})

// Catch-all OPTIONS handler for any unmatched routes
app.options('*', handleAllOptions(optionsConfig))

// 404 handler
app.use((req: Request, res: Response) => {
  // Handle OPTIONS requests that weren't caught earlier
  if (req.method === 'OPTIONS') {
    return handleAllOptions(optionsConfig)(req, res)
  }
  
  res.status(404).json({
    error: 'Not Found',
    message: 'The requested resource was not found',
    path: req.path,
  })
})

// Start server
app.listen(port, () => {
  logger.info(`BFF server started`, {
    port,
    environment: process.env.NODE_ENV || 'development',
    cognitoUserPoolId: COGNITO_USER_POOL_ID,
    cognitoRegion: COGNITO_REGION,
    internalApiUrl: INTERNAL_API_URL,
  })
})

export default app
