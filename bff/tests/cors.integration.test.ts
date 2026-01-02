/**
 * Integration Tests for CORS Configuration
 * 
 * Tests actual HTTP requests from different origins, browser preflight behavior,
 * authentication flow with CORS, and error scenarios end-to-end.
 */

import request from 'supertest'
import express from 'express'
import cors from 'cors'
import { initializeCorsConfig } from '../src/config/cors'
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

describe('CORS Integration Tests', () => {
  const originalEnv = process.env
  let app: express.Application

  beforeEach(() => {
    // Reset environment variables
    process.env = { ...originalEnv }
    delete process.env.CORS_ORIGINS
    delete process.env.FRONTEND_URL
    delete process.env.NODE_ENV
    
    // Reset mocks
    jest.clearAllMocks()
    
    // Create fresh Express app for each test
    app = express()
  })

  afterAll(() => {
    process.env = originalEnv
  })

  const setupApp = (corsOrigins?: string, nodeEnv?: string) => {
    if (corsOrigins) process.env.CORS_ORIGINS = corsOrigins
    if (nodeEnv) process.env.NODE_ENV = nodeEnv
    
    const corsConfig = initializeCorsConfig()
    app.use(cors(corsConfig.corsOptions))
    
    // Add test routes
    app.get('/api/test', (req, res) => {
      res.json({ message: 'Test endpoint', origin: req.get('Origin') })
    })
    
    app.post('/api/data', (req, res) => {
      res.json({ message: 'Data received', origin: req.get('Origin') })
    })
    
    app.get('/api/auth/user', (req, res) => {
      res.json({ user: 'test-user', authenticated: true })
    })
    
    return app
  }

  describe('CloudFront Origin Requests', () => {
    test('should allow requests from CloudFront origin', async () => {
      const testApp = setupApp('https://d2qvaswtmn22om.cloudfront.net', 'production')
      
      const response = await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://d2qvaswtmn22om.cloudfront.net')
        .expect(200)
      
      expect(response.headers['access-control-allow-origin']).toBe('https://d2qvaswtmn22om.cloudfront.net')
      expect(response.headers['access-control-allow-credentials']).toBe('true')
      expect(response.body.message).toBe('Test endpoint')
    })

    test('should include correct CORS headers in response', async () => {
      const testApp = setupApp('https://d2qvaswtmn22om.cloudfront.net', 'production')
      
      const response = await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://d2qvaswtmn22om.cloudfront.net')
        .expect(200)
      
      expect(response.headers['access-control-allow-origin']).toBe('https://d2qvaswtmn22om.cloudfront.net')
      expect(response.headers['access-control-allow-credentials']).toBe('true')
      expect(response.headers['access-control-expose-headers']).toContain('X-Total-Count')
    })

    test('should reject requests from unauthorized origins', async () => {
      const testApp = setupApp('https://d2qvaswtmn22om.cloudfront.net', 'production')
      
      await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://malicious.com')
        .expect(500) // CORS error results in 500
    })
  })

  describe('OPTIONS Preflight Requests', () => {
    test('should handle OPTIONS preflight requests correctly', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/data')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'POST')
        .set('Access-Control-Request-Headers', 'Content-Type,Authorization')
        .expect(200)
      
      expect(response.headers['access-control-allow-origin']).toBe('https://example.com')
      expect(response.headers['access-control-allow-methods']).toContain('POST')
      expect(response.headers['access-control-allow-headers']).toContain('Content-Type')
      expect(response.headers['access-control-allow-headers']).toContain('Authorization')
      expect(response.headers['access-control-max-age']).toBe('86400')
    })

    test('should handle complex preflight requests with custom headers', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/data')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'PUT')
        .set('Access-Control-Request-Headers', 'X-Api-Key,X-Requested-With')
        .expect(200)
      
      expect(response.headers['access-control-allow-methods']).toContain('PUT')
      expect(response.headers['access-control-allow-headers']).toContain('X-Api-Key')
      expect(response.headers['access-control-allow-headers']).toContain('X-Requested-With')
    })

    test('should reject preflight requests from unauthorized origins', async () => {
      const testApp = setupApp('https://example.com')
      
      await request(testApp)
        .options('/api/data')
        .set('Origin', 'https://malicious.com')
        .set('Access-Control-Request-Method', 'POST')
        .expect(500) // CORS error
    })
  })

  describe('Multiple Origins Configuration', () => {
    test('should allow requests from multiple configured origins', async () => {
      const testApp = setupApp('https://example.com,https://app.example.com,http://localhost:3000')
      
      // Test first origin
      const response1 = await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://example.com')
        .expect(200)
      
      expect(response1.headers['access-control-allow-origin']).toBe('https://example.com')
      
      // Test second origin
      const response2 = await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://app.example.com')
        .expect(200)
      
      expect(response2.headers['access-control-allow-origin']).toBe('https://app.example.com')
      
      // Test third origin
      const response3 = await request(testApp)
        .get('/api/test')
        .set('Origin', 'http://localhost:3000')
        .expect(200)
      
      expect(response3.headers['access-control-allow-origin']).toBe('http://localhost:3000')
    })

    test('should reject origins not in the allowlist', async () => {
      const testApp = setupApp('https://example.com,https://app.example.com')
      
      await request(testApp)
        .get('/api/test')
        .set('Origin', 'https://unauthorized.com')
        .expect(500)
    })
  })

  describe('Development Environment', () => {
    test('should allow localhost origins in development', async () => {
      const testApp = setupApp(undefined, 'development')
      
      const response = await request(testApp)
        .get('/api/test')
        .set('Origin', 'http://localhost:3000')
        .expect(200)
      
      expect(response.headers['access-control-allow-origin']).toBe('http://localhost:3000')
    })

    test('should allow multiple localhost ports in development', async () => {
      const testApp = setupApp(undefined, 'development')
      
      // Test port 3000
      const response1 = await request(testApp)
        .get('/api/test')
        .set('Origin', 'http://localhost:3000')
        .expect(200)
      
      expect(response1.headers['access-control-allow-origin']).toBe('http://localhost:3000')
      
      // Test port 5173
      const response2 = await request(testApp)
        .get('/api/test')
        .set('Origin', 'http://localhost:5173')
        .expect(200)
      
      expect(response2.headers['access-control-allow-origin']).toBe('http://localhost:5173')
    })
  })

  describe('Authentication Flow with CORS', () => {
    test('should allow authenticated requests with credentials', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .get('/api/auth/user')
        .set('Origin', 'https://example.com')
        .set('Authorization', 'Bearer test-token')
        .expect(200)
      
      expect(response.headers['access-control-allow-origin']).toBe('https://example.com')
      expect(response.headers['access-control-allow-credentials']).toBe('true')
      expect(response.body.authenticated).toBe(true)
    })

    test('should handle preflight for authenticated requests', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/auth/user')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'GET')
        .set('Access-Control-Request-Headers', 'Authorization')
        .expect(200)
      
      expect(response.headers['access-control-allow-headers']).toContain('Authorization')
      expect(response.headers['access-control-allow-credentials']).toBe('true')
    })
  })

  describe('Server-to-Server Requests', () => {
    test('should allow requests without Origin header', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .get('/api/test')
        // No Origin header set
        .expect(200)
      
      expect(response.body.message).toBe('Test endpoint')
      expect(response.body.origin).toBeUndefined()
    })

    test('should handle POST requests without Origin header', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .post('/api/data')
        .send({ data: 'test' })
        // No Origin header set
        .expect(200)
      
      expect(response.body.message).toBe('Data received')
    })
  })

  describe('Error Scenarios', () => {
    test('should handle malformed Origin headers gracefully', async () => {
      const testApp = setupApp('https://example.com')
      
      await request(testApp)
        .get('/api/test')
        .set('Origin', 'not-a-valid-url')
        .expect(500)
    })

    test('should handle suspicious Origin patterns', async () => {
      const testApp = setupApp('https://example.com')
      
      await request(testApp)
        .get('/api/test')
        .set('Origin', 'javascript:alert(1)')
        .expect(500)
    })

    test('should handle IP address origins', async () => {
      const testApp = setupApp('https://example.com')
      
      await request(testApp)
        .get('/api/test')
        .set('Origin', 'http://192.168.1.1:3000')
        .expect(500)
    })
  })

  describe('HTTP Methods Support', () => {
    test('should support all configured HTTP methods', async () => {
      const testApp = setupApp('https://example.com')
      
      // Add routes for different methods
      app.put('/api/test', (req, res) => res.json({ method: 'PUT' }))
      app.delete('/api/test', (req, res) => res.json({ method: 'DELETE' }))
      app.patch('/api/test', (req, res) => res.json({ method: 'PATCH' }))
      
      const methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
      
      for (const method of methods) {
        const response = await request(testApp)
          .options('/api/test')
          .set('Origin', 'https://example.com')
          .set('Access-Control-Request-Method', method)
          .expect(200)
        
        expect(response.headers['access-control-allow-methods']).toContain(method)
      }
    })
  })

  describe('Custom Headers Support', () => {
    test('should support AWS-specific headers', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/test')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'GET')
        .set('Access-Control-Request-Headers', 'X-Amz-Date,X-Amz-Security-Token')
        .expect(200)
      
      expect(response.headers['access-control-allow-headers']).toContain('X-Amz-Date')
      expect(response.headers['access-control-allow-headers']).toContain('X-Amz-Security-Token')
    })

    test('should support API key headers', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/test')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'GET')
        .set('Access-Control-Request-Headers', 'X-Api-Key')
        .expect(200)
      
      expect(response.headers['access-control-allow-headers']).toContain('X-Api-Key')
    })
  })

  describe('Response Headers Exposure', () => {
    test('should expose custom response headers', async () => {
      const testApp = setupApp('https://example.com')
      
      // Add route that sets custom headers
      app.get('/api/headers', (req, res) => {
        res.set('X-Total-Count', '100')
        res.set('X-Request-ID', 'test-123')
        res.set('X-RateLimit-Remaining', '99')
        res.json({ message: 'Headers test' })
      })
      
      const response = await request(testApp)
        .get('/api/headers')
        .set('Origin', 'https://example.com')
        .expect(200)
      
      const exposedHeaders = response.headers['access-control-expose-headers']
      expect(exposedHeaders).toContain('X-Total-Count')
      expect(exposedHeaders).toContain('X-Request-ID')
      expect(exposedHeaders).toContain('X-RateLimit-Remaining')
    })
  })

  describe('Preflight Cache', () => {
    test('should set correct preflight cache duration', async () => {
      const testApp = setupApp('https://example.com')
      
      const response = await request(testApp)
        .options('/api/test')
        .set('Origin', 'https://example.com')
        .set('Access-Control-Request-Method', 'POST')
        .expect(200)
      
      expect(response.headers['access-control-max-age']).toBe('86400') // 24 hours
    })
  })
})