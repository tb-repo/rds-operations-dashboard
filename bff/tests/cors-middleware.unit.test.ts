/**
 * Unit Tests for CORS Middleware Configuration
 * 
 * Tests middleware initialization with different configurations, origin validation logic,
 * and header generation for valid requests.
 */

import { initializeCorsConfig } from '../src/config/cors'
import { OriginValidator } from '../src/security/origin-validator'
import { logger } from '../src/utils/logger'

// Mock dependencies
jest.mock('../src/utils/logger', () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    debug: jest.fn()
  }
}))

jest.mock('../src/security/origin-validator')

describe('CORS Middleware Unit Tests', () => {
  const originalEnv = process.env
  let mockOriginValidator: jest.Mocked<OriginValidator>

  beforeEach(() => {
    // Reset environment variables
    process.env = { ...originalEnv }
    delete process.env.CORS_ORIGINS
    delete process.env.FRONTEND_URL
    delete process.env.NODE_ENV
    
    // Reset mocks
    jest.clearAllMocks()
    
    // Create mock OriginValidator
    mockOriginValidator = {
      validateOrigin: jest.fn(),
      getRecentSecurityEvents: jest.fn(),
      getSecurityStats: jest.fn(),
      updateAllowedOrigins: jest.fn()
    } as any
    
    ;(OriginValidator as jest.MockedClass<typeof OriginValidator>).mockImplementation(() => mockOriginValidator)
  })

  afterAll(() => {
    process.env = originalEnv
  })

  describe('Middleware Initialization', () => {
    test('should initialize middleware with single origin', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config).toHaveProperty('allowedOrigins')
      expect(config).toHaveProperty('corsOptions')
      expect(config).toHaveProperty('originValidator')
      expect(config.allowedOrigins).toEqual(['https://example.com'])
    })

    test('should initialize middleware with multiple origins', () => {
      process.env.CORS_ORIGINS = 'https://example.com,https://app.example.com,http://localhost:3000'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://example.com',
        'https://app.example.com',
        'http://localhost:3000'
      ])
      expect(OriginValidator).toHaveBeenCalledWith([
        'https://example.com',
        'https://app.example.com',
        'http://localhost:3000'
      ])
    })

    test('should initialize middleware with development defaults', () => {
      process.env.NODE_ENV = 'development'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://d2qvaswtmn22om.cloudfront.net'
      ])
    })

    test('should initialize middleware with production defaults', () => {
      process.env.NODE_ENV = 'production'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual(['https://d2qvaswtmn22om.cloudfront.net'])
    })

    test('should initialize middleware with staging defaults', () => {
      process.env.NODE_ENV = 'staging'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://staging-d2qvaswtmn22om.cloudfront.net',
        'http://localhost:3000',
        'http://localhost:5173'
      ])
    })
  })

  describe('Origin Validation Logic', () => {
    test('should validate allowed origin correctly', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: true,
        reason: 'Origin in allowlist'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Test the origin validation function
      const originFunction = config.corsOptions.origin as Function
      originFunction('https://example.com', callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith('https://example.com')
      expect(callback).toHaveBeenCalledWith(null, true)
    })

    test('should reject disallowed origin correctly', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: false,
        reason: 'Origin not in allowlist'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Test the origin validation function
      const originFunction = config.corsOptions.origin as Function
      originFunction('https://malicious.com', callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith('https://malicious.com')
      expect(callback).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'CORS: Origin not in allowlist'
        }),
        false
      )
    })

    test('should handle null origin (server-to-server requests)', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: true,
        reason: 'No origin header (server-to-server or mobile app)'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Test with null origin
      const originFunction = config.corsOptions.origin as Function
      originFunction(null, callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith(null)
      expect(callback).toHaveBeenCalledWith(null, true)
    })

    test('should handle undefined origin', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: true,
        reason: 'No origin header (server-to-server or mobile app)'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Test with undefined origin
      const originFunction = config.corsOptions.origin as Function
      originFunction(undefined, callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith(undefined)
      expect(callback).toHaveBeenCalledWith(null, true)
    })

    test('should pass validation result reason in error message', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: false,
        reason: 'Invalid origin format'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      const originFunction = config.corsOptions.origin as Function
      originFunction('invalid-origin', callback)
      
      expect(callback).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'CORS: Invalid origin format'
        }),
        false
      )
    })
  })

  describe('Header Generation', () => {
    test('should configure correct allowed methods', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.methods).toEqual([
        'GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH', 'HEAD'
      ])
    })

    test('should configure correct allowed headers', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.allowedHeaders).toEqual([
        'Content-Type',
        'Authorization',
        'X-Api-Key',
        'X-Amz-Date',
        'X-Amz-Security-Token',
        'X-Requested-With',
        'Accept',
        'Origin',
        'Cache-Control'
      ])
    })

    test('should configure correct exposed headers', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.exposedHeaders).toEqual([
        'X-Total-Count',
        'X-Request-ID',
        'X-RateLimit-Limit',
        'X-RateLimit-Remaining',
        'X-RateLimit-Reset'
      ])
    })

    test('should enable credentials for authenticated requests', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.credentials).toBe(true)
    })

    test('should set correct preflight cache duration', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.maxAge).toBe(86400) // 24 hours
    })

    test('should set correct OPTIONS success status', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.optionsSuccessStatus).toBe(200)
    })

    test('should disable preflight continue', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions.preflightContinue).toBe(false)
    })
  })

  describe('Configuration Validation', () => {
    test('should validate configuration with valid HTTPS origins', () => {
      process.env.CORS_ORIGINS = 'https://example.com,https://app.example.com'
      
      expect(() => initializeCorsConfig()).not.toThrow()
      expect(logger.info).toHaveBeenCalledWith(
        'CORS configuration validated successfully',
        expect.objectContaining({
          origins: ['https://example.com', 'https://app.example.com'],
          totalOrigins: 2
        })
      )
    })

    test('should validate configuration with mixed HTTP/HTTPS origins', () => {
      process.env.CORS_ORIGINS = 'https://example.com,http://localhost:3000'
      
      expect(() => initializeCorsConfig()).not.toThrow()
    })

    test('should reject configuration with invalid origins', () => {
      process.env.CORS_ORIGINS = 'invalid-url,https://valid.com'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - invalid-url')
    })

    test('should reject configuration with unsupported protocols', () => {
      process.env.CORS_ORIGINS = 'ftp://example.com,https://valid.com'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - ftp://example.com')
    })

    test('should reject empty configuration', () => {
      process.env.CORS_ORIGINS = ','
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: No origins specified')
    })

    test('should fall back to environment defaults when CORS_ORIGINS is empty string', () => {
      process.env.CORS_ORIGINS = ''
      process.env.NODE_ENV = 'development'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://d2qvaswtmn22om.cloudfront.net'
      ])
    })
  })

  describe('Environment-Specific Configuration', () => {
    test('should use custom FRONTEND_URL in production', () => {
      process.env.NODE_ENV = 'production'
      process.env.FRONTEND_URL = 'https://custom-production.example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual(['https://custom-production.example.com'])
    })

    test('should include FRONTEND_URL in staging along with defaults', () => {
      process.env.NODE_ENV = 'staging'
      process.env.FRONTEND_URL = 'https://custom-staging.example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://custom-staging.example.com',
        'http://localhost:3000',
        'http://localhost:5173'
      ])
    })

    test('should include FRONTEND_URL in development along with defaults', () => {
      process.env.NODE_ENV = 'development'
      process.env.FRONTEND_URL = 'https://custom-dev.example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://custom-dev.example.com'
      ])
    })

    test('should filter out undefined FRONTEND_URL', () => {
      process.env.NODE_ENV = 'development'
      // FRONTEND_URL is undefined
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://d2qvaswtmn22om.cloudfront.net'
      ])
    })
  })

  describe('Error Handling and Logging', () => {
    test('should log initialization success with configuration details', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      initializeCorsConfig()
      
      expect(logger.info).toHaveBeenCalledWith(
        'CORS configuration initialized successfully',
        expect.objectContaining({
          allowedOrigins: ['https://example.com'],
          nodeEnv: 'development',
          credentialsEnabled: true,
          maxAge: 86400
        })
      )
    })

    test('should log error with environment context on failure', () => {
      process.env.NODE_ENV = 'production'
      process.env.FRONTEND_URL = 'https://frontend.com'
      process.env.CORS_ORIGINS = 'invalid-url'
      
      expect(() => initializeCorsConfig()).toThrow()
      expect(logger.error).toHaveBeenCalledWith(
        'Failed to initialize CORS configuration',
        expect.objectContaining({
          error: expect.stringContaining('Invalid origins'),
          nodeEnv: 'production',
          frontendUrl: 'https://frontend.com',
          corsOrigins: 'invalid-url'
        })
      )
    })

    test('should rethrow configuration errors', () => {
      process.env.CORS_ORIGINS = 'invalid-url'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - invalid-url')
    })
  })

  describe('OriginValidator Integration', () => {
    test('should create OriginValidator with correct origins', () => {
      const origins = ['https://example.com', 'https://app.example.com']
      process.env.CORS_ORIGINS = origins.join(',')
      
      const config = initializeCorsConfig()
      
      expect(OriginValidator).toHaveBeenCalledWith(origins)
      expect(config.originValidator).toBe(mockOriginValidator)
    })

    test('should pass origin validation requests to OriginValidator', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({
        allowed: true,
        reason: 'Origin in allowlist'
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      const originFunction = config.corsOptions.origin as Function
      originFunction('https://example.com', callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith('https://example.com')
    })
  })
})