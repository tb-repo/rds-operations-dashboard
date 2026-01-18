/**
 * Error Resolution API Routes
 * 
 * Provides BFF endpoints for the error resolution and monitoring system.
 * Integrates with the error resolution Lambda functions.
 * 
 * Metadata:
 * {
 *   "generated_by": "claude-3.5-sonnet",
 *   "timestamp": "2025-12-16T14:30:00Z",
 *   "version": "1.0.0",
 *   "policy_version": "v1.0.0",
 *   "traceability": "REQ-6.1, 6.2 → DESIGN-Integration → TASK-7",
 *   "review_status": "Pending",
 *   "risk_level": "Level 2",
 *   "reviewed_by": null,
 *   "approved_by": null
 * }
 */

import { Router, Request, Response } from 'express'
import axios from 'axios'
import { logger } from '../utils/logger'
import { auditService } from '../services/audit'
import { ServiceDiscovery } from '../services/service-discovery'

export function createErrorResolutionRoutes(
  serviceDiscovery: ServiceDiscovery,
  getApiKey: () => string
): Router {
  const router = Router()

  /**
   * GET /api/errors/dashboard - Get error monitoring dashboard data
   * Permission: view_metrics
   */
  router.get('/dashboard', async (req: Request, res: Response) => {
    try {
      const widgetIds = req.query.widgets as string | undefined
      const widgets = widgetIds ? widgetIds.split(',') : undefined

      // Call monitoring dashboard metrics endpoint with graceful fallback
      let response
      try {
        response = await serviceDiscovery.callService(
          'monitoring',
          '/dashboard/metrics',
          {
            apiKey: getApiKey(),
            params: { widgets: widgets?.join(',') },
            timeout: 3000 // Short timeout for quick fallback
          }
        )
        
        logger.info('Error dashboard data fetched', {
          userId: req.user?.userId,
          email: req.user?.email,
          widgets: widgets?.length || 'all',
        })

        return res.json(response)
      } catch (error: any) {
        // Provide fallback dashboard data
        logger.warn('Metrics endpoint unavailable, providing fallback data', {
          error: error.message,
          userId: req.user?.userId,
        })
        
        return res.json({
          status: 'fallback',
          message: 'Dashboard data temporarily unavailable',
          widgets: {
            error_metrics: {
              title: 'Error Metrics',
              data: {
                total_errors: 0,
                breakdown: {
                  by_severity: { critical: 0, high: 0, medium: 0, low: 0 },
                  by_service: {},
                  error_rates: {}
                }
              },
              status: 'unavailable'
            },
            system_health: {
              title: 'System Health',
              data: {
                indicators: {
                  total_errors: 0,
                  critical_errors: 0,
                  high_errors: 0,
                  services_affected: 0
                }
              },
              status: 'unavailable'
            }
          },
          last_updated: new Date().toISOString(),
          fallback: true
        })
      }
    } catch (error: any) {
      // Final fallback - should never reach here but just in case
      logger.error('Unexpected error in dashboard endpoint', {
        error: error.message,
        userId: req.user?.userId,
      })
      
      // Return fallback data instead of 500 error
      return res.json({
        status: 'error',
        message: 'Dashboard service encountered an error',
        fallback: true,
        widgets: {
          error_metrics: {
            title: 'Error Metrics',
            data: {
              total_errors: 0,
              breakdown: {
                by_severity: { critical: 0, high: 0, medium: 0, low: 0 },
                by_service: {},
                error_rates: {}
              }
            },
            status: 'unavailable'
          },
          system_health: {
            title: 'System Health',
            data: {
              indicators: {
                total_errors: 0,
                critical_errors: 0,
                high_errors: 0,
                services_affected: 0
              }
            },
            status: 'unavailable'
          }
        },
        last_updated: new Date().toISOString()
      })
    }
  })

  /**
   * GET /api/errors/statistics - Get error detection statistics
   * Permission: view_metrics
   * 
   * Fixed: Provide graceful fallback when monitoring service is unavailable
   */
  router.get('/statistics', async (req: Request, res: Response) => {
    try {
      // Try to get data from monitoring dashboard metrics endpoint with graceful fallback
      let response
      try {
        response = await serviceDiscovery.callService(
          'monitoring',
          '/dashboard/metrics',
          {
            apiKey: getApiKey(),
            timeout: 3000, // Short timeout for quick fallback
            params: { 
              widgets: 'error_metrics,system_health' // Request specific widgets for statistics
            }
          }
        )
        
        // Transform monitoring data to statistics format expected by frontend
        const dashboardData = response
        const errorMetrics = dashboardData?.widgets?.error_metrics
        const systemHealth = dashboardData?.widgets?.system_health

        const statisticsData = {
          status: 'available',
          statistics: {
            total_errors_detected: systemHealth?.data?.indicators?.total_errors || 0,
            detector_version: '1.0.0',
            patterns_loaded: Object.keys(errorMetrics?.data?.breakdown?.by_service || {}).length,
            critical_errors: systemHealth?.data?.indicators?.critical_errors || 0,
            high_errors: systemHealth?.data?.indicators?.high_errors || 0,
            services_affected: systemHealth?.data?.indicators?.services_affected || 0
          },
          errors_by_severity: errorMetrics?.data?.breakdown?.by_severity || {
            critical: 0,
            high: 0,
            medium: 0,
            low: 0
          },
          errors_by_service: errorMetrics?.data?.breakdown?.by_service || {},
          error_rates: errorMetrics?.data?.breakdown?.error_rates || {},
          last_updated: dashboardData?.last_updated || new Date().toISOString(),
          timestamp: new Date().toISOString()
        }

        logger.info('Error statistics fetched successfully', {
          userId: req.user?.userId,
          email: req.user?.email,
          totalErrors: statisticsData.statistics.total_errors_detected
        })

        return res.json(statisticsData)
        
      } catch (error: any) {
        // Provide graceful fallback data instead of error
        logger.warn('Error statistics endpoint unavailable, returning fallback data', {
          error: error.message,
          userId: req.user?.userId,
        })
        
        return res.json({
          status: 'unavailable',
          message: 'Error statistics service is temporarily unavailable',
          fallback: true,
          statistics: {
            total_errors_detected: 0,
            detector_version: '1.0.0',
            patterns_loaded: 0,
            critical_errors: 0,
            high_errors: 0,
            services_affected: 0
          },
          errors_by_severity: {
            critical: 0,
            high: 0,
            medium: 0,
            low: 0
          },
          errors_by_service: {},
          error_rates: {},
          timestamp: new Date().toISOString()
        })
      }
    } catch (error: any) {
      // Final fallback - should never reach here but just in case
      logger.error('Unexpected error in statistics endpoint', {
        error: error.message,
        userId: req.user?.userId,
      })
      
      // Return fallback data instead of 500 error
      return res.json({
        status: 'error',
        message: 'Error statistics service encountered an error',
        fallback: true,
        statistics: {
          total_errors_detected: 0,
          detector_version: '1.0.0',
          patterns_loaded: 0,
          critical_errors: 0,
          high_errors: 0,
          services_affected: 0
        },
        errors_by_severity: {
          critical: 0,
          high: 0,
          medium: 0,
          low: 0
        },
        errors_by_service: {},
        error_rates: {},
        timestamp: new Date().toISOString()
      })
    }
  })

  /**
   * POST /api/errors/detect - Detect and classify an error
   * Permission: execute_operations
   */
  router.post('/detect', async (req: Request, res: Response) => {
    try {
      const requestBody = {
        ...req.body,
        user_id: req.user?.userId,
        context: {
          ...req.body.context,
          user_email: req.user?.email,
          source_ip: req.ip,
          user_agent: req.get('user-agent'),
        },
      }

      const response = await serviceDiscovery.callService(
        'error-resolution',
        '/detect',
        {
          method: 'POST',
          data: requestBody,
          apiKey: getApiKey()
        }
      )

      logger.info('Error detection requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        errorId: response.error_id,
        service: req.body.service,
        statusCode: req.body.status_code,
      })

      auditService.logOperationEvent(
        'ERROR_DETECTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `error:${response.error_id}`,
        'detect',
        'success',
        undefined,
        {
          errorId: response.error_id,
          service: req.body.service,
          endpoint: req.body.endpoint,
          statusCode: req.body.status_code,
          category: response.category,
          severity: response.severity,
        }
      )

      res.json(response)
    } catch (error: any) {
      logger.error('Error in error detection', {
        error: error.message,
        userId: req.user?.userId,
        service: req.body.service,
      })

      auditService.logOperationEvent(
        'ERROR_DETECTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `service:${req.body.service}`,
        'detect',
        'failure',
        undefined,
        { error: error.message }
      )

      res.status(500).json({
        error: 'Failed to detect error',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  /**
   * POST /api/errors/resolve - Attempt to resolve an error
   * Permission: execute_operations
   */
  router.post('/resolve', async (req: Request, res: Response) => {
    try {
      const requestBody = {
        ...req.body,
        context: {
          ...req.body.context,
          user_id: req.user?.userId,
          user_email: req.user?.email,
          source_ip: req.ip,
          user_agent: req.get('user-agent'),
        },
      }

      const response = await serviceDiscovery.callService(
        'error-resolution',
        '/resolve',
        {
          method: 'POST',
          data: requestBody,
          apiKey: getApiKey()
        }
      )

      logger.info('Error resolution requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        errorId: req.body.error_id,
        strategy: req.body.resolution_strategy,
        attemptId: response.attempt_id,
      })

      auditService.logOperationEvent(
        'ERROR_RESOLUTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `error:${req.body.error_id}`,
        'resolve',
        response.success ? 'success' : 'failure',
        undefined,
        {
          errorId: req.body.error_id,
          attemptId: response.attempt_id,
          strategy: response.strategy,
          success: response.success,
        }
      )

      res.json(response)
    } catch (error: any) {
      logger.error('Error in error resolution', {
        error: error.message,
        userId: req.user?.userId,
        errorId: req.body.error_id,
      })

      auditService.logOperationEvent(
        'ERROR_RESOLUTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `error:${req.body.error_id}`,
        'resolve',
        'failure',
        undefined,
        { error: error.message }
      )

      res.status(500).json({
        error: 'Failed to resolve error',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  /**
   * POST /api/errors/rollback - Rollback a resolution attempt
   * Permission: execute_operations
   */
  router.post('/rollback', async (req: Request, res: Response) => {
    try {
      const response = await serviceDiscovery.callService(
        'error-resolution',
        '/rollback',
        {
          method: 'POST',
          data: req.body,
          apiKey: getApiKey()
        }
      )

      logger.info('Error resolution rollback requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        attemptId: req.body.attempt_id,
        success: response.rollback_success,
      })

      auditService.logOperationEvent(
        'ERROR_ROLLBACK',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `attempt:${req.body.attempt_id}`,
        'rollback',
        response.rollback_success ? 'success' : 'failure',
        undefined,
        {
          attemptId: req.body.attempt_id,
          success: response.rollback_success,
        }
      )

      res.json(response)
    } catch (error: any) {
      logger.error('Error in error resolution rollback', {
        error: error.message,
        userId: req.user?.userId,
        attemptId: req.body.attempt_id,
      })

      auditService.logOperationEvent(
        'ERROR_ROLLBACK',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `attempt:${req.body.attempt_id}`,
        'rollback',
        'failure',
        undefined,
        { error: error.message }
      )

      res.status(500).json({
        error: 'Failed to rollback resolution',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  /**
   * GET /api/errors/attempts/:attemptId - Get resolution attempt details
   * Permission: view_metrics
   */
  router.get('/attempts/:attemptId', async (req: Request, res: Response) => {
    try {
      const response = await serviceDiscovery.callService(
        'error-resolution',
        `/attempts/${req.params.attemptId}`,
        {
          apiKey: getApiKey()
        }
      )

      res.json(response)
    } catch (error: any) {
      logger.error('Error fetching resolution attempt', {
        error: error.message,
        userId: req.user?.userId,
        attemptId: req.params.attemptId,
      })
      res.status(error.response?.status || 500).json({
        error: 'Failed to fetch resolution attempt',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  /**
   * GET /api/errors/health - Get error resolution system health
   * Permission: view_metrics
   */
  router.get('/health', async (req: Request, res: Response) => {
    try {
      const response = await serviceDiscovery.callService(
        'error-resolution',
        '/health',
        {
          apiKey: getApiKey()
        }
      )

      res.json(response)
    } catch (error: any) {
      logger.error('Error fetching error resolution health', {
        error: error.message,
        userId: req.user?.userId,
      })
      res.status(error.response?.status || 500).json({
        error: 'Failed to fetch error resolution health',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  return router
}