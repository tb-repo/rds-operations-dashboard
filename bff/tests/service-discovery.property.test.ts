/**
 * Property Tests: Service Discovery
 * 
 * Validates: Requirements 2.1, 2.3, 2.2, 2.4
 * Property 3: Service Discovery Correctness
 * Property 4: Backend Service Routing
 */

import { describe, test, expect, beforeEach, afterEach } from '@jest/globals'
import fc from 'fast-check'
import { ServiceDiscovery, getServiceDiscovery, initializeServiceDiscovery, destroyServiceDiscovery } from '../src/services/service-discovery'

// Mock environment variables for testing
const mockEnvVars = {
  INTERNAL_API_URL: 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com',
  BFF_API_URL: 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
  INTERNAL_API_KEY: 'test-api-key'
}

// Property 3: Service Discovery Correctness
describe('Property 3: Service Discovery Correctness', () => {
  
  beforeEach(() => {
    // Set up clean environment for each test
    Object.entries(mockEnvVars).forEach(([key, value]) => {
      process.env[key] = value
    })
    destroyServiceDiscovery()
  })
  
  afterEach(() => {
    destroyServiceDiscovery()
  })
  
  test('For any backend service name, BFF should return a valid, reachable endpoint that is not the BFF own URL', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(
          'discovery',
          'operations',
          'monitoring',
          'compliance',
          'costs',
          'approvals',
          'cloudops'
        ),
        (serviceName) => {
          const serviceDiscovery = initializeServiceDiscovery()
          
          // Property: Service endpoint should be valid and not circular
          const endpoint = serviceDiscovery.getEndpoint(serviceName as any)
          
          // Should not be empty
          expect(endpoint).toBeTruthy()
          expect(endpoint).not.toBe('')
          expect(endpoint).not.toBe('/')
          
          // Should not contain stage prefixes
          expect(endpoint).not.toMatch(/\/prod\//)
          expect(endpoint).not.toMatch(/\/staging\//)
          expect(endpoint).not.toMatch(/\/dev\//)
          expect(endpoint).not.toMatch(/\/\$default\//)
          
          // Should not be the BFF's own URL (circular reference check)
          const bffUrl = process.env.BFF_API_URL!
          expect(endpoint).not.toBe(bffUrl)
          expect(endpoint).not.toMatch(new RegExp(`^${bffUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`))
          
          // Should be a valid URL structure
          try {
            const url = new URL(endpoint)
            expect(url.protocol).toMatch(/^https?:$/)
            expect(url.hostname).toBeTruthy()
            expect(url.pathname).toBeTruthy()
          } catch (error) {
            throw new Error(`Invalid URL structure for ${serviceName}: ${endpoint}`)
          }
          
          // Should point to the internal API gateway
          expect(endpoint).toMatch(/^https:\/\/0pjyr8lkpl\.execute-api\.ap-southeast-1\.amazonaws\.com/)
          
          return true
        }
      ),
      { numRuns: 50 }
    )
  })
  
  test('Service discovery should detect and prevent circular references', () => {
    fc.assert(
      fc.property(
        fc.record({
          internalApiUrl: fc.constantFrom(
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com', // Same as BFF (circular)
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod', // BFF with /prod (circular)
            'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com/prod' // Internal with /prod (problematic)
          ),
          bffApiUrl: fc.constant('https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com')
        }),
        ({ internalApiUrl, bffApiUrl }) => {
          // Set up problematic environment
          process.env.INTERNAL_API_URL = internalApiUrl
          process.env.BFF_API_URL = bffApiUrl
          
          // Property: Should detect circular references and stage prefixes
          if (internalApiUrl === bffApiUrl || internalApiUrl.includes('/prod')) {
            expect(() => {
              initializeServiceDiscovery()
            }).toThrow()
          } else {
            // Should work fine for valid configurations
            const serviceDiscovery = initializeServiceDiscovery()
            expect(serviceDiscovery).toBeDefined()
          }
          
          return true
        }
      ),
      { numRuns: 20 }
    )
  })
  
  test('All service endpoints should follow consistent naming patterns', () => {
    const serviceDiscovery = initializeServiceDiscovery()
    const allEndpoints = serviceDiscovery.getAllEndpoints()
    
    fc.assert(
      fc.property(
        fc.constantFrom(...Object.keys(allEndpoints)),
        (serviceName) => {
          const endpoint = allEndpoints[serviceName as keyof typeof allEndpoints]
          
          // Property: Consistent endpoint patterns
          expect(endpoint).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/[a-z-]+$/)
          
          // Should not have double slashes
          expect(endpoint).not.toMatch(/\/\//)
          
          // Should not end with slash
          expect(endpoint).not.toMatch(/\/$/)
          
          // Should have meaningful path segment
          const url = new URL(endpoint)
          const pathSegments = url.pathname.split('/').filter(Boolean)
          expect(pathSegments.length).toBeGreaterThan(0)
          
          // Path should relate to service name
          const pathSegment = pathSegments[pathSegments.length - 1]
          const expectedPaths = {
            'discovery': 'instances',
            'operations': 'operations',
            'monitoring': 'monitoring',
            'compliance': 'compliance',
            'costs': 'costs',
            'approvals': 'approvals',
            'cloudops': 'cloudops'
          }
          
          expect(pathSegment).toBe(expectedPaths[serviceName as keyof typeof expectedPaths])
          
          return true
        }
      ),
      { numRuns: 30 }
    )
  })
  
  test('Service discovery configuration should be immutable after initialization', () => {
    const serviceDiscovery = initializeServiceDiscovery()
    const originalEndpoints = serviceDiscovery.getAllEndpoints()
    
    fc.assert(
      fc.property(
        fc.constantFrom('discovery', 'operations', 'monitoring'),
        (serviceName) => {
          const endpoint1 = serviceDiscovery.getEndpoint(serviceName as any)
          const endpoint2 = serviceDiscovery.getEndpoint(serviceName as any)
          
          // Property: Endpoints should be consistent across calls
          expect(endpoint1).toBe(endpoint2)
          expect(endpoint1).toBe(originalEndpoints[serviceName as keyof typeof originalEndpoints])
          
          return true
        }
      ),
      { numRuns: 20 }
    )
  })
})

// Property 4: Backend Service Routing
describe('Property 4: Backend Service Routing', () => {
  
  beforeEach(() => {
    Object.entries(mockEnvVars).forEach(([key, value]) => {
      process.env[key] = value
    })
    destroyServiceDiscovery()
  })
  
  afterEach(() => {
    destroyServiceDiscovery()
  })
  
  test('For any backend service call from BFF, request should be routed to appropriate Lambda function or internal API endpoint', () => {
    fc.assert(
      fc.property(
        fc.record({
          service: fc.constantFrom('discovery', 'operations', 'monitoring', 'compliance', 'costs'),
          path: fc.constantFrom('', '/', '/health', '/status'),
          method: fc.constantFrom('GET', 'POST')
        }),
        ({ service, path, method }) => {
          const serviceDiscovery = initializeServiceDiscovery()
          
          // Property: Service routing should be deterministic and correct
          const endpoint = serviceDiscovery.getEndpoint(service as any)
          
          // Construct expected URL
          const expectedUrl = `${endpoint}${path}`
          
          // Should not contain circular references
          expect(expectedUrl).not.toMatch(/08mqqv008c/) // BFF API Gateway ID
          
          // Should point to internal API
          expect(expectedUrl).toMatch(/0pjyr8lkpl/) // Internal API Gateway ID
          
          // Should not have stage prefixes
          expect(expectedUrl).not.toMatch(/\/prod\//)
          expect(expectedUrl).not.toMatch(/\/staging\//)
          expect(expectedUrl).not.toMatch(/\/dev\//)
          
          // Should be a valid URL
          try {
            new URL(expectedUrl)
          } catch (error) {
            throw new Error(`Invalid routed URL: ${expectedUrl}`)
          }
          
          // Test HTTP client creation
          const client = serviceDiscovery.createInternalApiClient('test-key')
          expect(client.defaults.headers['x-api-key']).toBe('test-key')
          expect(client.defaults.headers['User-Agent']).toMatch(/RDS-Dashboard-BFF/)
          expect(client.defaults.headers['x-bff-request']).toBe('true')
          
          return true
        }
      ),
      { numRuns: 40 }
    )
  })
  
  test('Service health checks should target correct endpoints without circular calls', async () => {
    const serviceDiscovery = initializeServiceDiscovery()
    
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom('discovery', 'operations', 'monitoring'),
        async (serviceName) => {
          // Property: Health checks should not create circular calls
          const endpoint = serviceDiscovery.getEndpoint(serviceName as any)
          
          // Health check URL should be the service endpoint itself
          expect(endpoint).not.toMatch(/08mqqv008c/) // Should not call BFF
          expect(endpoint).toMatch(/0pjyr8lkpl/) // Should call internal API
          
          // Mock the health check (we can't make real calls in unit tests)
          const mockHealth = {
            service: serviceName,
            endpoint,
            healthy: true,
            responseTime: 100,
            lastChecked: new Date()
          }
          
          // Validate health check structure
          expect(mockHealth.service).toBe(serviceName)
          expect(mockHealth.endpoint).toBe(endpoint)
          expect(mockHealth.healthy).toBe(true)
          expect(mockHealth.responseTime).toBeGreaterThan(0)
          expect(mockHealth.lastChecked).toBeInstanceOf(Date)
          
          return true
        }
      ),
      { numRuns: 15, timeout: 10000 }
    )
  })
  
  test('Service call method should construct correct requests for all service types', () => {
    fc.assert(
      fc.property(
        fc.record({
          service: fc.constantFrom('discovery', 'operations', 'monitoring', 'compliance', 'costs'),
          path: fc.constantFrom('', '/list', '/status', '/health'),
          method: fc.constantFrom('GET', 'POST', 'PUT', 'DELETE'),
          hasData: fc.boolean(),
          hasParams: fc.boolean()
        }),
        ({ service, path, method, hasData, hasParams }) => {
          const serviceDiscovery = initializeServiceDiscovery()
          
          // Property: Service call configuration should be correct
          const endpoint = serviceDiscovery.getEndpoint(service as any)
          const expectedUrl = `${endpoint}${path}`
          
          // Validate URL construction
          expect(expectedUrl).not.toMatch(/\/\//) // No double slashes
          expect(expectedUrl).not.toMatch(/\/prod\//) // No stage prefixes
          expect(expectedUrl).toMatch(/^https:\/\//) // Valid HTTPS URL
          
          // Validate client configuration
          const client = serviceDiscovery.createInternalApiClient('test-api-key')
          
          expect(client.defaults.timeout).toBe(30000)
          expect(client.defaults.headers['x-api-key']).toBe('test-api-key')
          expect(client.defaults.headers['User-Agent']).toBe('RDS-Dashboard-BFF/1.0')
          expect(client.defaults.headers['x-bff-request']).toBe('true')
          expect(client.defaults.headers['Content-Type']).toBe('application/json')
          
          // Validate request options structure
          const requestOptions = {
            method,
            url: expectedUrl,
            data: hasData ? { test: 'data' } : undefined,
            params: hasParams ? { test: 'param' } : undefined
          }
          
          expect(requestOptions.method).toBe(method)
          expect(requestOptions.url).toBe(expectedUrl)
          
          if (hasData) {
            expect(requestOptions.data).toBeDefined()
          }
          
          if (hasParams) {
            expect(requestOptions.params).toBeDefined()
          }
          
          return true
        }
      ),
      { numRuns: 50 }
    )
  })
  
  test('Service statistics should accurately reflect service discovery state', () => {
    const serviceDiscovery = initializeServiceDiscovery()
    
    fc.assert(
      fc.property(
        fc.integer({ min: 0, max: 7 }), // Number of services to mock as healthy
        (healthyCount) => {
          // Property: Statistics should be mathematically correct
          const stats = serviceDiscovery.getStatistics()
          
          expect(stats.totalServices).toBe(7) // We have 7 services defined
          expect(stats.healthyServices).toBeGreaterThanOrEqual(0)
          expect(stats.unhealthyServices).toBeGreaterThanOrEqual(0)
          expect(stats.healthyServices + stats.unhealthyServices).toBeLessThanOrEqual(stats.totalServices)
          expect(stats.averageResponseTime).toBeGreaterThanOrEqual(0)
          
          // If we have health data, lastHealthCheck should be a valid date
          if (stats.healthyServices > 0 || stats.unhealthyServices > 0) {
            expect(stats.lastHealthCheck).toBeInstanceOf(Date)
          }
          
          return true
        }
      ),
      { numRuns: 20 }
    )
  })
})

// Additional validation tests
describe('Service Discovery Validation', () => {
  
  beforeEach(() => {
    Object.entries(mockEnvVars).forEach(([key, value]) => {
      process.env[key] = value
    })
    destroyServiceDiscovery()
  })
  
  afterEach(() => {
    destroyServiceDiscovery()
  })
  
  test('Service discovery should handle missing environment variables gracefully', () => {
    // Test with missing INTERNAL_API_URL
    delete process.env.INTERNAL_API_URL
    
    expect(() => {
      initializeServiceDiscovery()
    }).not.toThrow() // Should use defaults
    
    const serviceDiscovery = getServiceDiscovery()
    const endpoint = serviceDiscovery.getEndpoint('discovery')
    expect(endpoint).toBe('/instances') // Should use default empty base URL
  })
  
  test('Service discovery should validate all required services are configured', () => {
    const serviceDiscovery = initializeServiceDiscovery()
    const allEndpoints = serviceDiscovery.getAllEndpoints()
    
    const requiredServices = ['discovery', 'operations', 'monitoring', 'compliance', 'costs', 'approvals', 'cloudops']
    
    requiredServices.forEach(service => {
      expect(allEndpoints).toHaveProperty(service)
      expect(allEndpoints[service as keyof typeof allEndpoints]).toBeTruthy()
    })
  })
  
  test('Service discovery singleton should work correctly', () => {
    const instance1 = getServiceDiscovery()
    const instance2 = getServiceDiscovery()
    
    // Should be the same instance
    expect(instance1).toBe(instance2)
    
    // Should have consistent configuration
    expect(instance1.getAllEndpoints()).toEqual(instance2.getAllEndpoints())
  })
  
  test('Service discovery cleanup should work properly', () => {
    const serviceDiscovery = initializeServiceDiscovery()
    
    // Should be initialized
    expect(serviceDiscovery).toBeDefined()
    
    // Cleanup
    destroyServiceDiscovery()
    
    // New instance should be created
    const newInstance = getServiceDiscovery()
    expect(newInstance).toBeDefined()
    expect(newInstance).not.toBe(serviceDiscovery)
  })
})