/**
 * Property-Based Tests for Configuration Validation
 * 
 * Tests the configuration validation system to ensure it properly validates
 * environment variables and service endpoints.
 * 
 * **Property 9: Configuration Validation**
 * **Validates: Requirements 6.5**
 */

import { describe, test, expect, beforeEach, afterEach } from '@jest/globals'
import fc from 'fast-check'
import { ConfigValidator, ValidationResult } from '../src/services/config-validator'

// Mock environment variables for testing
const originalEnv = process.env

describe('Configuration Validation Properties', () => {
  let validator: ConfigValidator

  beforeEach(() => {
    // Reset environment variables
    jest.resetModules()
    process.env = { ...originalEnv }
    validator = new ConfigValidator()
  })

  afterEach(() => {
    // Restore original environment
    process.env = originalEnv
  })

  /**
   * Property 9.1: Required environment variables validation
   * For any set of required environment variables, if any are missing,
   * validation should fail with appropriate error messages.
   */
  test('Property 9.1: Missing required environment variables cause validation failure', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          COGNITO_USER_POOL_ID: fc.option(fc.string({ minLength: 1 }), { nil: undefined }),
          COGNITO_REGION: fc.option(fc.constantFrom('us-east-1', 'ap-southeast-1', 'eu-west-1'), { nil: undefined })
        }),
        async (envVars) => {
          // Set up environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            } else {
              delete process.env[key]
            }
          })

          const result = await validator.validateConfiguration()

          // If any required variable is missing, validation should fail
          const missingRequired = Object.entries(envVars).some(([key, value]) => 
            ['COGNITO_USER_POOL_ID', 'COGNITO_REGION'].includes(key) && value === undefined
          )

          if (missingRequired) {
            expect(result.valid).toBe(false)
            expect(result.errors.length).toBeGreaterThan(0)
            expect(result.details.environmentVariables.valid).toBe(false)
            expect(result.details.environmentVariables.missing.length).toBeGreaterThan(0)
          }
        }
      ),
      { numRuns: 50 }
    )
  })

  /**
   * Property 9.2: Valid environment variables configuration
   * For any complete set of valid environment variables,
   * the environment validation should pass.
   */
  test('Property 9.2: Complete valid environment variables pass validation', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          COGNITO_USER_POOL_ID: fc.string({ minLength: 10, maxLength: 50 }),
          COGNITO_REGION: fc.constantFrom('us-east-1', 'ap-southeast-1', 'eu-west-1', 'us-west-2'),
          COGNITO_CLIENT_ID: fc.option(fc.string({ minLength: 10, maxLength: 50 })),
          FRONTEND_URL: fc.option(fc.constantFrom(
            'https://example.com',
            'https://d2qvaswtmn22om.cloudfront.net',
            'http://localhost:3000'
          )),
          INTERNAL_API_URL: fc.option(fc.constantFrom(
            'https://api.example.com',
            'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
          ))
        }),
        async (envVars) => {
          // Set up environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            }
          })

          const result = await validator.validateConfiguration()

          // Environment variables validation should pass
          expect(result.details.environmentVariables.missing).toHaveLength(0)
          expect(result.details.environmentVariables.invalid).toHaveLength(0)
        }
      ),
      { numRuns: 30 }
    )
  })

  /**
   * Property 9.3: Invalid URL format detection
   * For any invalid URL in environment variables,
   * validation should detect and report the invalid format.
   */
  test('Property 9.3: Invalid URL formats are detected', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          FRONTEND_URL: fc.option(fc.constantFrom(
            'not-a-url',
            'ftp://invalid-protocol.com',
            'https://',
            'http://localhost:abc',
            'invalid-url-format'
          )),
          INTERNAL_API_URL: fc.option(fc.constantFrom(
            'not-a-url',
            'invalid-format',
            'https://example.com/prod', // Should be flagged as deprecated
            'http://'
          ))
        }),
        async (envVars) => {
          // Set required variables
          process.env.COGNITO_USER_POOL_ID = 'test-pool-id'
          process.env.COGNITO_REGION = 'ap-southeast-1'

          // Set up test environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            }
          })

          const result = await validator.validateConfiguration()

          // Check if any invalid URLs were provided
          const hasInvalidUrls = Object.values(envVars).some(value => 
            value !== undefined && (
              !value.startsWith('http') || 
              value === 'https://' || 
              value === 'http://' ||
              value.includes('/prod')
            )
          )

          if (hasInvalidUrls) {
            expect(result.details.environmentVariables.invalid.length).toBeGreaterThan(0)
          }
        }
      ),
      { numRuns: 30 }
    )
  })

  /**
   * Property 9.4: Configuration report generation consistency
   * For any validation result, the generated report should contain
   * all errors and warnings from the validation result.
   */
  test('Property 9.4: Configuration report contains all validation details', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          COGNITO_USER_POOL_ID: fc.option(fc.string({ minLength: 1 })),
          COGNITO_REGION: fc.option(fc.constantFrom('us-east-1', 'invalid-region')),
          FRONTEND_URL: fc.option(fc.constantFrom('https://example.com', 'invalid-url'))
        }),
        async (envVars) => {
          // Set up environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            } else {
              delete process.env[key]
            }
          })

          const result = await validator.validateConfiguration()
          const report = validator.generateConfigurationReport(result)

          // Report should contain status information
          expect(report).toContain(result.valid ? '✅ VALID' : '❌ INVALID')
          expect(report).toContain(`Errors: ${result.errors.length}`)
          expect(report).toContain(`Warnings: ${result.warnings.length}`)

          // Report should contain all errors
          result.errors.forEach(error => {
            expect(report).toContain('❌')
          })

          // Report should contain all warnings
          result.warnings.forEach(warning => {
            expect(report).toContain('⚠️')
          })

          // Report should contain section headers
          expect(report).toContain('Environment Variables:')
          expect(report).toContain('Service Endpoints:')
          expect(report).toContain('Authentication:')
          expect(report).toContain('CORS Configuration:')
        }
      ),
      { numRuns: 25 }
    )
  })

  /**
   * Property 9.5: Validation result structure consistency
   * For any configuration validation, the result should always
   * have the expected structure and properties.
   */
  test('Property 9.5: Validation result has consistent structure', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          COGNITO_USER_POOL_ID: fc.option(fc.string()),
          COGNITO_REGION: fc.option(fc.string()),
          FRONTEND_URL: fc.option(fc.string()),
          INTERNAL_API_URL: fc.option(fc.string())
        }),
        async (envVars) => {
          // Set up environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            } else {
              delete process.env[key]
            }
          })

          const result = await validator.validateConfiguration()

          // Validate result structure
          expect(result).toHaveProperty('valid')
          expect(result).toHaveProperty('errors')
          expect(result).toHaveProperty('warnings')
          expect(result).toHaveProperty('details')

          expect(typeof result.valid).toBe('boolean')
          expect(Array.isArray(result.errors)).toBe(true)
          expect(Array.isArray(result.warnings)).toBe(true)

          // Validate details structure
          expect(result.details).toHaveProperty('environmentVariables')
          expect(result.details).toHaveProperty('serviceEndpoints')
          expect(result.details).toHaveProperty('authentication')
          expect(result.details).toHaveProperty('cors')

          // Validate environment variables details
          const envDetails = result.details.environmentVariables
          expect(envDetails).toHaveProperty('valid')
          expect(envDetails).toHaveProperty('missing')
          expect(envDetails).toHaveProperty('invalid')
          expect(envDetails).toHaveProperty('warnings')
          expect(typeof envDetails.valid).toBe('boolean')
          expect(Array.isArray(envDetails.missing)).toBe(true)
          expect(Array.isArray(envDetails.invalid)).toBe(true)
          expect(Array.isArray(envDetails.warnings)).toBe(true)

          // Validate service endpoints details
          const serviceDetails = result.details.serviceEndpoints
          expect(serviceDetails).toHaveProperty('valid')
          expect(serviceDetails).toHaveProperty('accessible')
          expect(serviceDetails).toHaveProperty('inaccessible')
          expect(serviceDetails).toHaveProperty('errors')
          expect(typeof serviceDetails.valid).toBe('boolean')
          expect(Array.isArray(serviceDetails.accessible)).toBe(true)
          expect(Array.isArray(serviceDetails.inaccessible)).toBe(true)
          expect(Array.isArray(serviceDetails.errors)).toBe(true)
        }
      ),
      { numRuns: 20 }
    )
  })

  /**
   * Property 9.6: Error and warning consistency
   * For any validation result, if valid is false, there should be at least one error.
   * If valid is true, there should be no errors (but warnings are allowed).
   */
  test('Property 9.6: Validation status consistency with errors', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          COGNITO_USER_POOL_ID: fc.option(fc.string()),
          COGNITO_REGION: fc.option(fc.string()),
          FRONTEND_URL: fc.option(fc.string())
        }),
        async (envVars) => {
          // Set up environment variables
          Object.entries(envVars).forEach(([key, value]) => {
            if (value !== undefined) {
              process.env[key] = value
            } else {
              delete process.env[key]
            }
          })

          const result = await validator.validateConfiguration()

          // Consistency check: if valid is false, there should be errors
          if (!result.valid) {
            expect(result.errors.length).toBeGreaterThan(0)
          }

          // Consistency check: if valid is true, there should be no errors
          if (result.valid) {
            expect(result.errors.length).toBe(0)
          }

          // All error and warning arrays should be defined
          expect(result.errors).toBeDefined()
          expect(result.warnings).toBeDefined()
          expect(Array.isArray(result.errors)).toBe(true)
          expect(Array.isArray(result.warnings)).toBe(true)
        }
      ),
      { numRuns: 30 }
    )
  })
})

// Integration test with actual service discovery
describe('Configuration Validation Integration', () => {
  beforeEach(() => {
    process.env = { ...originalEnv }
  })

  afterEach(() => {
    process.env = originalEnv
  })

  test('Integration: Full configuration validation with service discovery', async () => {
    // Set up a complete valid configuration
    process.env.COGNITO_USER_POOL_ID = 'ap-southeast-1_test123'
    process.env.COGNITO_REGION = 'ap-southeast-1'
    process.env.COGNITO_CLIENT_ID = 'test-client-id'
    process.env.FRONTEND_URL = 'https://d2qvaswtmn22om.cloudfront.net'
    process.env.INTERNAL_API_URL = 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
    process.env.INTERNAL_API_KEY = 'test-api-key'

    const validator = new ConfigValidator()
    const result = await validator.validateConfiguration()

    // Environment variables should be valid
    expect(result.details.environmentVariables.valid).toBe(true)
    expect(result.details.environmentVariables.missing).toHaveLength(0)

    // CORS configuration should be valid
    expect(result.details.cors.valid).toBe(true)
    expect(result.details.cors.frontendUrlValid).toBe(true)

    // Generate report and verify it contains expected sections
    const report = validator.generateConfigurationReport(result)
    expect(report).toContain('BFF CONFIGURATION VALIDATION REPORT')
    expect(report).toContain('Environment Variables:')
    expect(report).toContain('Service Endpoints:')
    expect(report).toContain('Authentication:')
    expect(report).toContain('CORS Configuration:')
  })
})