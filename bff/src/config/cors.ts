/**
 * Production-Only CORS Configuration Module
 * 
 * Provides production-only CORS configuration with enhanced security.
 * Supports only production CloudFront origin for maximum security.
 */

import { CorsOptions } from 'cors'
import { logger } from '../utils/logger'
import { OriginValidator } from '../security/origin-validator'

export interface CorsConfig {
  allowedOrigins: string[]
  corsOptions: CorsOptions
  originValidator: OriginValidator
}

/**
 * Validates if an origin URL is properly formatted and uses allowed protocols
 */
const isValidOrigin = (origin: string): boolean => {
  try {
    const url = new URL(origin)
    // Only allow HTTPS protocol for production security
    return url.protocol === 'https:'
  } catch {
    return false
  }
}

/**
 * Gets CORS origins for production-only configuration
 */
const getCorsOrigins = (): string[] => {
  // Production-only: Use CORS_ORIGINS environment variable or default to CloudFront
  const corsOrigins = process.env.CORS_ORIGINS
  if (corsOrigins) {
    const origins = corsOrigins.split(',').map(origin => origin.trim()).filter(Boolean)
    logger.info('Using CORS origins from CORS_ORIGINS environment variable', { origins })
    return origins
  }
  
  // Production-only default: CloudFront origin only
  const productionOrigin = 'https://d2qvaswtmn22om.cloudfront.net'
  logger.info('Using production-only CORS origin', { origins: [productionOrigin] })
  return [productionOrigin]
}

/**
 * Validates CORS configuration at startup
 */
const validateCorsConfiguration = (origins: string[]): void => {
  if (origins.length === 0) {
    logger.error('No CORS origins configured')
    throw new Error('CORS configuration error: No origins specified')
  }
  
  const invalidOrigins = origins.filter(origin => !isValidOrigin(origin))
  if (invalidOrigins.length > 0) {
    logger.error('Invalid CORS origins configured - only HTTPS origins allowed in production', { invalidOrigins })
    throw new Error(`CORS configuration error: Invalid origins (only HTTPS allowed) - ${invalidOrigins.join(', ')}`)
  }
  
  // Production security check: ensure no localhost or development origins
  const developmentOrigins = origins.filter(origin => 
    origin.includes('localhost') || 
    origin.includes('127.0.0.1') || 
    origin.startsWith('http://') ||
    origin.includes('staging')
  )
  
  if (developmentOrigins.length > 0) {
    logger.error('Development/staging origins detected in production configuration', { developmentOrigins })
    throw new Error(`CORS security error: Development origins not allowed in production - ${developmentOrigins.join(', ')}`)
  }
  
  logger.info('Production-only CORS configuration validated successfully', { 
    origins, 
    nodeEnv: process.env.NODE_ENV || 'production',
    totalOrigins: origins.length,
    securityLevel: 'production-only'
  })
}

/**
 * Creates production-only CORS options with enhanced security
 */
const createCorsOptions = (allowedOrigins: string[]): { corsOptions: CorsOptions, originValidator: OriginValidator } => {
  const originValidator = new OriginValidator(allowedOrigins)
  
  const corsOptions: CorsOptions = {
    origin: (origin: string | undefined, callback: (err: Error | null, allow?: boolean) => void) => {
      // Use enhanced origin validator with production-only security
      const validation = originValidator.validateOrigin(origin)
      
      if (validation.allowed) {
        callback(null, true)
      } else {
        // Log security violations for production monitoring
        logger.warn('CORS origin rejected in production', {
          origin,
          reason: validation.reason,
          timestamp: new Date().toISOString()
        })
        
        const error = new Error(`CORS: ${validation.reason}`)
        callback(error, false)
      }
    },
    
    // Enable credentials for authenticated requests
    credentials: true,
    
    // Successful OPTIONS response status
    optionsSuccessStatus: 200,
    
    // Allowed HTTP methods
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH', 'HEAD'],
    
    // Allowed request headers
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
    
    // Headers exposed to the client
    exposedHeaders: [
      'X-Total-Count',
      'X-Request-ID',
      'X-RateLimit-Limit',
      'X-RateLimit-Remaining',
      'X-RateLimit-Reset'
    ],
    
    // Preflight cache duration (24 hours)
    maxAge: 86400,
    
    // Handle preflight requests for all routes
    preflightContinue: false
  }
  
  return { corsOptions, originValidator }
}

/**
 * Initializes and returns production-only CORS configuration
 */
export const initializeCorsConfig = (): CorsConfig => {
  try {
    // Get production-only origins
    const allowedOrigins = getCorsOrigins()
    
    // Validate production-only configuration
    validateCorsConfiguration(allowedOrigins)
    
    // Create CORS options with production-only security
    const { corsOptions, originValidator } = createCorsOptions(allowedOrigins)
    
    logger.info('Production-only CORS configuration initialized successfully', {
      allowedOrigins,
      nodeEnv: process.env.NODE_ENV || 'production',
      credentialsEnabled: corsOptions.credentials,
      maxAge: corsOptions.maxAge,
      securityLevel: 'production-only',
      httpsOnly: true
    })
    
    return {
      allowedOrigins,
      corsOptions,
      originValidator
    }
    
  } catch (error: any) {
    logger.error('Failed to initialize production-only CORS configuration', { 
      error: error.message,
      nodeEnv: process.env.NODE_ENV,
      corsOrigins: process.env.CORS_ORIGINS
    })
    throw error
  }
}

/**
 * Gets current CORS configuration for debugging/monitoring
 */
export const getCorsConfigInfo = (): { origins: string[], environment: string, securityLevel: string } => {
  return {
    origins: getCorsOrigins(),
    environment: process.env.NODE_ENV || 'production',
    securityLevel: 'production-only'
  }
}