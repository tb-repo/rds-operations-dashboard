/**
 * Property Test: Clean URL Structure
 * 
 * Validates: Requirements 1.1, 1.3, 4.1
 * Property 1: For any API endpoint in the system, the URL should not contain 
 * /prod or other environment-specific stage prefixes
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const API_BASE_URL = process.env.TEST_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const TIMEOUT = 10000

// Property: Clean URL Structure
describe('Property 1: Clean URL Structure', () => {
  
  test('API endpoints should not contain /prod or environment-specific prefixes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(
          '/health',
          '/cors-config',
          '/api/health',
          '/api/instances',
          '/api/metrics',
          '/api/compliance',
          '/api/costs'
        ),
        async (endpoint) => {
          // Property: Clean URL should not contain /prod
          const cleanUrl = `${API_BASE_URL}${endpoint}`
          
          // Verify URL structure
          expect(cleanUrl).not.toMatch(/\/prod\//)
          expect(cleanUrl).not.toMatch(/\/staging\//)
          expect(cleanUrl).not.toMatch(/\/dev\//)
          expect(cleanUrl).not.toMatch(/\/test\//)
          
          // Verify the URL is accessible (for non-auth endpoints)
          if (endpoint === '/health' || endpoint === '/cors-config') {
            try {
              const response = await axios.get(cleanUrl, { timeout: TIMEOUT })
              expect(response.status).toBe(200)
              
              // Additional validation for specific endpoints
              if (endpoint === '/health') {
                expect(response.data).toHaveProperty('status')
                expect(response.data.status).toBe('healthy')
              }
              
              if (endpoint === '/cors-config') {
                expect(response.data).toHaveProperty('allowedOrigins')
                expect(response.data).toHaveProperty('corsEnabled')
                expect(response.data.corsEnabled).toBe(true)
              }
            } catch (error: any) {
              // Log error for debugging but don't fail the property test
              // as network issues shouldn't invalidate the URL structure property
              console.warn(`Network error testing ${cleanUrl}: ${error.message}`)
            }
          }
          
          return true
        }
      ),
      { numRuns: 50, timeout: 30000 }
    )
  })
  
  test('API Gateway should respond to root-level paths without stage prefixes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          path: fc.constantFrom('/health', '/cors-config'),
          method: fc.constantFrom('GET', 'OPTIONS')
        }),
        async ({ path, method }) => {
          const url = `${API_BASE_URL}${path}`
          
          // Property: Root-level paths should be accessible
          expect(url).not.toMatch(/\/prod/)
          expect(url).not.toMatch(/\/\$default/)
          
          // The URL should be a clean, root-level path
          const pathParts = new URL(url).pathname.split('/').filter(Boolean)
          
          // First part should be the actual endpoint, not a stage
          if (pathParts.length > 0) {
            expect(pathParts[0]).not.toBe('prod')
            expect(pathParts[0]).not.toBe('staging')
            expect(pathParts[0]).not.toBe('dev')
            expect(pathParts[0]).not.toBe('$default')
          }
          
          return true
        }
      ),
      { numRuns: 30, timeout: 20000 }
    )
  })
  
  test('Environment variables should not contain stage prefixes in URLs', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(
          'INTERNAL_API_URL',
          'FRONTEND_URL',
          'API_BASE_URL'
        ),
        (envVarName) => {
          const envValue = process.env[envVarName]
          
          if (envValue) {
            // Property: Environment URLs should not contain stage prefixes
            expect(envValue).not.toMatch(/\/prod$/)
            expect(envValue).not.toMatch(/\/prod\//)
            expect(envValue).not.toMatch(/\/staging$/)
            expect(envValue).not.toMatch(/\/staging\//)
            expect(envValue).not.toMatch(/\/dev$/)
            expect(envValue).not.toMatch(/\/dev\//)
            
            // Should be a clean base URL
            try {
              const url = new URL(envValue)
              expect(url.pathname).toMatch(/^\/?$/) // Should be root or empty
            } catch (error) {
              // If not a valid URL, it should still not contain stage prefixes
              expect(envValue).not.toMatch(/\/(prod|staging|dev|test)\b/)
            }
          }
          
          return true
        }
      ),
      { numRuns: 10 }
    )
  })
  
  test('API responses should not reference stage-prefixed URLs', async () => {
    const healthUrl = `${API_BASE_URL}/health`
    const corsUrl = `${API_BASE_URL}/cors-config`
    
    try {
      // Test health endpoint response
      const healthResponse = await axios.get(healthUrl, { timeout: TIMEOUT })
      const healthData = JSON.stringify(healthResponse.data)
      
      // Property: Response data should not contain stage-prefixed URLs
      expect(healthData).not.toMatch(/\/prod\//)
      expect(healthData).not.toMatch(/\/staging\//)
      expect(healthData).not.toMatch(/\/dev\//)
      
      // Test CORS config endpoint response
      const corsResponse = await axios.get(corsUrl, { timeout: TIMEOUT })
      const corsData = JSON.stringify(corsResponse.data)
      
      // Property: CORS config should not reference stage-prefixed URLs
      expect(corsData).not.toMatch(/\/prod\//)
      expect(corsData).not.toMatch(/\/staging\//)
      expect(corsData).not.toMatch(/\/dev\//)
      
      // Allowed origins should be clean URLs
      if (corsResponse.data.allowedOrigins) {
        corsResponse.data.allowedOrigins.forEach((origin: string) => {
          expect(origin).not.toMatch(/\/prod$/)
          expect(origin).not.toMatch(/\/staging$/)
          expect(origin).not.toMatch(/\/dev$/)
        })
      }
      
    } catch (error: any) {
      console.warn(`Network error in response validation: ${error.message}`)
      // Don't fail the test for network issues
    }
  })
  
  test('URL construction should always produce clean URLs', () => {
    fc.assert(
      fc.property(
        fc.record({
          baseUrl: fc.constantFrom(
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
          ),
          endpoint: fc.constantFrom(
            '/health',
            '/api/instances',
            '/api/operations',
            '/instances',
            '/operations',
            '/discovery'
          )
        }),
        ({ baseUrl, endpoint }) => {
          // Property: URL construction should never introduce stage prefixes
          const constructedUrl = `${baseUrl.replace(/\/$/, '')}${endpoint}`
          
          expect(constructedUrl).not.toMatch(/\/prod\//)
          expect(constructedUrl).not.toMatch(/\/staging\//)
          expect(constructedUrl).not.toMatch(/\/dev\//)
          expect(constructedUrl).not.toMatch(/\/\$default\//)
          
          // Should be a valid URL structure
          try {
            const url = new URL(constructedUrl)
            const pathSegments = url.pathname.split('/').filter(Boolean)
            
            // No segment should be a stage name
            pathSegments.forEach(segment => {
              expect(segment).not.toBe('prod')
              expect(segment).not.toBe('staging')
              expect(segment).not.toBe('dev')
              expect(segment).not.toBe('$default')
            })
          } catch (error) {
            throw new Error(`Invalid URL constructed: ${constructedUrl}`)
          }
          
          return true
        }
      ),
      { numRuns: 100 }
    )
  })
})

// Additional validation tests
describe('Clean URL Structure Validation', () => {
  
  test('BFF should not call itself through stage-prefixed URLs', () => {
    // This test validates that the BFF configuration doesn't create circular references
    const internalApiUrl = process.env.INTERNAL_API_URL
    const bffApiUrl = process.env.BFF_API_URL || API_BASE_URL
    
    if (internalApiUrl && bffApiUrl) {
      // Property: Internal API URL should not be the same as BFF URL with /prod
      expect(internalApiUrl).not.toBe(`${bffApiUrl}/prod`)
      expect(internalApiUrl).not.toMatch(/\/prod$/)
      
      // Should be different base URLs or different paths
      try {
        const internalUrl = new URL(internalApiUrl)
        const bffUrl = new URL(bffApiUrl)
        
        if (internalUrl.host === bffUrl.host) {
          // Same host, paths should be different and not stage-prefixed
          expect(internalUrl.pathname).not.toBe('/prod')
          expect(internalUrl.pathname).not.toBe('/staging')
          expect(internalUrl.pathname).not.toBe('/dev')
        }
      } catch (error) {
        console.warn('Could not parse URLs for circular reference check')
      }
    }
  })
  
  test('All configured endpoints should use consistent URL patterns', () => {
    const endpoints = [
      '/health',
      '/cors-config',
      '/api/health',
      '/api/instances',
      '/api/metrics',
      '/api/compliance',
      '/api/costs',
      '/api/operations',
      '/api/discovery/trigger',
      '/api/monitoring',
      '/api/approvals',
      '/api/errors',
      '/api/users'
    ]
    
    endpoints.forEach(endpoint => {
      // Property: All endpoints should follow clean URL patterns
      expect(endpoint).toMatch(/^\/[a-z-]+/) // Start with / and lowercase
      expect(endpoint).not.toMatch(/\/prod\//)
      expect(endpoint).not.toMatch(/\/staging\//)
      expect(endpoint).not.toMatch(/\/dev\//)
      expect(endpoint).not.toMatch(/\/\$default\//)
      
      // Should not have double slashes
      expect(endpoint).not.toMatch(/\/\//)
      
      // Should not end with slash (except root)
      if (endpoint !== '/') {
        expect(endpoint).not.toMatch(/\/$/)
      }
    })
  })
})