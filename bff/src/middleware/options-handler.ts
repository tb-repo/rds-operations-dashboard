/**
 * Enhanced OPTIONS Request Handler Middleware
 * 
 * Ensures all API routes properly support OPTIONS method for CORS preflight requests.
 * Provides comprehensive CORS headers and validation for preflight requests.
 */

import { Request, Response, NextFunction } from 'express'
import { logger } from '../utils/logger'

export interface OptionsHandlerConfig {
  allowedOrigins: string[]
  allowedMethods: string[]
  allowedHeaders: string[]
  exposedHeaders: string[]
  maxAge: number
  credentials: boolean
}

/**
 * Creates an OPTIONS request handler middleware
 */
export const createOptionsHandler = (config: OptionsHandlerConfig) => {
  return (req: Request, res: Response, next: NextFunction) => {
    // Only handle OPTIONS requests
    if (req.method !== 'OPTIONS') {
      return next()
    }

    const origin = req.get('Origin')
    const requestMethod = req.get('Access-Control-Request-Method')
    const requestHeaders = req.get('Access-Control-Request-Headers')

    logger.debug('Handling OPTIONS preflight request', {
      origin,
      requestMethod,
      requestHeaders,
      path: req.path
    })

    // Validate origin if present
    if (origin) {
      if (!config.allowedOrigins.includes(origin)) {
        logger.warn('OPTIONS request blocked: unauthorized origin', { 
          origin, 
          allowedOrigins: config.allowedOrigins 
        })
        return res.status(403).json({ error: 'Origin not allowed' })
      }
      res.header('Access-Control-Allow-Origin', origin)
    }

    // Validate requested method
    if (requestMethod) {
      if (!config.allowedMethods.includes(requestMethod.toUpperCase())) {
        logger.warn('OPTIONS request blocked: unsupported method', { 
          requestMethod, 
          allowedMethods: config.allowedMethods 
        })
        return res.status(405).json({ error: 'Method not allowed' })
      }
    }

    // Set CORS headers
    res.header('Access-Control-Allow-Methods', config.allowedMethods.join(', '))
    res.header('Access-Control-Allow-Headers', config.allowedHeaders.join(', '))
    res.header('Access-Control-Expose-Headers', config.exposedHeaders.join(', '))
    res.header('Access-Control-Max-Age', config.maxAge.toString())
    
    if (config.credentials) {
      res.header('Access-Control-Allow-Credentials', 'true')
    }

    // Additional security headers for OPTIONS responses
    res.header('Vary', 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers')
    res.header('Cache-Control', 'no-cache, no-store, must-revalidate')

    logger.debug('OPTIONS preflight request handled successfully', {
      origin,
      requestMethod,
      path: req.path,
      maxAge: config.maxAge
    })

    // Return successful preflight response
    res.status(200).end()
  }
}

/**
 * Middleware to add CORS headers to all responses (not just OPTIONS)
 */
export const addCorsHeaders = (config: OptionsHandlerConfig) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const origin = req.get('Origin')

    // Add CORS headers to all responses if origin is allowed
    if (origin && config.allowedOrigins.includes(origin)) {
      res.header('Access-Control-Allow-Origin', origin)
      res.header('Access-Control-Expose-Headers', config.exposedHeaders.join(', '))
      
      if (config.credentials) {
        res.header('Access-Control-Allow-Credentials', 'true')
      }
    }

    next()
  }
}

/**
 * Comprehensive OPTIONS route handler for catch-all routes
 */
export const handleAllOptions = (config: OptionsHandlerConfig) => {
  return (req: Request, res: Response) => {
    const origin = req.get('Origin')

    logger.info('Handling catch-all OPTIONS request', {
      origin,
      path: req.path,
      method: req.method
    })

    // Set comprehensive CORS headers
    if (origin && config.allowedOrigins.includes(origin)) {
      res.header('Access-Control-Allow-Origin', origin)
    }

    res.header('Access-Control-Allow-Methods', config.allowedMethods.join(', '))
    res.header('Access-Control-Allow-Headers', config.allowedHeaders.join(', '))
    res.header('Access-Control-Expose-Headers', config.exposedHeaders.join(', '))
    res.header('Access-Control-Max-Age', config.maxAge.toString())
    
    if (config.credentials) {
      res.header('Access-Control-Allow-Credentials', 'true')
    }

    res.header('Vary', 'Origin')
    res.status(200).json({
      message: 'CORS preflight successful',
      allowedMethods: config.allowedMethods,
      allowedHeaders: config.allowedHeaders,
      maxAge: config.maxAge
    })
  }
}