/**
 * Property-Based Tests for CORS Configuration
 * 
 * **Feature: cors-configuration-fix, Property 1: Origin Validation**
 * **Validates: Requirements 1.1, 1.4**
 * 
 * **Feature: cors-configuration-fix, Property 2: CORS Headers Inclusion**
 * **Validates: Requirements 1.2**
 */

import * as fc from 'fast-check'
import { initializeCorsConfig } from '../src/config/cors'
import { OriginValidator } from '../src/security/origin-validator'
import { Request, Response } from 'express'

// Mock logger to avoid noise in tests
jest.mock('../src/utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  }
}))

describe('CORS Configuration Property Tests', () => {
  
  beforeEach(() => {
    // Reset environment variables for each test
    delete process.env.CORS_ORIGINS
    delete process.env.FRONTEND_URL
    process.env.NODE_ENV = 'test'
  })

  describe('Property 1: Origin Validation', () => {
    /**
     * **Feature: cors-configuration-fix, Property 1: Origin Validation**
     * **Validates: Requirements 1.1, 1.4**
     * 
     * For any valid HTTP/HTTPS origin that is in the allowed origins list,
     * the CORS origin callback should allow the request (callback with null, true)
     */
    test('should allow all valid origins in the allowed list', () => {
      fc.assert(
        fc.property(
          // Generate valid HTTP/HTTPS URLs
          fc.array(
            fc.record({
              protocol: fc.constantFrom('http:', 'https:'),
              hostname: fc.domain(),
              port: fc.option(fc.integer({ min: 1, max: 65535 }), { nil: undefined })
            }).map(({ protocol, hostname, port }) => 
              `${protocol}//${hostname}${port ? `:${port}` : ''}`
            ),
            { minLength: 1, maxLength: 5 }
          ),
          (validOrigins) => {
            // Set up environment with these origins
            process.env.CORS_ORIGINS = validOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test each valid origin
            validOrigins.forEach(origin => {
              const mockCallback = jest.fn()
              originCallback(origin, mockCallback)
              
              // Should allow the origin
              expect(mockCallback).toHaveBeenCalledWith(null, true)
            })
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for invalid origin rejection
     * For any origin not in the allowed list, should be rejected
     */
    test('should reject origins not in the allowed list', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 3 }), // allowed origins
          fc.webUrl(), // test origin (different from allowed)
          (allowedOrigins, testOrigin) => {
            // Ensure test origin is not in allowed list
            fc.pre(!allowedOrigins.includes(testOrigin))
            
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test the unauthorized origin
            const mockCallback = jest.fn()
            originCallback(testOrigin, mockCallback)
            
            // Should reject the origin
            expect(mockCallback).toHaveBeenCalledWith(
              expect.any(Error),
              false
            )
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for no-origin requests (should always be allowed)
     */
    test('should always allow requests with no origin', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 5 }),
          (allowedOrigins) => {
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test with undefined origin
            const mockCallback = jest.fn()
            originCallback(undefined, mockCallback)
            
            // Should allow requests with no origin
            expect(mockCallback).toHaveBeenCalledWith(null, true)
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for invalid URL formats (should be rejected)
     */
    test('should reject invalid URL formats', () => {
      fc.assert(
        fc.property(
          // Generate invalid URL strings
          fc.oneof(
            fc.string().filter(s => {
              try {
                new URL(s)
                return false // Valid URL, skip
              } catch {
                return s.length > 0 // Invalid URL, use it
              }
            }),
            fc.string().map(s => `ftp://${s}`), // Unsupported protocol
            fc.string().map(s => `file://${s}`), // Unsupported protocol
          ),
          (invalidOrigin) => {
            // Set up environment with valid origins
            process.env.CORS_ORIGINS = 'https://example.com'
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test the invalid origin
            const mockCallback = jest.fn()
            originCallback(invalidOrigin, mockCallback)
            
            // Should reject invalid origins
            expect(mockCallback).toHaveBeenCalledWith(
              expect.any(Error),
              false
            )
          }
        ),
        { numRuns: 50 } // Fewer runs since generating invalid URLs is complex
      )
    })
  })

  describe('Property 2: CORS Headers Inclusion', () => {
    /**
     * **Feature: cors-configuration-fix, Property 2: CORS Headers Inclusion**
     * **Validates: Requirements 1.2**
     * 
     * For any CORS configuration, the corsOptions should include all required headers
     */
    test('should include all required CORS configuration properties', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 5 }),
          (allowedOrigins) => {
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const options = corsConfig.corsOptions
            
            // Verify all required CORS properties are present
            expect(options).toHaveProperty('origin')
            expect(options).toHaveProperty('credentials', true)
            expect(options).toHaveProperty('optionsSuccessStatus', 200)
            expect(options).toHaveProperty('methods')
            expect(options).toHaveProperty('allowedHeaders')
            expect(options).toHaveProperty('exposedHeaders')
            expect(options).toHaveProperty('maxAge')
            expect(options).toHaveProperty('preflightContinue', false)
            
            // Verify methods include required HTTP methods
            const methods = options.methods as string[]
            expect(methods).toContain('GET')
            expect(methods).toContain('POST')
            expect(methods).toContain('PUT')
            expect(methods).toContain('DELETE')
            expect(methods).toContain('OPTIONS')
            
            // Verify essential headers are allowed
            const allowedHeaders = options.allowedHeaders as string[]
            expect(allowedHeaders).toContain('Content-Type')
            expect(allowedHeaders).toContain('Authorization')
            expect(allowedHeaders).toContain('X-Api-Key')
            
            // Verify credentials are enabled for authenticated requests
            expect(options.credentials).toBe(true)
            
            // Verify reasonable preflight cache duration
            expect(options.maxAge).toBeGreaterThan(0)
            expect(options.maxAge).toBeLessThanOrEqual(86400) // Max 24 hours
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for environment-specific origin configuration
     */
    test('should configure origins based on environment', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('development', 'staging', 'production'),
          fc.webUrl(),
          (nodeEnv, frontendUrl) => {
            // Set up environment
            process.env.NODE_ENV = nodeEnv
            process.env.FRONTEND_URL = frontendUrl
            delete process.env.CORS_ORIGINS // Use environment defaults
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            
            // Verify origins are configured
            expect(corsConfig.allowedOrigins).toBeInstanceOf(Array)
            expect(corsConfig.allowedOrigins.length).toBeGreaterThan(0)
            
            // Verify frontend URL is included in allowed origins
            expect(corsConfig.allowedOrigins).toContain(frontendUrl)
            
            // Environment-specific checks
            if (nodeEnv === 'development') {
              // Development should include localhost origins
              expect(corsConfig.allowedOrigins.some(origin => 
                origin.includes('localhost')
              )).toBe(true)
            }
            
            if (nodeEnv === 'production') {
              // Production should be more restrictive
              expect(corsConfig.allowedOrigins.length).toBeLessThanOrEqual(2)
            }
          }
        ),
        { numRuns: 100 }
      )
    })
  })

  describe('Configuration Validation Properties', () => {
    /**
     * Property test for configuration error handling
     */
    test('should handle invalid configuration gracefully', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.constant(''), // Empty origins
            fc.string().filter(s => s.includes('invalid-url')), // Invalid URL format
          ),
          (invalidConfig) => {
            // Set up invalid environment
            process.env.CORS_ORIGINS = invalidConfig
            
            // Should throw configuration error
            expect(() => {
              initializeCorsConfig()
            }).toThrow()
          }
        ),
        { numRuns: 50 }
      )
    })
  })

  describe('Property 3: OPTIONS Request Handling', () => {
    /**
     * **Feature: cors-configuration-fix, Property 3: OPTIONS Request Handling**
     * **Validates: Requirements 1.3**
     * 
     * For any OPTIONS request with valid origin and method, should return 200 with proper CORS headers
     */
    test('should handle OPTIONS requests with proper CORS headers', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 3 }),
          fc.webUrl(),
          fc.constantFrom('GET', 'POST', 'PUT', 'DELETE', 'PATCH'),
          (allowedOrigins, testOrigin, requestMethod) => {
            // Only test with allowed origins
            fc.pre(allowedOrigins.includes(testOrigin))
            
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const options = corsConfig.corsOptions
            
            // Simulate OPTIONS request handling
            const mockCallback = jest.fn()
            const originCallback = options.origin as Function
            
            // Test origin validation for OPTIONS
            originCallback(testOrigin, mockCallback)
            
            // Should allow the origin
            expect(mockCallback).toHaveBeenCalledWith(null, true)
            
            // Verify OPTIONS-specific configuration
            expect(options.optionsSuccessStatus).toBe(200)
            expect(options.preflightContinue).toBe(false)
            
            // Verify methods include the requested method
            const methods = options.methods as string[]
            expect(methods).toContain('OPTIONS')
            expect(methods).toContain(requestMethod)
            
            // Verify preflight cache is configured
            expect(options.maxAge).toBeGreaterThan(0)
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for OPTIONS request method validation
     */
    test('should include all required HTTP methods for OPTIONS responses', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 5 }),
          (allowedOrigins) => {
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const options = corsConfig.corsOptions
            
            // Verify all essential HTTP methods are supported
            const methods = options.methods as string[]
            const requiredMethods = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH', 'HEAD']
            
            requiredMethods.forEach(method => {
              expect(methods).toContain(method)
            })
            
            // Verify OPTIONS is always included
            expect(methods).toContain('OPTIONS')
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for preflight request headers validation
     */
    test('should support all required headers in preflight requests', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 5 }),
          (allowedOrigins) => {
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const options = corsConfig.corsOptions
            
            // Verify essential headers are allowed
            const allowedHeaders = options.allowedHeaders as string[]
            const requiredHeaders = [
              'Content-Type',
              'Authorization',
              'X-Api-Key',
              'X-Amz-Date',
              'X-Amz-Security-Token'
            ]
            
            requiredHeaders.forEach(header => {
              expect(allowedHeaders).toContain(header)
            })
            
            // Verify exposed headers are configured
            const exposedHeaders = options.exposedHeaders as string[]
            expect(exposedHeaders).toBeInstanceOf(Array)
            expect(exposedHeaders.length).toBeGreaterThan(0)
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for preflight cache configuration
     */
    test('should configure appropriate preflight cache duration', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 5 }),
          (allowedOrigins) => {
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const options = corsConfig.corsOptions
            
            // Verify maxAge is configured appropriately
            expect(options.maxAge).toBeGreaterThan(0)
            expect(options.maxAge).toBeLessThanOrEqual(86400) // Max 24 hours
            
            // Verify preflight handling is configured
            expect(options.preflightContinue).toBe(false)
            expect(options.optionsSuccessStatus).toBe(200)
          }
        ),
        { numRuns: 100 }
      )
    })
  })

  describe('Property 4: Invalid Origin Rejection', () => {
    /**
     * **Feature: cors-configuration-fix, Property 4: Invalid Origin Rejection**
     * **Validates: Requirements 1.5**
     * 
     * For any origin not in the allowed list, should be rejected with appropriate error
     */
    test('should reject all unauthorized origins with security logging', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 3 }), // allowed origins
          fc.webUrl(), // test origin (different from allowed)
          (allowedOrigins, unauthorizedOrigin) => {
            // Ensure test origin is not in allowed list
            fc.pre(!allowedOrigins.includes(unauthorizedOrigin))
            
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test the unauthorized origin
            const mockCallback = jest.fn()
            originCallback(unauthorizedOrigin, mockCallback)
            
            // Should reject the origin with error
            expect(mockCallback).toHaveBeenCalledWith(
              expect.any(Error),
              false
            )
            
            // Verify error message is descriptive
            const errorCall = mockCallback.mock.calls[0]
            const error = errorCall[0] as Error
            expect(error.message).toContain('CORS')
          }
        ),
        { numRuns: 100 }
      )
    })

    /**
     * Property test for malformed origin rejection
     */
    test('should reject malformed origins with security validation', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.string().filter(s => {
              try {
                new URL(s)
                return false // Valid URL, skip
              } catch {
                return s.length > 0 && s.length < 100 // Invalid URL, use it
              }
            }),
            fc.string().map(s => `ftp://${s}.com`), // Unsupported protocol
            fc.string().map(s => `javascript:${s}`), // Dangerous protocol
            fc.constant('not-a-url'),
            fc.constant('http://'),
            fc.constant('https://'),
          ),
          (malformedOrigin) => {
            // Set up environment with valid origins
            process.env.CORS_ORIGINS = 'https://example.com,https://test.com'
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test the malformed origin
            const mockCallback = jest.fn()
            originCallback(malformedOrigin, mockCallback)
            
            // Should reject malformed origins
            expect(mockCallback).toHaveBeenCalledWith(
              expect.any(Error),
              false
            )
            
            // Verify error indicates format issue
            const errorCall = mockCallback.mock.calls[0]
            const error = errorCall[0] as Error
            expect(error.message).toMatch(/CORS|format|Invalid/i)
          }
        ),
        { numRuns: 50 } // Fewer runs since generating invalid URLs is complex
      )
    })

    /**
     * Property test for suspicious origin detection
     */
    test('should detect and handle suspicious origin patterns', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.integer({ min: 1000, max: 65535 }).map(port => `http://localhost:${port}`), // High port localhost
            fc.tuple(fc.integer({ min: 1, max: 255 }), fc.integer({ min: 1, max: 255 }), fc.integer({ min: 1, max: 255 }), fc.integer({ min: 1, max: 255 }))
              .map(([a, b, c, d]) => `http://${a}.${b}.${c}.${d}`), // IP addresses
            fc.string().map(s => `http://example.com/<script>${s}</script>`), // Script injection attempt
          ),
          (suspiciousOrigin) => {
            // Set up environment (don't include suspicious origin in allowed list)
            process.env.CORS_ORIGINS = 'https://example.com,https://trusted.com'
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originCallback = corsConfig.corsOptions.origin as Function
            
            // Test the suspicious origin
            const mockCallback = jest.fn()
            originCallback(suspiciousOrigin, mockCallback)
            
            // Should reject suspicious origins not in allowlist
            expect(mockCallback).toHaveBeenCalledWith(
              expect.any(Error),
              false
            )
          }
        ),
        { numRuns: 50 }
      )
    })

    /**
     * Property test for security event logging
     */
    test('should log security events for rejected origins', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 3 }),
          fc.webUrl(),
          (allowedOrigins, rejectedOrigin) => {
            // Ensure rejected origin is not in allowed list
            fc.pre(!allowedOrigins.includes(rejectedOrigin))
            
            // Set up environment
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originValidator = corsConfig.originValidator
            
            // Clear any existing events
            const initialStats = originValidator.getSecurityStats()
            
            // Validate the rejected origin
            const result = originValidator.validateOrigin(rejectedOrigin)
            
            // Should be rejected
            expect(result.allowed).toBe(false)
            expect(result.reason).toBeTruthy()
            expect(result.securityEvent).toBeDefined()
            
            // Should have logged a security event
            const newStats = originValidator.getSecurityStats()
            expect(newStats.totalEvents).toBeGreaterThan(initialStats.totalEvents)
            
            // Should have recent events
            const recentEvents = originValidator.getRecentSecurityEvents(1)
            expect(recentEvents.length).toBeGreaterThan(0)
            expect(recentEvents[0].origin).toBe(rejectedOrigin)
          }
        ),
        { numRuns: 100 }
      )
    })
  })

  describe('Property 6: Error Handling and Logging', () => {
    /**
     * **Feature: cors-configuration-fix, Property 6: Error Handling and Logging**
     * **Validates: Requirements 2.5**
     * 
     * For any invalid CORS configuration, the system should log appropriate error messages
     * and use secure default configuration
     */
    test('should handle empty origins configuration with secure defaults', () => {
      fc.assert(
        fc.property(
          fc.constantFrom(''), // Only truly empty string that triggers fallback
          (emptyConfig) => {
            // Set up empty configuration that triggers fallback
            process.env.CORS_ORIGINS = emptyConfig
            process.env.NODE_ENV = 'development' // Use development which has hardcoded defaults
            process.env.FRONTEND_URL = 'https://test.example.com'
            
            // Should succeed with fallback to environment defaults
            const corsConfig = initializeCorsConfig()
            
            // Should have valid configuration with fallback origins
            expect(corsConfig.allowedOrigins).toBeInstanceOf(Array)
            expect(corsConfig.allowedOrigins.length).toBeGreaterThan(0)
            // Should include either localhost or frontend URL
            const hasValidOrigin = corsConfig.allowedOrigins.some(origin => 
              origin.includes('localhost') || origin === 'https://test.example.com'
            )
            expect(hasValidOrigin).toBe(true)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should handle undefined CORS_ORIGINS with secure defaults', () => {
      // Test when CORS_ORIGINS is not set at all
      delete process.env.CORS_ORIGINS
      process.env.NODE_ENV = 'development'
      process.env.FRONTEND_URL = 'https://test.example.com'
      
      // Should succeed with fallback to environment defaults
      const corsConfig = initializeCorsConfig()
      
      // Should have valid configuration with fallback origins
      expect(corsConfig.allowedOrigins).toBeInstanceOf(Array)
      expect(corsConfig.allowedOrigins.length).toBeGreaterThan(0)
      // Should include either localhost or frontend URL
      const hasValidOrigin = corsConfig.allowedOrigins.some(origin => 
        origin.includes('localhost') || origin === 'https://test.example.com'
      )
      expect(hasValidOrigin).toBe(true)
    })

    test('should throw error for whitespace-only CORS_ORIGINS configuration', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('   ', '\t\n', ' \t '), // Whitespace-only configurations
          (whitespaceConfig) => {
            // Set up whitespace-only configuration
            process.env.CORS_ORIGINS = whitespaceConfig
            process.env.NODE_ENV = 'development'
            
            // Should throw configuration error for whitespace-only origins
            expect(() => {
              initializeCorsConfig()
            }).toThrow(/CORS configuration error.*No origins specified/)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should throw error for comma-only CORS_ORIGINS configuration', () => {
      fc.assert(
        fc.property(
          fc.constantFrom(',,,', ', , ,', ',,'), // Comma-only configurations that result in empty arrays
          (commaConfig) => {
            // Set up comma-only configuration
            process.env.CORS_ORIGINS = commaConfig
            process.env.NODE_ENV = 'development'
            
            // Should throw configuration error for comma-only origins
            expect(() => {
              initializeCorsConfig()
            }).toThrow(/CORS configuration error.*No origins specified/)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should throw error when no valid origins can be determined', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('', '   ', '\t\n'), // Empty configurations
          (emptyConfig) => {
            // Set up environment with no valid fallbacks
            process.env.CORS_ORIGINS = emptyConfig
            process.env.NODE_ENV = 'production'
            delete process.env.FRONTEND_URL // No fallback URL
            
            // Should throw configuration error when no valid origins available
            expect(() => {
              initializeCorsConfig()
            }).toThrow(/CORS configuration error/)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should handle malformed origin URLs with proper error logging', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.string().filter(s => {
              try {
                new URL(s)
                return false // Valid URL, skip
              } catch {
                return s.length > 0 && s.length < 50 // Invalid URL, use it
              }
            }),
            fc.string().map(s => `ftp://${s}.com`), // Unsupported protocol
            fc.string().map(s => `javascript:${s}`), // Dangerous protocol
            fc.constant('not-a-url'),
            fc.constant('http://'),
            fc.constant('https://'),
            fc.constant('://missing-protocol'),
          ),
          (malformedOrigin) => {
            // Set up environment with malformed origin
            process.env.CORS_ORIGINS = `https://valid.com,${malformedOrigin},https://another-valid.com`
            
            // Should throw configuration error for invalid origins
            expect(() => {
              initializeCorsConfig()
            }).toThrow(/CORS configuration error.*Invalid origins/)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should provide detailed error information for configuration failures', () => {
      fc.assert(
        fc.property(
          fc.array(
            fc.oneof(
              fc.constant('invalid-url'),
              fc.constant('ftp://bad-protocol.com'),
              fc.constant(''),
              fc.string().filter(s => s.includes('<script>'))
            ),
            { minLength: 1, maxLength: 3 }
          ),
          (invalidOrigins) => {
            // Set up environment with all invalid origins
            process.env.CORS_ORIGINS = invalidOrigins.join(',')
            
            // Should throw with descriptive error message
            let thrownError: Error | null = null
            try {
              initializeCorsConfig()
            } catch (error) {
              thrownError = error as Error
            }
            
            expect(thrownError).not.toBeNull()
            expect(thrownError!.message).toContain('CORS configuration error')
            expect(thrownError!.message).toContain('Invalid origins')
            
            // Error message should include the invalid origins
            invalidOrigins.forEach(origin => {
              if (origin.trim()) { // Skip empty strings
                expect(thrownError!.message).toContain(origin)
              }
            })
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should handle mixed valid and invalid origins appropriately', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 2 }), // Valid origins
          fc.array(fc.constant('invalid-url'), { minLength: 1, maxLength: 2 }), // Invalid origins
          (validOrigins, invalidOrigins) => {
            // Mix valid and invalid origins
            const mixedOrigins = [...validOrigins, ...invalidOrigins]
            process.env.CORS_ORIGINS = mixedOrigins.join(',')
            
            // Should throw because of invalid origins, even if some are valid
            expect(() => {
              initializeCorsConfig()
            }).toThrow(/CORS configuration error.*Invalid origins/)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should use environment-specific fallbacks when CORS_ORIGINS is invalid', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('development', 'staging', 'production'),
          fc.webUrl(),
          (nodeEnv, frontendUrl) => {
            // Set up environment with invalid CORS_ORIGINS but valid fallback
            process.env.NODE_ENV = nodeEnv
            process.env.FRONTEND_URL = frontendUrl
            delete process.env.CORS_ORIGINS // Use environment defaults
            
            // Should succeed with environment defaults
            const corsConfig = initializeCorsConfig()
            
            // Should have valid configuration
            expect(corsConfig.allowedOrigins).toBeInstanceOf(Array)
            expect(corsConfig.allowedOrigins.length).toBeGreaterThan(0)
            expect(corsConfig.allowedOrigins).toContain(frontendUrl)
            
            // Should have proper CORS options
            expect(corsConfig.corsOptions).toBeDefined()
            expect(corsConfig.corsOptions.credentials).toBe(true)
            expect(corsConfig.originValidator).toBeDefined()
          }
        ),
        { numRuns: 25 }
      )
    })

    test('should log security events for invalid origin validation attempts', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 3 }),
          fc.oneof(
            fc.string().filter(s => {
              try {
                new URL(s)
                return false // Valid URL, skip
              } catch {
                return s.length > 0 && s.length < 30 // Invalid URL, use it
              }
            }),
            fc.webUrl().map(url => url + '<script>alert("xss")</script>'), // XSS attempt
            fc.string().map(s => `javascript:${s}`), // JavaScript protocol
          ),
          (allowedOrigins, maliciousOrigin) => {
            // Set up valid configuration
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originValidator = corsConfig.originValidator
            
            // Clear any existing events
            const initialStats = originValidator.getSecurityStats()
            
            // Attempt validation with malicious origin
            const result = originValidator.validateOrigin(
              maliciousOrigin,
              '192.168.1.100', // Mock client IP
              'Mozilla/5.0 (Malicious Bot)', // Mock user agent
              '/api/sensitive', // Mock path
              'POST' // Mock method
            )
            
            // Should be rejected
            expect(result.allowed).toBe(false)
            expect(result.reason).toBeTruthy()
            expect(result.securityEvent).toBeDefined()
            
            // Should have logged a security event
            const newStats = originValidator.getSecurityStats()
            expect(newStats.totalEvents).toBeGreaterThan(initialStats.totalEvents)
            
            // Should have appropriate event type
            const recentEvents = originValidator.getRecentSecurityEvents(1)
            expect(recentEvents.length).toBeGreaterThan(0)
            
            const lastEvent = recentEvents[recentEvents.length - 1]
            expect(lastEvent.origin).toBe(maliciousOrigin)
            expect(['INVALID_ORIGIN_FORMAT', 'SUSPICIOUS_ORIGIN', 'ORIGIN_BLOCKED']).toContain(lastEvent.type)
            expect(lastEvent.timestamp).toBeInstanceOf(Date)
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should maintain security event history with proper limits', () => {
      fc.assert(
        fc.property(
          fc.array(fc.webUrl(), { minLength: 1, maxLength: 2 }),
          fc.integer({ min: 5, max: 20 }), // Number of malicious attempts
          (allowedOrigins, attemptCount) => {
            // Set up valid configuration
            process.env.CORS_ORIGINS = allowedOrigins.join(',')
            
            // Initialize CORS config
            const corsConfig = initializeCorsConfig()
            const originValidator = corsConfig.originValidator
            
            // Generate multiple malicious attempts
            for (let i = 0; i < attemptCount; i++) {
              const maliciousOrigin = `http://malicious-${i}.com`
              originValidator.validateOrigin(maliciousOrigin)
            }
            
            // Should have recorded all events
            const stats = originValidator.getSecurityStats()
            expect(stats.totalEvents).toBeGreaterThanOrEqual(attemptCount)
            expect(stats.blockedOrigins).toBeGreaterThan(0)
            
            // Should be able to retrieve recent events
            const recentEvents = originValidator.getRecentSecurityEvents(attemptCount)
            expect(recentEvents.length).toBeGreaterThan(0)
            expect(recentEvents.length).toBeLessThanOrEqual(attemptCount)
            
            // Events should be properly formatted
            recentEvents.forEach(event => {
              expect(event.type).toBeDefined()
              expect(event.origin).toBeDefined()
              expect(event.reason).toBeDefined()
              expect(event.timestamp).toBeInstanceOf(Date)
            })
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should handle configuration errors gracefully without exposing sensitive information', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.constant(undefined), // Missing environment
            fc.constant(''), // Empty configuration
            fc.string().filter(s => s.includes('password') || s.includes('secret')), // Sensitive data
          ),
          (sensitiveConfig) => {
            // Set up potentially sensitive configuration
            if (sensitiveConfig !== undefined) {
              process.env.CORS_ORIGINS = sensitiveConfig
            } else {
              delete process.env.CORS_ORIGINS
              delete process.env.FRONTEND_URL
            }
            
            let thrownError: Error | null = null
            try {
              initializeCorsConfig()
            } catch (error) {
              thrownError = error as Error
            }
            
            if (thrownError) {
              // Error message should not expose sensitive configuration details
              expect(thrownError.message).not.toContain('password')
              expect(thrownError.message).not.toContain('secret')
              expect(thrownError.message).not.toContain('token')
              
              // Should be a generic configuration error
              expect(thrownError.message).toContain('CORS configuration error')
            }
          }
        ),
        { numRuns: 20 }
      )
    })

    test('should provide consistent error handling across different invalid configurations', () => {
      fc.assert(
        fc.property(
          fc.oneof(
            fc.constant(''), // Empty
            fc.constant('   '), // Whitespace only
            fc.constant('invalid-url,another-invalid'), // Multiple invalid
            fc.constant('ftp://unsupported.com'), // Unsupported protocol
            fc.constant('http://,https://'), // Incomplete URLs
          ),
          (invalidConfig) => {
            // Set up invalid configuration
            process.env.CORS_ORIGINS = invalidConfig
            
            // Should consistently throw configuration errors
            let thrownError: Error | null = null
            try {
              initializeCorsConfig()
            } catch (error) {
              thrownError = error as Error
            }
            
            expect(thrownError).not.toBeNull()
            expect(thrownError!.message).toMatch(/CORS configuration error/i)
            
            // Error should be descriptive but not expose internal details
            expect(thrownError!.message.length).toBeGreaterThan(10)
            expect(thrownError!.message.length).toBeLessThan(200)
          }
        ),
        { numRuns: 20 }
      )
    })
  })
})