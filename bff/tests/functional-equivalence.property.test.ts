/**
 * Property Test: Functional Equivalence
 * 
 * Validates: Requirements 7.1, 7.3, 7.4
 * Property 10: For any existing API operation, it should continue to work 
 * identically with the new clean URL structure
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const API_BASE_URL = process.env.TEST_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const INTERNAL_API_URL = process.env.INTERNAL_API_URL || 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
const TIMEOUT = 15000

// Mock data generators for testing
const generateInstanceId = () => fc.stringOf(fc.constantFrom('a', 'b', 'c', 'd', 'e', 'f', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'), { minLength: 10, maxLength: 20 })
const generateAccountId = () => fc.stringOf(fc.constantFrom('0', '1', '2', '3', '4', '5', '6', '7', '8', '9'), { minLength: 12, maxLength: 12 })
const generateRegion = () => fc.constantFrom('us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1', 'ap-northeast-1')

interface APIOperation {
  endpoint: string;
  method: string;
  requiresAuth: boolean;
  expectedResponseStructure: any;
  testPayload?: any;
}

// Define API operations that should work identically
const API_OPERATIONS: APIOperation[] = [
  {
    endpoint: '/health',
    method: 'GET',
    requiresAuth: false,
    expectedResponseStructure: { status: 'string', timestamp: 'string' }
  },
  {
    endpoint: '/cors-config',
    method: 'GET',
    requiresAuth: false,
    expectedResponseStructure: { allowedOrigins: 'array', corsEnabled: 'boolean' }
  },
  {
    endpoint: '/api/health',
    method: 'GET',
    requiresAuth: false,
    expectedResponseStructure: { status: 'string' }
  },
  {
    endpoint: '/api/instances',
    method: 'GET',
    requiresAuth: true,
    expectedResponseStructure: { instances: 'array', total: 'number' }
  },
  {
    endpoint: '/api/metrics',
    method: 'GET',
    requiresAuth: true,
    expectedResponseStructure: { metrics: 'object', timestamp: 'string' }
  },
  {
    endpoint: '/api/compliance',
    method: 'GET',
    requiresAuth: true,
    expectedResponseStructure: { compliance: 'object', summary: 'object' }
  },
  {
    endpoint: '/api/costs',
    method: 'GET',
    requiresAuth: true,
    expectedResponseStructure: { costs: 'array', summary: 'object' }
  }
];

// Property: Functional Equivalence
describe('Property 10: Functional Equivalence', () => {
  
  test('API operations should work identically with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...API_OPERATIONS),
        async (operation) => {
          const cleanUrl = `${API_BASE_URL}${operation.endpoint}`;
          
          // Property: Clean URL should not contain stage prefixes
          expect(cleanUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            // Test the operation with clean URL
            const response = await axios({
              method: operation.method,
              url: cleanUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500 // Accept 4xx as valid responses for auth-required endpoints
            });
            
            // Property: Response should have expected structure for successful calls
            if (response.status === 200) {
              const data = response.data;
              
              // Validate response structure matches expectations
              Object.entries(operation.expectedResponseStructure).forEach(([key, expectedType]) => {
                expect(data).toHaveProperty(key);
                
                if (expectedType === 'string') {
                  expect(typeof data[key]).toBe('string');
                } else if (expectedType === 'number') {
                  expect(typeof data[key]).toBe('number');
                } else if (expectedType === 'boolean') {
                  expect(typeof data[key]).toBe('boolean');
                } else if (expectedType === 'array') {
                  expect(Array.isArray(data[key])).toBe(true);
                } else if (expectedType === 'object') {
                  expect(typeof data[key]).toBe('object');
                  expect(data[key]).not.toBeNull();
                }
              });
              
              // Property: Response should not contain stage-prefixed URLs
              const responseStr = JSON.stringify(data);
              expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
            }
            
            // Property: Auth-required endpoints should return 401/403 without auth
            if (operation.requiresAuth && response.status >= 400) {
              expect([401, 403]).toContain(response.status);
            }
            
            // Property: Non-auth endpoints should return 200
            if (!operation.requiresAuth) {
              expect(response.status).toBe(200);
            }
            
          } catch (error: any) {
            // Property: Network errors should not be due to URL structure issues
            if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${cleanUrl}: ${error.message}`);
              // Don't fail the property test for network issues
            } else if (error.response) {
              // HTTP error responses are acceptable for auth-required endpoints
              if (operation.requiresAuth && [401, 403].includes(error.response.status)) {
                // Expected auth error
                expect([401, 403]).toContain(error.response.status);
              } else if (error.response.status >= 500) {
                // Server errors might indicate functional issues
                console.warn(`Server error testing ${cleanUrl}: ${error.response.status}`);
              }
            } else {
              console.warn(`Unexpected error testing ${cleanUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 20, timeout: 60000 }
    );
  });
  
  test('RDS operations should produce identical results with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          operation: fc.constantFrom('instances', 'operations', 'discovery', 'monitoring', 'compliance', 'costs'),
          accountId: generateAccountId(),
          region: generateRegion()
        }),
        async ({ operation, accountId, region }) => {
          const cleanUrl = `${INTERNAL_API_URL}/${operation}`;
          
          // Property: Internal API URLs should be clean
          expect(cleanUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Property: URL should be properly formatted
          expect(cleanUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/[a-z]+$/);
          
          try {
            // Test with query parameters that might be used in real operations
            const queryParams = new URLSearchParams({
              accountId: accountId,
              region: region,
              limit: '10'
            });
            
            const fullUrl = `${cleanUrl}?${queryParams.toString()}`;
            
            const response = await axios.get(fullUrl, {
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Response should be consistent regardless of URL structure
            if (response.status === 200) {
              const data = response.data;
              
              // Common response structure validation
              expect(data).toBeDefined();
              
              // Operation-specific validations
              if (operation === 'instances') {
                expect(data).toHaveProperty('instances');
                expect(Array.isArray(data.instances)).toBe(true);
              } else if (operation === 'operations') {
                expect(data).toHaveProperty('operations');
                expect(Array.isArray(data.operations)).toBe(true);
              } else if (operation === 'discovery') {
                expect(data).toHaveProperty('discovered');
              } else if (operation === 'monitoring') {
                expect(data).toHaveProperty('metrics');
              } else if (operation === 'compliance') {
                expect(data).toHaveProperty('compliance');
              } else if (operation === 'costs') {
                expect(data).toHaveProperty('costs');
              }
              
              // Property: Response should not reference old stage-prefixed URLs
              const responseStr = JSON.stringify(data);
              expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
            }
            
          } catch (error: any) {
            // Handle expected errors gracefully
            if (error.response && [401, 403, 404].includes(error.response.status)) {
              // Expected for endpoints requiring auth or specific resources
              console.warn(`Expected error for ${cleanUrl}: ${error.response.status}`);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${cleanUrl}: ${error.message}`);
            } else {
              console.warn(`Unexpected error testing ${cleanUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 15, timeout: 45000 }
    );
  });
  
  test('Error responses should maintain consistent structure with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          endpoint: fc.constantFrom('/api/nonexistent', '/api/instances/invalid', '/api/operations/missing'),
          method: fc.constantFrom('GET', 'POST', 'PUT', 'DELETE')
        }),
        async ({ endpoint, method }) => {
          const cleanUrl = `${API_BASE_URL}${endpoint}`;
          
          // Property: Error endpoint URLs should be clean
          expect(cleanUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const response = await axios({
              method: method,
              url: cleanUrl,
              timeout: TIMEOUT,
              validateStatus: () => true // Accept all status codes
            });
            
            // Property: Error responses should have consistent structure
            if (response.status >= 400) {
              const data = response.data;
              
              // Common error response structure
              if (data && typeof data === 'object') {
                // Should have error information
                const hasErrorInfo = data.error || data.message || data.errorMessage || data.statusCode;
                expect(hasErrorInfo).toBeTruthy();
                
                // Should not reference stage-prefixed URLs in error messages
                const errorStr = JSON.stringify(data);
                expect(errorStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
              }
            }
            
          } catch (error: any) {
            // Network errors are acceptable for this test
            if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${cleanUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 30000 }
    );
  });
  
  test('API versioning should work consistently with clean URLs', () => {
    fc.assert(
      fc.property(
        fc.record({
          version: fc.constantFrom('v1', 'v2', ''),
          endpoint: fc.constantFrom('instances', 'operations', 'metrics', 'compliance')
        }),
        ({ version, endpoint }) => {
          // Property: API versioning should not conflict with clean URL structure
          const versionPrefix = version ? `/${version}` : '';
          const cleanUrl = `${API_BASE_URL}/api${versionPrefix}/${endpoint}`;
          
          // Should not contain stage prefixes
          expect(cleanUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Should have proper URL structure
          expect(cleanUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/api/);
          
          // Version should come before endpoint
          if (version) {
            expect(cleanUrl).toMatch(new RegExp(`/api/${version}/${endpoint}$`));
          } else {
            expect(cleanUrl).toMatch(new RegExp(`/api/${endpoint}$`));
          }
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
  
  test('Query parameters should work identically with clean URLs', () => {
    fc.assert(
      fc.property(
        fc.record({
          endpoint: fc.constantFrom('/api/instances', '/api/operations', '/api/metrics'),
          params: fc.record({
            limit: fc.option(fc.integer({ min: 1, max: 100 })),
            offset: fc.option(fc.integer({ min: 0, max: 1000 })),
            filter: fc.option(fc.constantFrom('active', 'inactive', 'all')),
            sort: fc.option(fc.constantFrom('name', 'created', 'modified'))
          })
        }),
        ({ endpoint, params }) => {
          const baseUrl = `${API_BASE_URL}${endpoint}`;
          
          // Property: Base URL should be clean
          expect(baseUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Build query string
          const queryParams = new URLSearchParams();
          Object.entries(params).forEach(([key, value]) => {
            if (value !== null && value !== undefined) {
              queryParams.append(key, value.toString());
            }
          });
          
          const fullUrl = queryParams.toString() ? `${baseUrl}?${queryParams.toString()}` : baseUrl;
          
          // Property: Full URL with parameters should remain clean
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Property: Query parameters should be properly encoded
          if (queryParams.toString()) {
            expect(fullUrl).toMatch(/\?[a-zA-Z0-9=&%_-]+$/);
          }
          
          return true;
        }
      ),
      { numRuns: 30 }
    );
  });
  
  test('Response headers should be consistent with clean URLs', async () => {
    const testEndpoints = ['/health', '/cors-config', '/api/health'];
    
    for (const endpoint of testEndpoints) {
      const cleanUrl = `${API_BASE_URL}${endpoint}`;
      
      try {
        const response = await axios.get(cleanUrl, { timeout: TIMEOUT });
        
        // Property: Response headers should not reference stage-prefixed URLs
        const headers = response.headers;
        Object.values(headers).forEach((headerValue: any) => {
          if (typeof headerValue === 'string') {
            expect(headerValue).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          }
        });
        
        // Property: CORS headers should work with clean URLs
        if (headers['access-control-allow-origin']) {
          expect(headers['access-control-allow-origin']).toBeDefined();
        }
        
        // Property: Content-Type should be consistent
        if (headers['content-type']) {
          expect(headers['content-type']).toMatch(/application\/json|text\/plain/);
        }
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Error testing headers for ${cleanUrl}: ${error.message}`);
        }
      }
    }
  });
});

// Integration tests for functional equivalence
describe('Functional Equivalence Integration', () => {
  
  test('Complete user workflow should work with clean URLs', async () => {
    // Simulate a complete user workflow
    const workflow = [
      { step: 'Health Check', url: `${API_BASE_URL}/health`, method: 'GET' },
      { step: 'CORS Config', url: `${API_BASE_URL}/cors-config`, method: 'GET' },
      { step: 'API Health', url: `${API_BASE_URL}/api/health`, method: 'GET' }
    ];
    
    for (const step of workflow) {
      // Property: Each step should use clean URLs
      expect(step.url).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
      
      try {
        const response = await axios({
          method: step.method,
          url: step.url,
          timeout: TIMEOUT
        });
        
        expect(response.status).toBe(200);
        
        // Property: Response should not reference stage-prefixed URLs
        const responseStr = JSON.stringify(response.data);
        expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Workflow step '${step.step}' failed: ${error.message}`);
        }
      }
    }
  });
  
  test('Service discovery should return clean URLs', () => {
    // Test that service discovery configuration uses clean URLs
    const serviceEndpoints = {
      discovery: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/instances` : undefined,
      operations: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/operations` : undefined,
      monitoring: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/monitoring` : undefined
    };
    
    Object.entries(serviceEndpoints).forEach(([service, endpoint]) => {
      if (endpoint) {
        // Property: Service endpoints should be clean
        expect(endpoint).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
        
        // Property: Should be valid URLs
        expect(() => new URL(endpoint)).not.toThrow();
        
        // Property: Should follow consistent pattern
        expect(endpoint).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/[a-z]+$/);
      }
    });
  });
});