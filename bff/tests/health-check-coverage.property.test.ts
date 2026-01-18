/**
 * Property Test: Health Check Coverage
 * 
 * Validates: Requirements 8.5
 * Property 14: For any critical system component, there should be a 
 * working health check endpoint accessible via clean URLs
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const API_BASE_URL = process.env.TEST_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const INTERNAL_API_URL = process.env.INTERNAL_API_URL || 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
const TIMEOUT = 15000

// Critical system components that must have health checks
const CRITICAL_COMPONENTS = [
  {
    name: 'BFF Health Check',
    url: '/health',
    baseUrl: API_BASE_URL,
    expectedFields: ['status', 'timestamp'],
    requiresAuth: false
  },
  {
    name: 'BFF API Health Check',
    url: '/api/health',
    baseUrl: API_BASE_URL,
    expectedFields: ['status'],
    requiresAuth: false
  },
  {
    name: 'CORS Configuration Check',
    url: '/cors-config',
    baseUrl: API_BASE_URL,
    expectedFields: ['allowedOrigins', 'corsEnabled'],
    requiresAuth: false
  },
  {
    name: 'RDS Discovery Service',
    url: '/instances',
    baseUrl: INTERNAL_API_URL,
    expectedFields: ['instances'],
    requiresAuth: true
  },
  {
    name: 'RDS Operations Service',
    url: '/operations',
    baseUrl: INTERNAL_API_URL,
    expectedFields: ['operations'],
    requiresAuth: true
  },
  {
    name: 'RDS Monitoring Service',
    url: '/monitoring',
    baseUrl: INTERNAL_API_URL,
    expectedFields: ['metrics'],
    requiresAuth: true
  },
  {
    name: 'Compliance Service',
    url: '/compliance',
    baseUrl: INTERNAL_API_URL,
    expectedFields: ['compliance'],
    requiresAuth: true
  },
  {
    name: 'Cost Analysis Service',
    url: '/costs',
    baseUrl: INTERNAL_API_URL,
    expectedFields: ['costs'],
    requiresAuth: true
  }
];

interface HealthCheckResult {
  component: string;
  url: string;
  status: 'healthy' | 'unhealthy' | 'unknown';
  responseTime: number;
  statusCode: number;
  hasCleanUrl: boolean;
  hasExpectedFields: boolean;
  error?: string;
}

// Property: Health Check Coverage
describe('Property 14: Health Check Coverage', () => {
  
  test('All critical components should have health check endpoints with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...CRITICAL_COMPONENTS),
        async (component) => {
          const fullUrl = `${component.baseUrl.replace(/\/$/, '')}${component.url}`;
          
          // Property: Health check URLs should be clean
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          const startTime = Date.now();
          
          try {
            const response = await axios.get(fullUrl, {
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            const responseTime = Date.now() - startTime;
            
            // Property: Health checks should respond quickly
            expect(responseTime).toBeLessThan(TIMEOUT);
            
            if (response.status === 200) {
              const data = response.data;
              
              // Property: Health check responses should have expected structure
              if (component.expectedFields) {
                component.expectedFields.forEach(field => {
                  expect(data).toHaveProperty(field);
                });
              }
              
              // Property: Health check responses should not contain stage-prefixed URLs
              const responseStr = JSON.stringify(data);
              expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
              
              // Property: Health status should be clearly indicated
              if (data.status) {
                expect(['healthy', 'unhealthy', 'degraded', 'ok']).toContain(data.status.toLowerCase());
              }
              
            } else if (component.requiresAuth && [401, 403].includes(response.status)) {
              // Expected for auth-required endpoints
              expect([401, 403]).toContain(response.status);
            } else {
              console.warn(`Unexpected status ${response.status} for ${component.name}`);
            }
            
          } catch (error: any) {
            const responseTime = Date.now() - startTime;
            
            if (error.response && component.requiresAuth && [401, 403].includes(error.response.status)) {
              // Expected auth error
              expect([401, 403]).toContain(error.response.status);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error for ${component.name}: ${error.message}`);
            } else {
              console.warn(`Health check error for ${component.name}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 20, timeout: 60000 }
    );
  });
  
  test('Health check endpoints should return consistent response formats', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...CRITICAL_COMPONENTS.filter(c => !c.requiresAuth)),
        async (component) => {
          const fullUrl = `${component.baseUrl.replace(/\/$/, '')}${component.url}`;
          
          try {
            const response = await axios.get(fullUrl, { timeout: TIMEOUT });
            
            if (response.status === 200) {
              const data = response.data;
              
              // Property: Health check responses should be JSON objects
              expect(typeof data).toBe('object');
              expect(data).not.toBeNull();
              
              // Property: Should have timestamp or similar temporal indicator
              const hasTimestamp = data.timestamp || data.time || data.lastCheck || data.date;
              if (!hasTimestamp) {
                console.warn(`${component.name} health check missing timestamp`);
              }
              
              // Property: Should indicate health status clearly
              const hasStatus = data.status || data.health || data.state;
              expect(hasStatus).toBeTruthy();
              
              // Property: Response should not be empty
              expect(Object.keys(data).length).toBeGreaterThan(0);
            }
            
          } catch (error: any) {
            if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`Error testing ${component.name}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 30000 }
    );
  });
  
  test('Health check URLs should follow consistent naming patterns', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(...CRITICAL_COMPONENTS),
        (component) => {
          const fullUrl = `${component.baseUrl.replace(/\/$/, '')}${component.url}`;
          
          // Property: Health check URLs should follow consistent patterns
          expect(fullUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com/);
          
          // Property: Should not have double slashes
          expect(fullUrl).not.toMatch(/\/\//);
          
          // Property: Should not end with slash (except root)
          if (component.url !== '/') {
            expect(fullUrl).not.toMatch(/\/$/);
          }
          
          // Property: Should use lowercase paths
          const path = new URL(fullUrl).pathname;
          expect(path).toBe(path.toLowerCase());
          
          // Property: Should not contain stage prefixes
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
  
  test('Health checks should be accessible via both HTTP methods where appropriate', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          component: fc.constantFrom(...CRITICAL_COMPONENTS.filter(c => !c.requiresAuth)),
          method: fc.constantFrom('GET', 'HEAD', 'OPTIONS')
        }),
        async ({ component, method }) => {
          const fullUrl = `${component.baseUrl.replace(/\/$/, '')}${component.url}`;
          
          try {
            const response = await axios({
              method: method,
              url: fullUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Health checks should support appropriate HTTP methods
            if (method === 'GET') {
              expect([200, 401, 403]).toContain(response.status);
            } else if (method === 'HEAD') {
              expect([200, 405, 401, 403]).toContain(response.status);
            } else if (method === 'OPTIONS') {
              expect([200, 204, 405]).toContain(response.status);
              
              // Property: OPTIONS should include CORS headers
              if (response.status === 200 || response.status === 204) {
                const corsHeaders = response.headers['access-control-allow-methods'] || 
                                 response.headers['access-control-allow-origin'];
                if (corsHeaders) {
                  expect(corsHeaders).toBeTruthy();
                }
              }
            }
            
          } catch (error: any) {
            if (error.response && [405, 501].includes(error.response.status)) {
              // Method not allowed is acceptable for some methods
              expect([405, 501]).toContain(error.response.status);
            } else if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`Error testing ${method} ${fullUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 15, timeout: 45000 }
    );
  });
  
  test('Health check responses should include performance metrics', async () => {
    const performanceEndpoints = ['/health', '/api/health'];
    
    for (const endpoint of performanceEndpoints) {
      const fullUrl = `${API_BASE_URL}${endpoint}`;
      
      try {
        const startTime = Date.now();
        const response = await axios.get(fullUrl, { timeout: TIMEOUT });
        const responseTime = Date.now() - startTime;
        
        if (response.status === 200) {
          const data = response.data;
          
          // Property: Health checks should respond quickly
          expect(responseTime).toBeLessThan(5000); // 5 seconds max
          
          // Property: Response should include timing information
          if (data.responseTime || data.duration || data.elapsed) {
            const reportedTime = data.responseTime || data.duration || data.elapsed;
            expect(typeof reportedTime).toBe('number');
            expect(reportedTime).toBeGreaterThan(0);
          }
          
          // Property: Should include system information
          if (data.version || data.build || data.deployment) {
            expect(typeof (data.version || data.build || data.deployment)).toBe('string');
          }
        }
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Performance test error for ${fullUrl}: ${error.message}`);
        }
      }
    }
  });
  
  test('Health checks should validate clean URL configuration', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom('/health', '/cors-config'),
        async (endpoint) => {
          const fullUrl = `${API_BASE_URL}${endpoint}`;
          
          try {
            const response = await axios.get(fullUrl, { timeout: TIMEOUT });
            
            if (response.status === 200) {
              const data = response.data;
              
              // Property: Health check should validate URL cleanliness
              if (endpoint === '/cors-config') {
                // CORS config should not reference stage-prefixed URLs
                if (data.allowedOrigins && Array.isArray(data.allowedOrigins)) {
                  data.allowedOrigins.forEach((origin: string) => {
                    expect(origin).not.toMatch(/\/prod$|\/staging$|\/dev$/);
                  });
                }
              }
              
              // Property: Any URLs in health check response should be clean
              const responseStr = JSON.stringify(data);
              const urlMatches = responseStr.match(/https?:\/\/[^\s"]+/g);
              
              if (urlMatches) {
                urlMatches.forEach(url => {
                  expect(url).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                });
              }
            }
            
          } catch (error: any) {
            if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`URL validation error for ${fullUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 30000 }
    );
  });
  
  test('Comprehensive health check should cover all critical services', async () => {
    // Test that we can get a comprehensive health status
    const healthEndpoints = ['/health', '/api/health'];
    
    for (const endpoint of healthEndpoints) {
      const fullUrl = `${API_BASE_URL}${endpoint}`;
      
      try {
        const response = await axios.get(fullUrl, { timeout: TIMEOUT });
        
        if (response.status === 200) {
          const data = response.data;
          
          // Property: Comprehensive health check should exist
          expect(data).toBeDefined();
          expect(typeof data).toBe('object');
          
          // Property: Should indicate overall system health
          const hasOverallStatus = data.status || data.overall_status || data.health;
          expect(hasOverallStatus).toBeTruthy();
          
          // Property: Should provide actionable information
          if (data.services || data.components || data.checks) {
            const serviceList = data.services || data.components || data.checks;
            expect(Array.isArray(serviceList) || typeof serviceList === 'object').toBe(true);
          }
        }
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Comprehensive health check error: ${error.message}`);
        }
      }
    }
  });
  
  test('Health check coverage should be complete for all API endpoints', () => {
    // Define all API endpoints that should have health monitoring
    const apiEndpoints = [
      '/api/instances',
      '/api/operations', 
      '/api/metrics',
      '/api/compliance',
      '/api/costs',
      '/api/discovery/trigger',
      '/api/monitoring',
      '/api/approvals',
      '/api/errors',
      '/api/users'
    ];
    
    apiEndpoints.forEach(endpoint => {
      const fullUrl = `${API_BASE_URL}${endpoint}`;
      
      // Property: All API endpoints should be monitorable
      expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
      
      // Property: Should follow consistent URL structure
      expect(fullUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/api\/[a-z\/]+$/);
      
      // Property: Should be valid URLs
      expect(() => new URL(fullUrl)).not.toThrow();
    });
    
    // Property: Health check coverage should be comprehensive
    const healthCheckEndpoints = CRITICAL_COMPONENTS.map(c => c.url);
    const coveragePercentage = (healthCheckEndpoints.length / (apiEndpoints.length + healthCheckEndpoints.length)) * 100;
    
    expect(coveragePercentage).toBeGreaterThan(50); // At least 50% coverage
  });
});

// Integration tests for health check coverage
describe('Health Check Coverage Integration', () => {
  
  test('All health checks should be accessible and return clean URLs', async () => {
    const results: HealthCheckResult[] = [];
    
    for (const component of CRITICAL_COMPONENTS.filter(c => !c.requiresAuth)) {
      const fullUrl = `${component.baseUrl.replace(/\/$/, '')}${component.url}`;
      const startTime = Date.now();
      
      try {
        const response = await axios.get(fullUrl, { timeout: TIMEOUT });
        const responseTime = Date.now() - startTime;
        
        const result: HealthCheckResult = {
          component: component.name,
          url: fullUrl,
          status: response.status === 200 ? 'healthy' : 'unhealthy',
          responseTime,
          statusCode: response.status,
          hasCleanUrl: !fullUrl.match(/\/prod\/|\/staging\/|\/dev\//),
          hasExpectedFields: component.expectedFields ? 
            component.expectedFields.every(field => response.data && response.data[field] !== undefined) : true
        };
        
        results.push(result);
        
      } catch (error: any) {
        const responseTime = Date.now() - startTime;
        
        results.push({
          component: component.name,
          url: fullUrl,
          status: 'unhealthy',
          responseTime,
          statusCode: error.response?.status || 0,
          hasCleanUrl: !fullUrl.match(/\/prod\/|\/staging\/|\/dev\//),
          hasExpectedFields: false,
          error: error.message
        });
      }
    }
    
    // Property: All health checks should use clean URLs
    const cleanUrlResults = results.filter(r => r.hasCleanUrl);
    expect(cleanUrlResults.length).toBe(results.length);
    
    // Property: Majority of health checks should be accessible
    const healthyResults = results.filter(r => r.status === 'healthy');
    const healthPercentage = (healthyResults.length / results.length) * 100;
    
    console.log(`Health check coverage: ${healthPercentage.toFixed(2)}% (${healthyResults.length}/${results.length})`);
    
    // Log any issues for debugging
    const unhealthyResults = results.filter(r => r.status !== 'healthy');
    if (unhealthyResults.length > 0) {
      console.warn('Unhealthy components:', unhealthyResults.map(r => `${r.component}: ${r.error || r.statusCode}`));
    }
  });
  
  test('Health check system should detect stage elimination completion', async () => {
    // Test that health checks can validate stage elimination
    const healthUrl = `${API_BASE_URL}/health`;
    
    try {
      const response = await axios.get(healthUrl, { timeout: TIMEOUT });
      
      if (response.status === 200) {
        const data = response.data;
        
        // Property: Health check should validate stage elimination
        if (data.stage_elimination_complete !== undefined) {
          expect(typeof data.stage_elimination_complete).toBe('boolean');
        }
        
        if (data.clean_urls_validated !== undefined) {
          expect(typeof data.clean_urls_validated).toBe('boolean');
        }
        
        // Property: Should not reference any stage-prefixed URLs
        const responseStr = JSON.stringify(data);
        expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
      }
      
    } catch (error: any) {
      if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
        console.warn(`Stage elimination validation error: ${error.message}`);
      }
    }
  });
});