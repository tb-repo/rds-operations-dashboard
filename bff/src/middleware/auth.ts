import { Request, Response, NextFunction } from 'express'
import { JwtValidator, CognitoTokenPayload } from '../services/jwt-validator'
import { logger } from '../utils/logger'
import { auditService } from '../services/audit'

// Extend Express Request to include user context
declare global {
  namespace Express {
    interface Request {
      user?: UserContext
    }
  }
}

export interface UserContext {
  userId: string
  email: string
  name?: string
  groups: string[]
  permissions: string[]
  sessionId: string
  authTime: number
  tokenExpiry: number
}

export class AuthMiddleware {
  private jwtValidator: JwtValidator

  constructor(userPoolId: string, region: string, clientId?: string) {
    this.jwtValidator = new JwtValidator(userPoolId, region, clientId)
    logger.info('Auth middleware initialized')
  }

  /**
   * Middleware to authenticate requests
   */
  authenticate() {
    return async (req: Request, res: Response, next: NextFunction) => {
      try {
        // Extract token from Authorization header
        const token = this.extractToken(req)

        if (!token) {
          logger.warn('Authentication failed: No token provided', {
            path: req.path,
            method: req.method,
            ip: req.ip,
          })

          // Log failed authentication attempt
          auditService.logAuthenticationEvent(
            'AUTH_LOGIN_FAILURE',
            'unknown',
            'unknown',
            req.ip || 'unknown',
            req.get('user-agent') || 'unknown',
            'failure',
            { reason: 'No token provided', path: req.path }
          )
          
          return res.status(401).json({
            error: 'Unauthorized',
            message: 'Authentication required',
            code: 'AUTH_REQUIRED',
          })
        }

        // Validate token
        const validationResult = await this.jwtValidator.validateToken(token)

        if (!validationResult.valid || !validationResult.payload) {
          logger.warn('Authentication failed: Invalid token', {
            path: req.path,
            method: req.method,
            ip: req.ip,
            error: validationResult.error,
          })

          // Log failed authentication attempt
          auditService.logAuthenticationEvent(
            'AUTH_LOGIN_FAILURE',
            'unknown',
            'unknown',
            req.ip || 'unknown',
            req.get('user-agent') || 'unknown',
            'failure',
            { reason: validationResult.error, path: req.path }
          )

          // Determine specific error code
          const errorCode = this.getErrorCode(validationResult.error)
          const statusCode = errorCode === 'TOKEN_EXPIRED' ? 401 : 401

          return res.status(statusCode).json({
            error: 'Unauthorized',
            message: validationResult.error || 'Invalid authentication token',
            code: errorCode,
          })
        }

        // Extract user context from token
        const userContext = this.extractUserContext(validationResult.payload)
        
        // Attach user context to request
        req.user = userContext

        logger.debug('User authenticated successfully', {
          userId: userContext.userId,
          email: userContext.email,
          groups: userContext.groups,
          path: req.path,
        })

        // Log successful authentication
        auditService.logAuthenticationEvent(
          'AUTH_LOGIN_SUCCESS',
          userContext.userId,
          userContext.email,
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          'success',
          { path: req.path, groups: userContext.groups }
        )

        next()
      } catch (error) {
        logger.error('Authentication error', {
          error: error instanceof Error ? error.message : 'Unknown error',
          path: req.path,
          method: req.method,
        })

        res.status(500).json({
          error: 'Internal Server Error',
          message: 'Authentication service error',
          code: 'AUTH_SERVICE_ERROR',
        })
      }
    }
  }

  /**
   * Extract JWT token from Authorization header
   */
  private extractToken(req: Request): string | null {
    const authHeader = req.headers.authorization

    if (!authHeader) {
      return null
    }

    // Support both "Bearer <token>" and just "<token>"
    const parts = authHeader.split(' ')
    
    if (parts.length === 2 && parts[0].toLowerCase() === 'bearer') {
      return parts[1]
    }
    
    if (parts.length === 1) {
      return parts[0]
    }

    return null
  }

  /**
   * Extract user context from validated token payload
   */
  private extractUserContext(payload: CognitoTokenPayload): UserContext {
    const groups = payload['cognito:groups'] || []
    const permissions = this.getPermissionsForGroups(groups)

    return {
      userId: payload.sub,
      email: payload.email,
      name: payload.name,
      groups,
      permissions,
      sessionId: payload.jti || payload.sub,
      authTime: payload.auth_time,
      tokenExpiry: payload.exp || 0,
    }
  }

  /**
   * Map user groups to permissions
   * This will be enhanced in the permission mapping service
   */
  private getPermissionsForGroups(groups: string[]): string[] {
    const permissions = new Set<string>()

    for (const group of groups) {
      const groupPermissions = this.getGroupPermissions(group)
      groupPermissions.forEach(p => permissions.add(p))
    }

    return Array.from(permissions)
  }

  /**
   * Get permissions for a specific group
   */
  private getGroupPermissions(group: string): string[] {
    const rolePermissions: Record<string, string[]> = {
      Admin: [
        'view_instances',
        'view_metrics',
        'view_compliance',
        'view_costs',
        'execute_operations',
        'generate_cloudops',
        'trigger_discovery',
        'manage_users',
      ],
      DBA: [
        'view_instances',
        'view_metrics',
        'view_compliance',
        'view_costs',
        'execute_operations',
        'generate_cloudops',
        'trigger_discovery',
      ],
      ReadOnly: [
        'view_instances',
        'view_metrics',
        'view_compliance',
        'view_costs',
      ],
    }

    return rolePermissions[group] || []
  }

  /**
   * Determine error code from validation error message
   */
  private getErrorCode(error?: string): string {
    if (!error) {
      return 'INVALID_TOKEN'
    }

    if (error.toLowerCase().includes('expired')) {
      return 'TOKEN_EXPIRED'
    }

    if (error.toLowerCase().includes('signature')) {
      return 'INVALID_SIGNATURE'
    }

    if (error.toLowerCase().includes('issuer')) {
      return 'INVALID_ISSUER'
    }

    return 'INVALID_TOKEN'
  }

  /**
   * Optional middleware to check if token is about to expire
   */
  checkTokenExpiry(warningThresholdMinutes: number = 5) {
    return (req: Request, res: Response, next: NextFunction) => {
      if (!req.user) {
        return next()
      }

      const now = Date.now() / 1000
      const expiresIn = req.user.tokenExpiry - now
      const warningThreshold = warningThresholdMinutes * 60

      if (expiresIn < warningThreshold && expiresIn > 0) {
        res.setHeader('X-Token-Expiring-Soon', 'true')
        res.setHeader('X-Token-Expires-In', Math.floor(expiresIn).toString())
        
        logger.debug('Token expiring soon', {
          userId: req.user.userId,
          expiresIn: Math.floor(expiresIn),
        })
      }

      next()
    }
  }
}
