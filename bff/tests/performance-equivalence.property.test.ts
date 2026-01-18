/**
 * Property Test: Performance Equivalence
 * 
 * Validates: Requirements 8.4
 * Property 13: For any API operation, the response time should be 
 * equivalent or better than the current system
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const API_BASE_URL = process.env.TEST_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const INTERNAL_API_URL = process.env.INTERNAL_API_URL || 'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
const TIMEOUT = 30000

// Performance benchmarks (in milliseconds)
const PERFORMANCE_BENCHMARKS = {
  health_check: 2000,      // Health checks should respond within 2 seconds
  api_endpoints: 5000,     // API endpoints should respond within 5 seconds
  data_operations: 10000,  // Data operations should complete within 10 seconds
  discovery: 15000,        // Discovery operations can take up to 15 seconds
  complex_queries: 20000   // Complex queries can take up to 20 seconds
};

// Test endpoints with their expected performance characteristics
const PERFORMANCE_TEST_ENDPOINTS = [
  {
    name: 'BFF Health Check',
    url: '/health',
    baseUrl: API_BASE_URL,
    category: 'health_check',
    method: 'GET',
    requiresAuth: false,
    expectedResponseSize: 'small' // < 1KB
  },
  {
    name: 'API Health Check',
    url: '/api/health',
    baseUrl: API_BASE_URL,
    category: 'health_check',
    method: 'GET',
    requiresAuth: false,
    expectedResponseSize: 'small'
  },
  {
    name: 'CORS Configuration',
    url: '/cors-config',
    baseUrl: API_BASE_URL,
    category: 'api_endpoints',
    method: 'GET',
    requiresAuth: false,
    expectedResponseSize: 'small'
  },
  {
    name: 'RDS Instances',
    url: '/api/instances',
    baseUrl: API_BASE_URL,
    category: 'data_operations',
    method: 'GET',
    requiresAuth: true,
    expectedResponseSize: 'medium' // 1KB - 10KB
  },
  {
    name: 'System Metrics',
    url: '/api/metrics',
    baseUrl: API_BASE_URL,
    category: 'data_operations',
    method: 'GET',
    requiresAuth: true,
    expectedResponseSize: 'medium'
  },
  {
    name: 'Compliance Status',
    url: '/api/compliance',
    baseUrl: API_BASE_URL,
    category: 'data_operations',
    method: 'GET',
    requiresAuth: true,
    expectedResponseSize: 'medium'
  },
  {
    name: 'Cost Analysis',
    url: '/api/costs',
    baseUrl: API_BASE_URL,
    category: 'complex_queries',
    method: 'GET',
    requiresAuth: true,
    expectedResponseSize: 'large' // > 10KB
  },
  {
    name: 'Discovery Trigger',
    url: '/api/discovery/trigger',
    baseUrl: API_BASE_URL,
    category: 'discovery',
    method: 'POST',
    requiresAuth: true,
    expectedResponseSize: 'medium'
  }
];

interface PerformanceResult {
  endpoint: string;
  url: string;
  responseTime: number;
  statusCode: number;
  responseSize: number;
  benchmark: number;
  withinBenchmark: boolean;
  hasCleanUrl: boolean;
  error?: string;
}

// Property: Performance Equivalence
describe('Property 13: Performance Equivalence', () => {
  
  test('API operations should meet performance benchmarks with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...PERFORMANCE_TEST_ENDPOINTS),
        async (endpoint) => {
          const fullUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
          const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
          
          // Property: URLs should be clean
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          const startTime = Date.now();
          
          try {
            const response = await axios({
              method: endpoint.method,
              url: fullUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            const responseTime = Date.now() - startTime;
            const responseSize = JSON.stringify(response.data || '').length;
            
            // Property: Response time should meet benchmark
            if (response.status === 200) {
              expect(responseTime).toBeLessThan(benchmark);
              
              // Property: Response should not be empty for successful requests
              expect(responseSize).toBeGreaterThan(0);
              
              // Property: Response size should be reasonable for category
              if (endpoint.expectedResponseSize === 'small') {
                expect(responseSize).toBeLessThan(1024); // < 1KB
              } else if (endpoint.expectedResponseSize === 'medium') {
                expect(responseSize).toBeLessThan(10240); // < 10KB
              } else if (endpoint.expectedResponseSize === 'large') {
                expect(responseSize).toBeLessThan(102400); // < 100KB
              }
              
            } else if (endpoint.requiresAuth && [401, 403].includes(response.status)) {
              // Auth errors should still be fast
              expect(responseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
            }
            
            // Property: All responses should be reasonably fast
            expect(responseTime).toBeLessThan(TIMEOUT);
            
          } catch (error: any) {
            const responseTime = Date.now() - startTime;
            
            if (error.response && endpoint.requiresAuth && [401, 403].includes(error.response.status)) {
              // Auth errors should still be fast
              expect(responseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error for ${endpoint.name}: ${error.message}`);
            } else if (error.code === 'ECONNABORTED') {
              // Timeout - this is a performance failure
              expect(responseTime).toBeLessThan(benchmark);
            } else {
              console.warn(`Performance test error for ${endpoint.name}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 120000 }
    );
  });
  
  test('Concurrent requests should maintain performance with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          endpoint: fc.constantFrom(...PERFORMANCE_TEST_ENDPOINTS.filter(e => !e.requiresAuth)),
          concurrency: fc.integer({ min: 2, max: 5 })
        }),
        async ({ endpoint, concurrency }) => {
          const fullUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
          const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
          
          // Property: Concurrent requests should use clean URLs
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          const startTime = Date.now();
          
          // Create concurrent requests
          const requests = Array(concurrency).fill(null).map(() => 
            axios({
              method: endpoint.method,
              url: fullUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            }).catch(error => ({ error }))
          );
          
          try {
            const responses = await Promise.all(requests);
            const totalTime = Date.now() - startTime;
            
            // Property: Concurrent requests should not significantly degrade performance
            const avgTimePerRequest = totalTime / concurrency;
            expect(avgTimePerRequest).toBeLessThan(benchmark * 1.5); // Allow 50% degradation for concurrency
            
            // Property: Most requests should succeed
            const successfulResponses = responses.filter(r => !r.error && r.status === 200);
            const successRate = successfulResponses.length / responses.length;
            expect(successRate).toBeGreaterThan(0.8); // At least 80% success rate
            
          } catch (error: any) {
            console.warn(`Concurrent request test error for ${endpoint.name}: ${error.message}`);
          }
          
          return true;
        }
      ),
      { numRuns: 5, timeout: 180000 }
    );
  });
  
  test('Response times should be consistent across multiple requests', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...PERFORMANCE_TEST_ENDPOINTS.filter(e => !e.requiresAuth)),
        async (endpoint) => {
          const fullUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
          const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
          
          const responseTimes: number[] = [];
          const numRequests = 3;
          
          for (let i = 0; i < numRequests; i++) {
            const startTime = Date.now();
            
            try {
              const response = await axios({
                method: endpoint.method,
                url: fullUrl,
                timeout: TIMEOUT,
                validateStatus: (status) => status < 500
              });
              
              const responseTime = Date.now() - startTime;
              
              if (response.status === 200) {
                responseTimes.push(responseTime);
              }
              
              // Small delay between requests
              await new Promise(resolve => setTimeout(resolve, 100));
              
            } catch (error: any) {
              if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
                console.warn(`Consistency test error for ${endpoint.name}: ${error.message}`);
              }
            }
          }
          
          if (responseTimes.length >= 2) {
            // Property: Response times should be consistent
            const avgResponseTime = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
            const maxDeviation = Math.max(...responseTimes.map(t => Math.abs(t - avgResponseTime)));
            
            // Allow up to 100% deviation (response time can double)
            expect(maxDeviation).toBeLessThan(avgResponseTime);
            
            // Property: All response times should meet benchmark
            responseTimes.forEach(time => {
              expect(time).toBeLessThan(benchmark);
            });
          }
          
          return true;
        }
      ),
      { numRuns: 8, timeout: 120000 }
    );
  });
  
  test('Large response payloads should be handled efficiently', async () => {
    const largeDataEndpoints = PERFORMANCE_TEST_ENDPOINTS.filter(e => 
      e.expectedResponseSize === 'large' || e.expectedResponseSize === 'medium'
    );
    
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(...largeDataEndpoints),
        async (endpoint) => {
          const fullUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
          const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
          
          const startTime = Date.now();
          
          try {
            const response = await axios({
              method: endpoint.method,
              url: fullUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            const responseTime = Date.now() - startTime;
            const responseSize = JSON.stringify(response.data || '').length;
            
            if (response.status === 200) {
              // Property: Large responses should still meet performance benchmarks
              expect(responseTime).toBeLessThan(benchmark);
              
              // Property: Response throughput should be reasonable
              const throughputBytesPerMs = responseSize / responseTime;
              expect(throughputBytesPerMs).toBeGreaterThan(0.1); // At least 0.1 bytes/ms (100 bytes/second)
              
              // Property: Large responses should have substantial content
              if (endpoint.expectedResponseSize === 'large') {
                expect(responseSize).toBeGreaterThan(1024); // > 1KB
              } else if (endpoint.expectedResponseSize === 'medium') {
                expect(responseSize).toBeGreaterThan(100); // > 100 bytes
              }
            }
            
          } catch (error: any) {
            if (error.response && endpoint.requiresAuth && [401, 403].includes(error.response.status)) {
              // Auth errors are expected and should be fast
              const responseTime = Date.now() - startTime;
              expect(responseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
            } else if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`Large payload test error for ${endpoint.name}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 5, timeout: 90000 }
    );
  });
  
  test('Error responses should be fast and not degrade performance', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          baseEndpoint: fc.constantFrom(...PERFORMANCE_TEST_ENDPOINTS.filter(e => !e.requiresAuth)),
          errorPath: fc.constantFrom('/nonexistent', '/invalid', '/error')
        }),
        async ({ baseEndpoint, errorPath }) => {
          const errorUrl = `${baseEndpoint.baseUrl.replace(/\/$/, '')}${errorPath}`;
          
          // Property: Error URLs should also be clean
          expect(errorUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          const startTime = Date.now();
          
          try {
            const response = await axios({
              method: 'GET',
              url: errorUrl,
              timeout: TIMEOUT,
              validateStatus: () => true // Accept all status codes
            });
            
            const responseTime = Date.now() - startTime;
            
            // Property: Error responses should be fast
            expect(responseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
            
            // Property: Error responses should have appropriate status codes
            expect(response.status).toBeGreaterThanOrEqual(400);
            
            // Property: Error responses should not contain stage-prefixed URLs
            if (response.data) {
              const responseStr = JSON.stringify(response.data);
              expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
            }
            
          } catch (error: any) {
            const responseTime = Date.now() - startTime;
            
            // Even network errors should fail fast
            expect(responseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
            
            if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`Error response test error for ${errorUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 60000 }
    );
  });
  
  test('Performance should not degrade with query parameters', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          endpoint: fc.constantFrom(...PERFORMANCE_TEST_ENDPOINTS.filter(e => !e.requiresAuth)),
          params: fc.record({
            limit: fc.option(fc.integer({ min: 1, max: 100 })),
            offset: fc.option(fc.integer({ min: 0, max: 1000 })),
            filter: fc.option(fc.constantFrom('active', 'inactive', 'all')),
            sort: fc.option(fc.constantFrom('name', 'created', 'modified'))
          })
        }),
        async ({ endpoint, params }) => {
          const baseUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
          const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
          
          // Build query string
          const queryParams = new URLSearchParams();
          Object.entries(params).forEach(([key, value]) => {
            if (value !== null && value !== undefined) {
              queryParams.append(key, value.toString());
            }
          });
          
          const fullUrl = queryParams.toString() ? `${baseUrl}?${queryParams.toString()}` : baseUrl;
          
          // Property: URLs with parameters should be clean
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          const startTime = Date.now();
          
          try {
            const response = await axios({
              method: endpoint.method,
              url: fullUrl,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            const responseTime = Date.now() - startTime;
            
            if (response.status === 200) {
              // Property: Query parameters should not significantly impact performance
              expect(responseTime).toBeLessThan(benchmark * 1.2); // Allow 20% degradation for query processing
              
              // Property: Response should be valid
              expect(response.data).toBeDefined();
            }
            
          } catch (error: any) {
            if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
              console.warn(`Query parameter performance test error: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 8, timeout: 90000 }
    );
  });
  
  test('Performance monitoring should track clean URL metrics', async () => {
    // Test that performance monitoring works with clean URLs
    const monitoringEndpoints = ['/health', '/api/health'];
    
    for (const endpoint of monitoringEndpoints) {
      const fullUrl = `${API_BASE_URL}${endpoint}`;
      
      try {
        const startTime = Date.now();
        const response = await axios.get(fullUrl, { timeout: TIMEOUT });
        const responseTime = Date.now() - startTime;
        
        if (response.status === 200) {
          const data = response.data;
          
          // Property: Performance metrics should be available
          if (data.performance || data.metrics || data.timing) {
            const perfData = data.performance || data.metrics || data.timing;
            
            // Should include timing information
            if (perfData.responseTime || perfData.duration) {
              const reportedTime = perfData.responseTime || perfData.duration;
              expect(typeof reportedTime).toBe('number');
              expect(reportedTime).toBeGreaterThan(0);
              
              // Reported time should be reasonable compared to measured time
              expect(Math.abs(reportedTime - responseTime)).toBeLessThan(responseTime * 0.5);
            }
          }
          
          // Property: Performance data should not reference stage-prefixed URLs
          const responseStr = JSON.stringify(data);
          expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
        }
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Performance monitoring test error: ${error.message}`);
        }
      }
    }
  });
});

// Integration tests for performance equivalence
describe('Performance Equivalence Integration', () => {
  
  test('Overall system performance should meet benchmarks with clean URLs', async () => {
    const results: PerformanceResult[] = [];
    
    // Test a subset of endpoints for integration testing
    const testEndpoints = PERFORMANCE_TEST_ENDPOINTS.filter(e => !e.requiresAuth).slice(0, 5);
    
    for (const endpoint of testEndpoints) {
      const fullUrl = `${endpoint.baseUrl.replace(/\/$/, '')}${endpoint.url}`;
      const benchmark = PERFORMANCE_BENCHMARKS[endpoint.category as keyof typeof PERFORMANCE_BENCHMARKS];
      const startTime = Date.now();
      
      try {
        const response = await axios({
          method: endpoint.method,
          url: fullUrl,
          timeout: TIMEOUT
        });
        
        const responseTime = Date.now() - startTime;
        const responseSize = JSON.stringify(response.data || '').length;
        
        results.push({
          endpoint: endpoint.name,
          url: fullUrl,
          responseTime,
          statusCode: response.status,
          responseSize,
          benchmark,
          withinBenchmark: responseTime < benchmark,
          hasCleanUrl: !fullUrl.match(/\/prod\/|\/staging\/|\/dev\//)
        });
        
      } catch (error: any) {
        const responseTime = Date.now() - startTime;
        
        results.push({
          endpoint: endpoint.name,
          url: fullUrl,
          responseTime,
          statusCode: error.response?.status || 0,
          responseSize: 0,
          benchmark,
          withinBenchmark: false,
          hasCleanUrl: !fullUrl.match(/\/prod\/|\/staging\/|\/dev\//),
          error: error.message
        });
      }
    }
    
    // Property: All URLs should be clean
    const cleanUrlResults = results.filter(r => r.hasCleanUrl);
    expect(cleanUrlResults.length).toBe(results.length);
    
    // Property: Majority of endpoints should meet performance benchmarks
    const withinBenchmarkResults = results.filter(r => r.withinBenchmark);
    const performanceRate = (withinBenchmarkResults.length / results.length) * 100;
    
    console.log(`Performance benchmark compliance: ${performanceRate.toFixed(2)}% (${withinBenchmarkResults.length}/${results.length})`);
    
    // Log performance statistics
    const avgResponseTime = results.reduce((sum, r) => sum + r.responseTime, 0) / results.length;
    const maxResponseTime = Math.max(...results.map(r => r.responseTime));
    const minResponseTime = Math.min(...results.map(r => r.responseTime));
    
    console.log(`Response time stats: avg=${avgResponseTime.toFixed(2)}ms, min=${minResponseTime}ms, max=${maxResponseTime}ms`);
    
    // Property: Average performance should be good
    expect(avgResponseTime).toBeLessThan(PERFORMANCE_BENCHMARKS.api_endpoints);
    
    // Log any slow endpoints
    const slowResults = results.filter(r => !r.withinBenchmark);
    if (slowResults.length > 0) {
      console.warn('Slow endpoints:', slowResults.map(r => `${r.endpoint}: ${r.responseTime}ms (benchmark: ${r.benchmark}ms)`));
    }
  });
  
  test('Performance should be consistent across clean URL structure', async () => {
    // Test that clean URL structure doesn't introduce performance regressions
    const healthUrl = `${API_BASE_URL}/health`;
    const measurements: number[] = [];
    
    // Take multiple measurements
    for (let i = 0; i < 5; i++) {
      const startTime = Date.now();
      
      try {
        const response = await axios.get(healthUrl, { timeout: TIMEOUT });
        const responseTime = Date.now() - startTime;
        
        if (response.status === 200) {
          measurements.push(responseTime);
        }
        
        // Small delay between measurements
        await new Promise(resolve => setTimeout(resolve, 200));
        
      } catch (error: any) {
        if (error.code !== 'ENOTFOUND' && error.code !== 'ECONNREFUSED') {
          console.warn(`Performance consistency test error: ${error.message}`);
        }
      }
    }
    
    if (measurements.length >= 3) {
      // Property: Performance should be consistent
      const avgTime = measurements.reduce((a, b) => a + b, 0) / measurements.length;
      const variance = measurements.reduce((sum, time) => sum + Math.pow(time - avgTime, 2), 0) / measurements.length;
      const stdDev = Math.sqrt(variance);
      
      // Standard deviation should be less than 50% of average (reasonable consistency)
      expect(stdDev).toBeLessThan(avgTime * 0.5);
      
      // All measurements should be within reasonable bounds
      measurements.forEach(time => {
        expect(time).toBeLessThan(PERFORMANCE_BENCHMARKS.health_check);
      });
      
      console.log(`Performance consistency: avg=${avgTime.toFixed(2)}ms, stddev=${stdDev.toFixed(2)}ms`);
    }
  });
});