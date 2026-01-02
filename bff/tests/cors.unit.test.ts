/**
 * Unit Tests for CORS Configuration Module
 * 
 * Tests CORS middleware configuration with various origins, environment variable parsing,
 * validation logic, and error handling for invalid configurations.
 */

import { initializeCorsConfig, getCorsConfigInfo } from '../src/config/cors'
import { OriginValidator } from '../src/security/origin-validator'
import { logger } from '../src/utils/logger'

// Mock logger to prevent console output during tests
jest.mock('../src/utils/logger', () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
    debug: jest.fn()
  }
}))

// Mock OriginValidator
jest.mock('../src/security/origin-validator')

describe('CORS Configuration Unit Tests', () => {
  const originalEnv = process.env
  const mockOriginValidator = {
    validateOrigin: jest.fn()
  }

  beforeEach(() => {
    // Reset environment variables
    process.env = { ...originalEnv }
    delete process.env.CORS_ORIGINS
    delete process.env.FRONTEND_URL
    delete process.env.NODE_ENV
    
    // Reset mocks
    jest.clearAllMocks()
    ;(OriginValidator as jest.MockedClass<typeof OriginValidator>).mockImplementation(() => mockOriginValidator as any)
  })

  afterAll(() => {
    process.env = originalEnv
  })

  describe('Environment Variable Parsing', () => {
    test('should parse CORS_ORIGINS environment variable correctly', () => {
      process.env.CORS_ORIGINS = 'https://example.com,https://app.example.com,http://localhost:3000'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://example.com',
        'https://app.example.com',
        'http://localhost:3000'
      ])
      expect(logger.info).toHaveBeenCalledWith(
        'Using CORS origins from CORS_ORIGINS environment variable',
        { origins: ['https://example.com', 'https://app.example.com', 'http://localhost:3000'] }
      )
    })

    test('should handle CORS_ORIGINS with extra whitespace', () => {
      process.env.CORS_ORIGINS = ' https://example.com , https://app.example.com , http://localhost:3000 '
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://example.com',
        'https://app.example.com',
        'http://localhost:3000'
      ])
    })

    test('should filter out empty origins from CORS_ORIGINS', () => {
      process.env.CORS_ORIGINS = 'https://example.com,,https://app.example.com,'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://example.com',
        'https://app.example.com'
      ])
    })

    test('should use production defaults when NODE_ENV is production', () => {
      process.env.NODE_ENV = 'production'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual(['https://d2qvaswtmn22om.cloudfront.net'])
      expect(logger.info).toHaveBeenCalledWith(
        'Using production CORS origins',
        { origins: ['https://d2qvaswtmn22om.cloudfront.net'] }
      )
    })

    test('should use FRONTEND_URL in production when provided', () => {
      process.env.NODE_ENV = 'production'
      process.env.FRONTEND_URL = 'https://custom-frontend.example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual(['https://custom-frontend.example.com'])
    })

    test('should use staging defaults when NODE_ENV is staging', () => {
      process.env.NODE_ENV = 'staging'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'https://staging-d2qvaswtmn22om.cloudfront.net',
        'http://localhost:3000',
        'http://localhost:5173'
      ])
    })

    test('should use development defaults when NODE_ENV is development', () => {
      process.env.NODE_ENV = 'development'
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://d2qvaswtmn22om.cloudfront.net'
      ])
    })

    test('should use development defaults when NODE_ENV is not set', () => {
      // NODE_ENV is already undefined from beforeEach
      
      const config = initializeCorsConfig()
      
      expect(config.allowedOrigins).toEqual([
        'http://localhost:3000',
        'http://localhost:5173',
        'http://localhost:8080',
        'https://d2qvaswtmn22om.cloudfront.net'
      ])
    })
  })

  describe('Configuration Validation', () => {
    test('should validate valid HTTPS origins', () => {
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

    test('should validate valid HTTP origins for development', () => {
      process.env.CORS_ORIGINS = 'http://localhost:3000,http://localhost:5173'
      
      expect(() => initializeCorsConfig()).not.toThrow()
    })

    test('should throw error for empty origins configuration', () => {
      process.env.CORS_ORIGINS = ','
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: No origins specified')
      expect(logger.error).toHaveBeenCalledWith('No CORS origins configured')
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

    test('should throw error for invalid origin URLs', () => {
      process.env.CORS_ORIGINS = 'invalid-url,https://valid.com'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - invalid-url')
      expect(logger.error).toHaveBeenCalledWith(
        'Invalid CORS origins configured',
        { invalidOrigins: ['invalid-url'] }
      )
    })

    test('should throw error for unsupported protocols', () => {
      process.env.CORS_ORIGINS = 'ftp://example.com,https://valid.com'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - ftp://example.com')
    })

    test('should throw error for multiple invalid origins', () => {
      process.env.CORS_ORIGINS = 'invalid-url,ftp://example.com,javascript:alert(1)'
      
      expect(() => initializeCorsConfig()).toThrow('CORS configuration error: Invalid origins - invalid-url, ftp://example.com, javascript:alert(1)')
    })
  })

  describe('CORS Options Configuration', () => {
    test('should create CORS options with correct settings', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.corsOptions).toMatchObject({
        credentials: true,
        optionsSuccessStatus: 200,
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH', 'HEAD'],
        maxAge: 86400,
        preflightContinue: false
      })
    })

    test('should include correct allowed headers', () => {
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

    test('should include correct exposed headers', () => {
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

    test('should create OriginValidator with correct origins', () => {
      process.env.CORS_ORIGINS = 'https://example.com,https://app.example.com'
      
      const config = initializeCorsConfig()
      
      expect(OriginValidator).toHaveBeenCalledWith(['https://example.com', 'https://app.example.com'])
      expect(config.originValidator).toBe(mockOriginValidator)
    })
  })

  describe('Origin Validation Function', () => {
    test('should allow valid origin through callback', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({ allowed: true, reason: 'Origin in allowlist' })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Call the origin function
      ;(config.corsOptions.origin as Function)('https://example.com', callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith('https://example.com')
      expect(callback).toHaveBeenCalledWith(null, true)
    })

    test('should reject invalid origin through callback', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({ 
        allowed: false, 
        reason: 'Origin not allowed' 
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Call the origin function
      ;(config.corsOptions.origin as Function)('https://malicious.com', callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith('https://malicious.com')
      expect(callback).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'CORS: Origin not allowed'
        }),
        false
      )
    })

    test('should handle undefined origin', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      mockOriginValidator.validateOrigin.mockReturnValue({ 
        allowed: true, 
        reason: 'No origin header' 
      })
      
      const config = initializeCorsConfig()
      const callback = jest.fn()
      
      // Call the origin function with undefined
      ;(config.corsOptions.origin as Function)(undefined, callback)
      
      expect(mockOriginValidator.validateOrigin).toHaveBeenCalledWith(undefined)
      expect(callback).toHaveBeenCalledWith(null, true)
    })
  })

  describe('Error Handling', () => {
    test('should log error and rethrow when configuration fails', () => {
      process.env.CORS_ORIGINS = 'invalid-url'
      
      expect(() => initializeCorsConfig()).toThrow()
      expect(logger.error).toHaveBeenCalledWith(
        'Failed to initialize CORS configuration',
        expect.objectContaining({
          error: expect.stringContaining('Invalid origins'),
          nodeEnv: undefined,
          frontendUrl: undefined,
          corsOrigins: 'invalid-url'
        })
      )
    })

    test('should include environment context in error logs', () => {
      process.env.NODE_ENV = 'production'
      process.env.FRONTEND_URL = 'https://frontend.com'
      process.env.CORS_ORIGINS = 'invalid-url'
      
      expect(() => initializeCorsConfig()).toThrow()
      expect(logger.error).toHaveBeenCalledWith(
        'Failed to initialize CORS configuration',
        expect.objectContaining({
          nodeEnv: 'production',
          frontendUrl: 'https://frontend.com',
          corsOrigins: 'invalid-url'
        })
      )
    })
  })

  describe('getCorsConfigInfo', () => {
    test('should return current configuration info', () => {
      process.env.NODE_ENV = 'production'
      process.env.CORS_ORIGINS = 'https://example.com,https://app.example.com'
      
      const info = getCorsConfigInfo()
      
      expect(info).toEqual({
        origins: ['https://example.com', 'https://app.example.com'],
        environment: 'production'
      })
    })

    test('should return development as default environment', () => {
      // NODE_ENV is undefined
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const info = getCorsConfigInfo()
      
      expect(info.environment).toBe('development')
    })
  })

  describe('Integration with OriginValidator', () => {
    test('should pass correct parameters to OriginValidator constructor', () => {
      const origins = ['https://example.com', 'https://app.example.com']
      process.env.CORS_ORIGINS = origins.join(',')
      
      initializeCorsConfig()
      
      expect(OriginValidator).toHaveBeenCalledWith(origins)
    })

    test('should return OriginValidator instance in config', () => {
      process.env.CORS_ORIGINS = 'https://example.com'
      
      const config = initializeCorsConfig()
      
      expect(config.originValidator).toBe(mockOriginValidator)
    })
  })

  describe('Logging Behavior', () => {
    test('should log successful initialization', () => {
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

    test('should log environment-specific origin selection', () => {
      process.env.NODE_ENV = 'staging'
      
      initializeCorsConfig()
      
      expect(logger.info).toHaveBeenCalledWith(
        'Using staging CORS origins',
        expect.objectContaining({
          origins: expect.arrayContaining([
            'https://staging-d2qvaswtmn22om.cloudfront.net',
            'http://localhost:3000',
            'http://localhost:5173'
          ])
        })
      )
    })
  })
})