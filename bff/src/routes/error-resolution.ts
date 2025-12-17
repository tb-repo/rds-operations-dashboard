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

export function createErrorResolutionRoutes(
  internalApiUrl: string,
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

      // Call error resolution monitoring endpoint
      const response = await axios.get(
        `${internalApiUrl}/error-resolution/dashboard`,
        {
          headers: { 'x-api-key': getApiKey() },
          params: { widgets: widgets?.join(',') },
        }
      )

      logger.info('Error dashboard data fetched', {
        userId: req.user?.userId,
        email: req.user?.email,
        widgets: widgets?.length || 'all',
      })

      res.json(response.data)
    } catch (error: any) {
      logger.error('Error fetching error dashboard data', {
        error: error.message,
        userId: req.user?.userId,
      })
      res.status(500).json({
        error: 'Failed to fetch error dashboard data',
        message: error.response?.data?.message || error.message,
      })
    }
  })

  /**
   * GET /api/errors/statistics - Get error detection statistics
   * Permission: view_metrics
   */
  router.get('/statistics', async (req: Request, res: Response) => {
    try {
      const response = await axios.get(
        `${internalApiUrl}/error-resolution/statistics`,
        {
          headers: { 'x-api-key': getApiKey() },
        }
      )

      res.json(response.data)
    } catch (error: any) {
      logger.error('Error fetching error statistics', {
        error: error.message,
        userId: req.user?.userId,
      })
      res.status(500).json({
        error: 'Failed to fetch error statistics',
        message: error.response?.data?.message || error.message,
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

      const response = await axios.post(
        `${internalApiUrl}/error-resolution/detect`,
        requestBody,
        {
          headers: { 
            'x-api-key': getApiKey(),
            'Content-Type': 'application/json',
          },
        }
      )

      logger.info('Error detection requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        errorId: response.data.error_id,
        service: req.body.service,
        statusCode: req.body.status_code,
      })

      auditService.logOperationEvent(
        'ERROR_DETECTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `error:${response.data.error_id}`,
        'detect',
        'success',
        undefined,
        {
          errorId: response.data.error_id,
          service: req.body.service,
          endpoint: req.body.endpoint,
          statusCode: req.body.status_code,
          category: response.data.category,
          severity: response.data.severity,
        }
      )

      res.json(response.data)
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

      const response = await axios.post(
        `${internalApiUrl}/error-resolution/resolve`,
        requestBody,
        {
          headers: { 
            'x-api-key': getApiKey(),
            'Content-Type': 'application/json',
          },
        }
      )

      logger.info('Error resolution requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        errorId: req.body.error_id,
        strategy: req.body.resolution_strategy,
        attemptId: response.data.attempt_id,
      })

      auditService.logOperationEvent(
        'ERROR_RESOLUTION',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `error:${req.body.error_id}`,
        'resolve',
        response.data.success ? 'success' : 'failure',
        undefined,
        {
          errorId: req.body.error_id,
          attemptId: response.data.attempt_id,
          strategy: response.data.strategy,
          success: response.data.success,
        }
      )

      res.json(response.data)
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
      const response = await axios.post(
        `${internalApiUrl}/error-resolution/rollback`,
        req.body,
        {
          headers: { 
            'x-api-key': getApiKey(),
            'Content-Type': 'application/json',
          },
        }
      )

      logger.info('Error resolution rollback requested', {
        userId: req.user?.userId,
        email: req.user?.email,
        attemptId: req.body.attempt_id,
        success: response.data.rollback_success,
      })

      auditService.logOperationEvent(
        'ERROR_ROLLBACK',
        req.user?.userId || 'unknown',
        req.user?.email || 'unknown',
        req.ip || 'unknown',
        req.get('user-agent') || 'unknown',
        `attempt:${req.body.attempt_id}`,
        'rollback',
        response.data.rollback_success ? 'success' : 'failure',
        undefined,
        {
          attemptId: req.body.attempt_id,
          success: response.data.rollback_success,
        }
      )

      res.json(response.data)
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
      const response = await axios.get(
        `${internalApiUrl}/error-resolution/attempts/${req.params.attemptId}`,
        {
          headers: { 'x-api-key': getApiKey() },
        }
      )

      res.json(response.data)
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
      const response = await axios.get(
        `${internalApiUrl}/error-resolution/health`,
        {
          headers: { 'x-api-key': getApiKey() },
        }
      )

      res.json(response.data)
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