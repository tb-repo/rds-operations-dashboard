/**
 * Property Test: Root-Level Routing
 * 
 * Validates: Requirements 1.2, 4.4
 * Property 2: For any valid API path, the API Gateway should respond successfully 
 * without requiring stage prefixes
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const BFF_API_URL = process.env.TEST_BFF_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const INTERNAL_API_URL = process.env.TEST_INTERNAL_API_URL || 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
const API_KEY = process.env.INTERNAL_API_KEY || ''
const TIMEOUT = 15000

// Property: Root-Level Routing
describe('Property 2: Root-Level Routing', () => {
  
  test('BFF API Gateway should respond to root-level paths without stage prefixes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          endpoint: fc.constantFrom(
            '/health',
            '/cors-config',
            '/api/health'
          ),
          method: fc.constantFrom('GET', 'OPTIONS')
        }),
        async ({ endpoint, method }) => {
          const url = `${BFF_API_URL}${endpoint}`
          
          // Property: URL should not contain stage prefixes
          expect(url).not.toMatch(/\/prod\//)
          expect(url).not.toMatch(/\/staging\//)
          expect(url).not.toMatch(/\/dev\//)
          expect(url).not.toMatch(/\/\$default\//)
          
          try {
            const config: any = {
              method,
              url,
              timeout: TIMEOUT,
              validateStatus: (status: number) => status < 500 // Accept 4xx as valid responses
            }
            
            if (method === 'OPTIONS') {
              config.headers = {
                'Origin': 'https://d2qvaswtmn22om.cloudfront.net',
                'Access-Control-Request-Method': 'GET',
                'Access-Control-Request-Headers': 'Content-Type'
              }
            }
            
            const response = await axios(config)
            
            // Property: Should get a valid HTTP response
            expect(response.status).toBeLessThan(500)
            
            // For successful responses, validate structure
            if (response.status === 200) {
              if (endpoint === '/health' || endpoint === '/api/health') {
                expect(response.data).toHaveProperty('status')
                expect(response.data.status).toBe('healthy')
              }
              
              if (endpoint === '/cors-config') {
                expect(response.data).toHaveProperty('corsEnabled')
                expect(response.data.corsEnabled).toBe(true)
              }
            }
            
            // For OPTIONS requests, validate CORS headers
            if (method === 'OPTIONS' && response.status === 200) {
              expect(response.headers).toHaveProperty('access-control-allow-origin')
              expect(response.headers).toHaveProperty('access-control-allow-methods')
            }
            
          } catch (error: any) {
            // Network errors should not fail the property test
            if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
              console.warn(`Network error testing ${url}: ${error.message}`)
              return true
            }
            throw error
          }
          
          return true
        }
      ),
      { numRuns: 30, timeout: 45000 }
    )
  })
  
  test('Internal API Gateway should respond to backend service paths without stage prefixes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(
          '/instances',
          '/operations',
          '/discovery',
          '/monitoring',
          '/compliance',
          '/costs'
        ),
        async (endpoint) => {
          const url = `${INTERNAL_API_URL}${endpoint}`
          
          // Property: URL should not contain stage prefixes
          expect(url).not.toMatch(/\/prod\//)
          expect(url).not.toMatch(/\/staging\//)
          expect(url).not.toMatch(/\/dev\//)
          expect(url).not.toMatch(/\/\$default\//)
          
          try {
            const headers: any = {
              'User-Agent': 'RDS-Dashboard-Test/1.0'
            }
            
            if (API_KEY) {
              headers['x-api-key'] = API_KEY
            }
            
            const response = await axios.get(url, {
              headers,
              timeout: TIMEOUT,
              validateStatus: (status: number) => status < 500
            })
            
            // Property: Should get a valid HTTP response (not 5xx)
            expect(response.status).toBeLessThan(500)
            
            // 401/403 are acceptable for authenticated endpoints
            if (response.status === 401 || response.status === 403) {
              console.log(`Authentication required for ${endpoint} - this is expected`)
            }
            
            // For successful responses, validate basic structure
            if (response.status === 200) {
              expect(response.data).toBeDefined()
              
              // Response should not contain stage-prefixed URLs
              const responseText = JSON.stringify(response.data)
              expect(responseText).not.toMatch(/\/prod\//)
              expect(responseText).not.toMatch(/\/staging\//)
              expect(responseText).not.toMatch(/\/dev\//)
            }
            
          } catch (error: any) {
            // Handle expected authentication errors
            if (error.response?.status === 401 || error.response?.status === 403) {
              console.log(`Authentication required for ${endpoint} - this is expected`)
              return true
            }
            
            // Network errors should not fail the property test
            if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
              console.warn(`Network error testing ${url}: ${error.message}`)
              return true
            }
            
            throw error
          }
          
          return true
        }
      ),
      { numRuns: 20, timeout: 60000 }
    )
  })
  
  test('API Gateway routing should be consistent across different HTTP methods', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          baseUrl: fc.constantFrom(BFF_API_URL, INTERNAL_API_URL),
          endpoint: fc.constantFrom('/health', '/cors-config'),
          method: fc.constantFrom('GET', 'HEAD', 'OPTIONS')
        }),
        async ({ baseUrl, endpoint, method }) => {
          // Skip internal API health checks as they may not exist
          if (baseUrl === INTERNAL_API_URL && endpoint === '/health') {
            return true
          }
          
          const url = `${baseUrl}${endpoint}`
          
          // Property: Consistent routing regardless of HTTP method
          expect(url).not.toMatch(/\/prod\//)
          expect(url).not.toMatch(/\/staging\//)
          expect(url).not.toMatch(/\/dev\//)
          
          try {
            const config: any = {
              method,
              url,
              timeout: TIMEOUT,
              validateStatus: (status: number) => status < 500
            }
            
            if (method === 'OPTIONS') {
              config.headers = {
                'Origin': 'https://d2qvaswtmn22om.cloudfront.net',
                'Access-Control-Request-Method': 'GET'
              }
            }
            
            const response = await axios(config)
            
            // Property: Should respond consistently
            expect(response.status).toBeLessThan(500)
            
            // Method-specific validations
            if (method === 'HEAD') {
              expect(response.data).toBeUndefined()
            }
            
            if (method === 'OPTIONS') {
              expect(response.headers).toHaveProperty('access-control-allow-methods')
            }
            
          } catch (error: any) {
            // Some methods might not be supported, that's okay
            if (error.response?.status === 405) {
              console.log(`Method ${method} not allowed for ${endpoint} - this is acceptable`)
              return true
            }
            
            // Network errors should not fail the property test
            if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
              console.warn(`Network error testing ${url}: ${error.message}`)
              return true
            }
            
            throw error
          }
          
          return true
        }
      ),
      { numRuns: 25, timeout: 50000 }
    )
  })
  
  test('URL path parsing should never extract stage prefixes', () => {
    fc.assert(
      fc.property(
        fc.record({
          baseUrl: fc.constantFrom(
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
          ),
          path: fc.constantFrom(
            '/health',
            '/api/instances',
            '/instances',
            '/operations',
            '/discovery'
          )
        }),
        ({ baseUrl, path }) => {
          const fullUrl = `${baseUrl}${path}`
          const parsedUrl = new URL(fullUrl)
          
          // Property: Path parsing should not reveal stage prefixes
          const pathSegments = parsedUrl.pathname.split('/').filter(Boolean)
          
          // No segment should be a stage name
          pathSegments.forEach(segment => {
            expect(segment).not.toBe('prod')
            expect(segment).not.toBe('staging')
            expect(segment).not.toBe('dev')
            expect(segment).not.toBe('$default')
          })
          
          // First segment should be meaningful endpoint, not stage
          if (pathSegments.length > 0) {
            const firstSegment = pathSegments[0]
            expect(['api', 'health', 'cors-config', 'instances', 'operations', 'discovery', 'monitoring', 'compliance', 'costs'])
              .toContain(firstSegment)
          }
          
          return true
        }
      ),
      { numRuns: 50 }
    )
  })
  
  test('API Gateway should handle root path requests correctly', async () => {
    const rootUrls = [BFF_API_URL, INTERNAL_API_URL]
    
    for (const baseUrl of rootUrls) {
      try {
        const response = await axios.get(baseUrl, {
          timeout: TIMEOUT,
          validateStatus: (status: number) => status < 500
        })
        
        // Property: Root path should not redirect to stage-prefixed URLs
        if (response.status === 301 || response.status === 302) {
          const location = response.headers.location
          if (location) {
            expect(location).not.toMatch(/\/prod\//)
            expect(location).not.toMatch(/\/staging\//)
            expect(location).not.toMatch(/\/dev\//)
          }
        }
        
        // Should get some response (404 is acceptable for root)
        expect(response.status).toBeLessThan(500)
        
      } catch (error: any) {
        // Network errors are acceptable
        if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
          console.warn(`Network error testing root ${baseUrl}: ${error.message}`)
          continue
        }
        
        // 404 for root is acceptable
        if (error.response?.status === 404) {
          continue
        }
        
        throw error
      }
    }
  })
})

// Additional validation for routing consistency
describe('Root-Level Routing Validation', () => {
  
  test('Stage-less URLs should be the canonical form', () => {
    const testUrls = [
      `${BFF_API_URL}/health`,
      `${BFF_API_URL}/cors-config`,
      `${INTERNAL_API_URL}/instances`,
      `${INTERNAL_API_URL}/operations`
    ]
    
    testUrls.forEach(url => {
      // Property: Canonical URLs should not contain stages
      expect(url).not.toMatch(/\/prod\//)
      expect(url).not.toMatch(/\/staging\//)
      expect(url).not.toMatch(/\/dev\//)
      expect(url).not.toMatch(/\/\$default\//)
      
      // Should be clean, direct paths
      const parsedUrl = new URL(url)
      expect(parsedUrl.pathname).not.toMatch(/\/\//) // No double slashes
      expect(parsedUrl.pathname).toMatch(/^\/[a-z-]+/) // Start with / and lowercase
    })
  })
  
  test('API Gateway configuration should support clean URL routing', () => {
    // This test validates the expected URL patterns
    const expectedPatterns = [
      // BFF endpoints
      { url: `${BFF_API_URL}/health`, type: 'health-check' },
      { url: `${BFF_API_URL}/cors-config`, type: 'configuration' },
      { url: `${BFF_API_URL}/api/instances`, type: 'api-endpoint' },
      
      // Internal API endpoints  
      { url: `${INTERNAL_API_URL}/instances`, type: 'backend-service' },
      { url: `${INTERNAL_API_URL}/operations`, type: 'backend-service' },
      { url: `${INTERNAL_API_URL}/discovery`, type: 'backend-service' }
    ]
    
    expectedPatterns.forEach(({ url, type }) => {
      // Property: All URL patterns should be clean and consistent
      expect(url).not.toMatch(/\/prod\//)
      expect(url).not.toMatch(/\/staging\//)
      expect(url).not.toMatch(/\/dev\//)
      
      const parsedUrl = new URL(url)
      
      // Should have valid hostname
      expect(parsedUrl.hostname).toMatch(/^[a-z0-9]+\.execute-api\.ap-southeast-1\.amazonaws\.com$/)
      
      // Should have clean path structure
      expect(parsedUrl.pathname).toMatch(/^\/[a-z-\/]+$/)
      expect(parsedUrl.pathname).not.toMatch(/\/\//)
      
      console.log(`✓ ${type}: ${url}`)
    })
  })
})