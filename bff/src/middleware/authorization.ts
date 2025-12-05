import { Request, Response, NextFunction } from 'express'
import { Permission, permissionService } from '../services/permissions'
import { logger } from '../utils/logger'
import { auditService } from '../services/audit'
import axios from 'axios'

export interface ResourceContext {
  instanceId?: string
  environment?: string
  operation?: string
}

export interface AuthorizationResult {
  allowed: boolean
  reason?: string
  requiredPermission?: Permission
}

export class AuthorizationMiddleware {
  private internalApiUrl: string
  private apiKey: string

  constructor(internalApiUrl: string, apiKey: string) {
    this.internalApiUrl = internalApiUrl
    this.apiKey = apiKey
    logger.info('Authorization middleware initialized')
  }

  /**
   * Middleware to authorize requests based on permissions
   */
  authorize(requiredPermission?: Permission) {
    return async (req: Request, res: Response, next: NextFunction) => {
      try {
        // Check if user is authenticated
        if (!req.user) {
          logger.warn('Authorization failed: User not authenticated', {
            path: req.path,
            method: req.method,
          })
          
          return res.status(401).json({
            error: 'Unauthorized',
            message: 'Authentication required',
            code: 'AUTH_REQUIRED',
          })
        }

        // Determine required permission
        const permission = requiredPermission || 
          permissionService.getRequiredPermission(req.method, req.path)

        if (!permission) {
          // No specific permission required, allow access
          logger.debug('No permission required for endpoint', {
            path: req.path,
            method: req.method,
          })
          return next()
        }

        // Check if user has required permission
        const hasPermission = permissionService.hasPermission(
          req.user.permissions as Permission[],
          permission
        )

        if (!hasPermission) {
          logger.warn('Authorization denied: Insufficient permissions', {
            userId: req.user.userId,
            email: req.user.email,
            requiredPermission: permission,
            userPermissions: req.user.permissions,
            path: req.path,
            method: req.method,
          })

          // Log authorization denial
          auditService.logAuthorizationEvent(
            'AUTHZ_DENIED',
            req.user.userId,
            req.user.email,
            req.ip || 'unknown',
            req.get('user-agent') || 'unknown',
            req.path,
            req.method,
            'failure',
            undefined,
            {
              requiredPermission: permission,
              userPermissions: req.user.permissions,
              reason: 'Insufficient permissions',
            }
          )

          return res.status(403).json({
            error: 'Forbidden',
            message: 'Insufficient permissions to perform this action',
            code: 'INSUFFICIENT_PERMISSIONS',
            requiredPermission: permission,
            userPermissions: req.user.permissions,
          })
        }

        // Additional checks for operations endpoints
        if (permission === 'execute_operations') {
          const instanceId = this.extractInstanceId(req)
          
          if (instanceId) {
            const canOperate = await this.canOperateOnInstance(
              req.user.userId,
              instanceId,
              req.body.operation || 'unknown'
            )

            if (!canOperate.allowed) {
              logger.warn('Authorization denied: Production instance protection', {
                userId: req.user.userId,
                email: req.user.email,
                instanceId,
                operation: req.body.operation,
                reason: canOperate.reason,
              })

              // Log authorization denial for production protection
              auditService.logAuthorizationEvent(
                'AUTHZ_DENIED',
                req.user.userId,
                req.user.email,
                req.ip || 'unknown',
                req.get('user-agent') || 'unknown',
                `instance:${instanceId}`,
                req.body.operation || 'operation',
                'failure',
                undefined,
                {
                  reason: 'Production instance protection',
                  instanceId,
                  environment: 'production',
                }
              )

              return res.status(403).json({
                error: 'Forbidden',
                message: canOperate.reason || 'Operations on production instances are not allowed',
                code: 'PRODUCTION_PROTECTED',
                instanceId,
                environment: 'production',
              })
            }
          }
        }

        logger.debug('Authorization granted', {
          userId: req.user.userId,
          email: req.user.email,
          permission,
          path: req.path,
          method: req.method,
        })

        // Log authorization granted
        auditService.logAuthorizationEvent(
          'AUTHZ_GRANTED',
          req.user.userId,
          req.user.email,
          req.ip || 'unknown',
          req.get('user-agent') || 'unknown',
          req.path,
          req.method,
          'success',
          undefined,
          {
            permission,
          }
        )

        next()
      } catch (error) {
        logger.error('Authorization error', {
          error: error instanceof Error ? error.message : 'Unknown error',
          path: req.path,
          method: req.method,
        })

        res.status(500).json({
          error: 'Internal Server Error',
          message: 'Authorization service error',
          code: 'AUTHZ_SERVICE_ERROR',
        })
      }
    }
  }

  /**
   * Check if user can operate on a specific instance
   */
  private async canOperateOnInstance(
    userId: string,
    instanceId: string,
    operation: string
  ): Promise<AuthorizationResult> {
    try {
      // Fetch instance details from internal API
      const instance = await this.getInstanceDetails(instanceId)

      if (!instance) {
        return {
          allowed: false,
          reason: 'Instance not found',
        }
      }

      // Check if instance is production
      if (instance.environment === 'production') {
        logger.info('Blocking operation on production instance', {
          userId,
          instanceId,
          operation,
          environment: instance.environment,
        })

        return {
          allowed: false,
          reason: 'Operations on production instances are not allowed. Use CloudOps to generate a change request instead.',
        }
      }

      // Allow operations on non-production instances
      return {
        allowed: true,
      }
    } catch (error) {
      logger.error('Error checking instance operability', {
        userId,
        instanceId,
        error: error instanceof Error ? error.message : 'Unknown error',
      })

      // Fail closed - deny access if we can't determine environment
      return {
        allowed: false,
        reason: 'Unable to verify instance environment',
      }
    }
  }

  /**
   * Get instance details from internal API
   */
  private async getInstanceDetails(instanceId: string): Promise<any> {
    try {
      const response = await axios.get(
        `${this.internalApiUrl}/instances/${instanceId}`,
        {
          headers: {
            'x-api-key': this.apiKey,
          },
          timeout: 5000,
        }
      )

      return response.data
    } catch (error) {
      logger.error('Error fetching instance details', {
        instanceId,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      return null
    }
  }

  /**
   * Extract instance ID from request
   */
  private extractInstanceId(req: Request): string | null {
    // Check body
    if (req.body && req.body.instance_id) {
      return req.body.instance_id
    }

    // Check params
    if (req.params && req.params.instanceId) {
      return req.params.instanceId
    }

    if (req.params && req.params.id) {
      return req.params.id
    }

    // Check query
    if (req.query && req.query.instance_id) {
      return req.query.instance_id as string
    }

    return null
  }

  /**
   * Middleware to require specific permission
   */
  requirePermission(permission: Permission) {
    return this.authorize(permission)
  }

  /**
   * Middleware to require any of the specified permissions
   */
  requireAnyPermission(permissions: Permission[]) {
    return (req: Request, res: Response, next: NextFunction) => {
      if (!req.user) {
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'Authentication required',
          code: 'AUTH_REQUIRED',
        })
      }

      const hasAny = permissionService.hasAnyPermission(
        req.user.permissions as Permission[],
        permissions
      )

      if (!hasAny) {
        logger.warn('Authorization denied: Missing any required permission', {
          userId: req.user.userId,
          requiredPermissions: permissions,
          userPermissions: req.user.permissions,
        })

        return res.status(403).json({
          error: 'Forbidden',
          message: 'Insufficient permissions to perform this action',
          code: 'INSUFFICIENT_PERMISSIONS',
          requiredPermissions: permissions,
          userPermissions: req.user.permissions,
        })
      }

      next()
    }
  }

  /**
   * Middleware to require all of the specified permissions
   */
  requireAllPermissions(permissions: Permission[]) {
    return (req: Request, res: Response, next: NextFunction) => {
      if (!req.user) {
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'Authentication required',
          code: 'AUTH_REQUIRED',
        })
      }

      const hasAll = permissionService.hasAllPermissions(
        req.user.permissions as Permission[],
        permissions
      )

      if (!hasAll) {
        logger.warn('Authorization denied: Missing required permissions', {
          userId: req.user.userId,
          requiredPermissions: permissions,
          userPermissions: req.user.permissions,
        })

        return res.status(403).json({
          error: 'Forbidden',
          message: 'Insufficient permissions to perform this action',
          code: 'INSUFFICIENT_PERMISSIONS',
          requiredPermissions: permissions,
          userPermissions: req.user.permissions,
        })
      }

      next()
    }
  }
}
