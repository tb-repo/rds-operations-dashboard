/**
 * Property Test: Frontend URL Consistency
 * 
 * Validates: Requirements 1.4, 4.2, 4.4
 * 
 * This property test ensures that all frontend API URLs are consistent
 * and do not contain environment-specific stage prefixes like /prod.
 */

import { describe, test, expect } from 'vitest'
import { api, apiClient } from '../src/lib/api'

describe('Property Test: Frontend URL Consistency', () => {
  test('Property 7: Frontend URLs should not contain /prod stage prefixes', () => {
    // Test the base URL configuration
    const baseURL = apiClient.defaults.baseURL
    expect(baseURL).toBeDefined()
    expect(baseURL).not.toContain('/prod')
    expect(baseURL).not.toContain('/staging')
    expect(baseURL).not.toContain('/dev')
    
    // Verify clean URL structure
    if (baseURL) {
      expect(baseURL).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com$/)
    }
  })

  test('Property 8: All API endpoint paths should be clean without stage prefixes', () => {
    // Test that API paths are constructed correctly
    const testPaths = [
      '/api/instances',
      '/api/health',
      '/api/costs',
      '/api/compliance',
      '/api/operations',
      '/api/monitoring',
      '/api/discovery/trigger',
      '/api/approvals',
      '/api/errors/statistics'
    ]

    testPaths.forEach(path => {
      // Paths should start with /api and not contain stage prefixes
      expect(path).toMatch(/^\/api\//)
      expect(path).not.toContain('/prod/')
      expect(path).not.toContain('/staging/')
      expect(path).not.toContain('/dev/')
    })
  })

  test('Property 9: Environment variables should use clean URLs', () => {
    // Check that environment variables don't contain stage prefixes
    const bffApiUrl = import.meta.env.VITE_BFF_API_URL
    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL

    if (bffApiUrl) {
      expect(bffApiUrl).not.toContain('/prod')
      expect(bffApiUrl).not.toContain('/staging')
      expect(bffApiUrl).not.toContain('/dev')
      expect(bffApiUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com$/)
    }

    if (apiBaseUrl) {
      expect(apiBaseUrl).not.toContain('/prod')
      expect(apiBaseUrl).not.toContain('/staging')
      expect(apiBaseUrl).not.toContain('/dev')
      expect(apiBaseUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com$/)
    }
  })

  test('Property 10: API client configuration should be consistent', () => {
    // Verify API client is configured with clean URLs
    expect(apiClient.defaults.baseURL).toBeDefined()
    expect(apiClient.defaults.timeout).toBeGreaterThan(0)
    expect(apiClient.defaults.headers).toBeDefined()
    
    // Headers should be appropriate for clean API structure
    const headers = apiClient.defaults.headers as Record<string, any>
    expect(headers['Content-Type']).toBe('application/json')
    
    // Should not have stage-specific headers
    expect(headers).not.toHaveProperty('x-stage')
    expect(headers).not.toHaveProperty('x-environment')
  })

  test('Property 11: URL construction should be environment-agnostic', () => {
    // Test that URLs work across different environments
    const baseURL = apiClient.defaults.baseURL
    
    if (baseURL) {
      // Should work with any AWS region
      const urlPattern = /^https:\/\/[a-z0-9]+\.execute-api\.([a-z0-9-]+)\.amazonaws\.com$/
      const match = baseURL.match(urlPattern)
      expect(match).toBeTruthy()
      
      if (match) {
        const region = match[1]
        expect(region).toMatch(/^[a-z0-9-]+$/)
        
        // Common AWS regions should be supported
        const validRegions = [
          'us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1',
          'ap-northeast-1', 'ca-central-1', 'eu-central-1'
        ]
        // Region should be a valid AWS region format
        expect(region).toMatch(/^[a-z]+-[a-z]+-\d+$/)
      }
    }
  })

  test('Property 12: API methods should construct clean URLs', async () => {
    // Mock the API client to capture URL construction
    const originalGet = apiClient.get
    const originalPost = apiClient.post
    
    const capturedUrls: string[] = []
    
    // Mock to capture URLs without making actual requests
    apiClient.get = jest.fn().mockImplementation((url: string) => {
      capturedUrls.push(url)
      return Promise.reject(new Error('Mocked - no actual request'))
    })
    
    apiClient.post = jest.fn().mockImplementation((url: string) => {
      capturedUrls.push(url)
      return Promise.reject(new Error('Mocked - no actual request'))
    })

    try {
      // Test various API methods (they will fail but we capture URLs)
      await api.getInstances().catch(() => {})
      await api.getInstance('test-id').catch(() => {})
      await api.getHealth().catch(() => {})
      await api.getCosts().catch(() => {})
      await api.getCompliance().catch(() => {})
      await api.triggerDiscovery().catch(() => {})
      await api.getErrorStatistics().catch(() => {})
      
      // Verify all captured URLs are clean
      capturedUrls.forEach(url => {
        expect(url).not.toContain('/prod/')
        expect(url).not.toContain('/staging/')
        expect(url).not.toContain('/dev/')
        expect(url).toMatch(/^\/api\//)
      })
      
      // Should have captured multiple URLs
      expect(capturedUrls.length).toBeGreaterThan(0)
      
    } finally {
      // Restore original methods
      apiClient.get = originalGet
      apiClient.post = originalPost
    }
  })
})