/**
 * Jest test setup file
 * Configures global test environment and utilities
 */

// Set test environment variables
process.env.NODE_ENV = 'test'
process.env.LOG_LEVEL = 'error' // Reduce log noise during tests
process.env.COGNITO_USER_POOL_ID = 'test-pool-id'
process.env.COGNITO_REGION = 'us-east-1'
process.env.INTERNAL_API_URL = 'https://test-api.example.com'
process.env.FRONTEND_URL = 'https://test-frontend.example.com'

// Increase timeout for property-based tests
jest.setTimeout(30000)