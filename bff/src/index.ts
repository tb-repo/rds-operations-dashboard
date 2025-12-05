import express, { Request, Response } from 'express'
import cors from 'cors'
import helmet from 'helmet'
import dotenv from 'dotenv'
import { AuthMiddleware } from './middleware/auth'
import { AuthorizationMiddleware } from './middleware/authorization'
import { CognitoAdminService } from './services/cognito-admin'
import { createUserRoutes } from './routes/users'
import { logger } from './utils/logger'
import { auditService } from './services/audit'
import axios from 'axios'

// Load environment variables
dotenv.config()

// Validate required environment variables
const requiredEnvVars = [
  'COGNITO_USER_POOL_ID',
  'COGNITO_REGION',
  'INTERNAL_API_URL',
  'INTERNAL_API_KEY',
]

for (const envVar of requiredEnvVars) {
  if (!process.env[envVar]) {
    logger.error(`Missing required environment variable: ${envVar}`)
    process.exit(1)
  }
}

// Initialize Express app
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

// CORS configuration
const corsOptions = {
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true,
  optionsSuccessStatus: 200,
}
app.use(cors(corsOptions))

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
  process.env.COGNITO_USER_POOL_ID!,
  process.env.COGNITO_REGION!,
  process.env.COGNITO_CLIENT_ID
)

const authorizationMiddleware = new AuthorizationMiddleware(
  process.env.INTERNAL_API_URL!,
  process.env.INTERNAL_API_KEY!
)

const cognitoAdminService = new CognitoAdminService(
  process.env.COGNITO_REGION!,
  process.env.COGNITO_USER_POOL_ID!
)

// Health check endpoint (no auth required)
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() })
})

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
      const response = await axios.get(`${process.env.INTERNAL_API_URL}/instances`, {
        headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
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
        `${process.env.INTERNAL_API_URL}/instances/${req.params.id}`,
        {
          headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
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
      const response = await axios.get(`${process.env.INTERNAL_API_URL}/metrics`, {
        headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
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
      const response = await axios.get(`${process.env.INTERNAL_API_URL}/compliance`, {
        headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
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
      const response = await axios.get(`${process.env.INTERNAL_API_URL}/costs`, {
        headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
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
      // Add user context to request body for audit logging
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        user_id: req.user?.userId,
      }

      const response = await axios.post(
        `${process.env.INTERNAL_API_URL}/operations`,
        requestBody,
        {
          headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
        }
      )
      
      logger.info('Operation executed', {
        userId: req.user?.userId,
        email: req.user?.email,
        operation: req.body.operation,
        instanceId: req.body.instance_id,
      })

      // Log operation execution
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
      // Add user context to request body
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        user_id: req.user?.userId,
      }

      const response = await axios.post(
        `${process.env.INTERNAL_API_URL}/cloudops`,
        requestBody,
        {
          headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
        }
      )
      
      logger.info('CloudOps request generated', {
        userId: req.user?.userId,
        email: req.user?.email,
        instanceId: req.body.instance_id,
        requestType: req.body.request_type,
      })

      // Log CloudOps generation
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
        `${process.env.INTERNAL_API_URL}/discovery/trigger`,
        req.body,
        {
          headers: { 'x-api-key': process.env.INTERNAL_API_KEY },
        }
      )
      
      logger.info('Discovery triggered', {
        userId: req.user?.userId,
        email: req.user?.email,
      })

      // Log discovery trigger
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
        `${process.env.INTERNAL_API_URL}/monitoring`,
        req.body,
        {
          headers: { 
            'x-api-key': process.env.INTERNAL_API_KEY,
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
  authorizationMiddleware.authorize('execute_operations'), // Requires operations permission
  async (req: Request, res: Response) => {
    try {
      // Add user context to request body
      const requestBody = {
        ...req.body,
        requested_by: req.user?.email,
        approved_by: req.user?.email,
        rejected_by: req.user?.email,
        cancelled_by: req.user?.email,
        user_email: req.user?.email,
      }

      const response = await axios.post(
        `${process.env.INTERNAL_API_URL}/approvals`,
        requestBody,
        {
          headers: { 
            'x-api-key': process.env.INTERNAL_API_KEY,
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

      // Log approval events
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
        `${process.env.INTERNAL_API_URL}/approvals`,
        {
          headers: { 
            'x-api-key': process.env.INTERNAL_API_KEY,
          },
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
// User Management Endpoints (Admin only)
// ========================================
const userRoutes = createUserRoutes(cognitoAdminService)

// Apply authorization middleware to user management routes (except /me)
app.use(
  '/api/users',
  (req, res, next) => {
    // Skip authorization for /me endpoint
    if (req.path === '/me') {
      return next()
    }
    // Apply manage_users permission for all other user endpoints
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

// 404 handler
app.use((req: Request, res: Response) => {
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
    cognitoUserPoolId: process.env.COGNITO_USER_POOL_ID,
    cognitoRegion: process.env.COGNITO_REGION,
  })
})

export default app
