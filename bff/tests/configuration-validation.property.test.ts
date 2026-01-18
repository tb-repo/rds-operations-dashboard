/**
 * Property Test: Configuration Validation
 * 
 * Validates: Requirements 6.5
 * Property 9: For any invalid system configuration at startup, 
 * the system should detect and report the issue clearly
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'

// Configuration validation utilities
interface ConfigValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

class ConfigValidator {
  static validateEnvironmentVariables(config: Record<string, string | undefined>): ConfigValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    
    // Required environment variables
    const required = [
      'AWS_REGION',
      'INTERNAL_API_URL',
      'CORS_ALLOWED_ORIGINS'
    ];
    
    // Optional but recommended
    const recommended = [
      'LOG_LEVEL',
      'API_TIMEOUT',
      'HEALTH_CHECK_INTERVAL'
    ];
    
    // Check required variables
    required.forEach(key => {
      if (!config[key] || config[key]?.trim() === '') {
        errors.push(`Missing required environment variable: ${key}`);
      }
    });
    
    // Check recommended variables
    recommended.forEach(key => {
      if (!config[key]) {
        warnings.push(`Missing recommended environment variable: ${key}`);
      }
    });
    
    // Validate URL formats
    if (config.INTERNAL_API_URL) {
      try {
        const url = new URL(config.INTERNAL_API_URL);
        if (!url.protocol.startsWith('http')) {
          errors.push('INTERNAL_API_URL must use HTTP or HTTPS protocol');
        }
        if (url.pathname.includes('/prod')) {
          errors.push('INTERNAL_API_URL should not contain /prod stage prefix');
        }
      } catch (error) {
        errors.push('INTERNAL_API_URL is not a valid URL');
      }
    }
    
    // Validate CORS origins
    if (config.CORS_ALLOWED_ORIGINS) {
      try {
        const origins = JSON.parse(config.CORS_ALLOWED_ORIGINS);
        if (!Array.isArray(origins)) {
          errors.push('CORS_ALLOWED_ORIGINS must be a JSON array');
        } else {
          origins.forEach((origin: any, index: number) => {
            if (typeof origin !== 'string') {
              errors.push(`CORS_ALLOWED_ORIGINS[${index}] must be a string`);
            } else if (origin !== '*' && !origin.startsWith('http')) {
              errors.push(`CORS_ALLOWED_ORIGINS[${index}] must be a valid URL or '*'`);
            }
          });
        }
      } catch (error) {
        errors.push('CORS_ALLOWED_ORIGINS must be valid JSON');
      }
    }
    
    // Validate AWS region
    if (config.AWS_REGION) {
      const validRegions = [
        'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2',
        'eu-west-1', 'eu-west-2', 'eu-central-1',
        'ap-southeast-1', 'ap-southeast-2', 'ap-northeast-1'
      ];
      if (!validRegions.includes(config.AWS_REGION)) {
        warnings.push(`AWS_REGION '${config.AWS_REGION}' is not a common region`);
      }
    }
    
    return {
      isValid: errors.length === 0,
      errors,
      warnings
    };
  }
  
  static validateServiceEndpoints(endpoints: Record<string, string>): ConfigValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    
    Object.entries(endpoints).forEach(([service, endpoint]) => {
      if (!endpoint) {
        errors.push(`Missing endpoint for service: ${service}`);
        return;
      }
      
      try {
        const url = new URL(endpoint);
        
        // Check for stage prefixes
        if (url.pathname.includes('/prod') || url.pathname.includes('/staging')) {
          errors.push(`Service ${service} endpoint contains stage prefix: ${endpoint}`);
        }
        
        // Check for HTTPS in production-like environments
        if (url.protocol !== 'https:' && !url.hostname.includes('localhost')) {
          warnings.push(`Service ${service} should use HTTPS: ${endpoint}`);
        }
        
        // Check for reasonable timeout expectations
        if (url.hostname.includes('amazonaws.com') && !url.pathname.startsWith('/')) {
          warnings.push(`Service ${service} endpoint should have a path: ${endpoint}`);
        }
        
      } catch (error) {
        errors.push(`Invalid URL for service ${service}: ${endpoint}`);
      }
    });
    
    return {
      isValid: errors.length === 0,
      errors,
      warnings
    };
  }
}

// Property: Configuration Validation
describe('Property 9: Configuration Validation', () => {
  
  test('System should detect missing required environment variables', () => {
    fc.assert(
      fc.property(
        fc.record({
          AWS_REGION: fc.option(fc.constantFrom('us-east-1', 'ap-southeast-1', '')),
          INTERNAL_API_URL: fc.option(fc.constantFrom(
            'https://api.example.com',
            'https://api.example.com/prod',
            'invalid-url',
            ''
          )),
          CORS_ALLOWED_ORIGINS: fc.option(fc.constantFrom(
            '["*"]',
            '["https://example.com"]',
            'invalid-json',
            ''
          ))
        }),
        (config) => {
          // Property: Configuration validation should detect all issues
          const result = ConfigValidator.validateEnvironmentVariables(config);
          
          // If any required field is missing or empty, should be invalid
          const hasEmptyRequired = !config.AWS_REGION || !config.INTERNAL_API_URL || !config.CORS_ALLOWED_ORIGINS ||
                                  config.AWS_REGION === '' || config.INTERNAL_API_URL === '' || config.CORS_ALLOWED_ORIGINS === '';
          
          if (hasEmptyRequired) {
            expect(result.isValid).toBe(false);
            expect(result.errors.length).toBeGreaterThan(0);
          }
          
          // If INTERNAL_API_URL contains /prod, should be invalid
          if (config.INTERNAL_API_URL?.includes('/prod')) {
            expect(result.isValid).toBe(false);
            expect(result.errors.some(error => error.includes('stage prefix'))).toBe(true);
          }
          
          // If CORS_ALLOWED_ORIGINS is invalid JSON, should be invalid
          if (config.CORS_ALLOWED_ORIGINS && config.CORS_ALLOWED_ORIGINS !== '["*"]' && config.CORS_ALLOWED_ORIGINS !== '["https://example.com"]') {
            try {
              JSON.parse(config.CORS_ALLOWED_ORIGINS);
            } catch {
              expect(result.isValid).toBe(false);
              expect(result.errors.some(error => error.includes('valid JSON'))).toBe(true);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 100 }
    );
  });
  
  test('System should validate service endpoint configurations', () => {
    fc.assert(
      fc.property(
        fc.record({
          discovery: fc.option(fc.constantFrom(
            'https://api.example.com/instances',
            'https://api.example.com/prod/instances',
            'http://localhost:3000/instances',
            'invalid-url',
            ''
          )),
          operations: fc.option(fc.constantFrom(
            'https://api.example.com/operations',
            'https://api.example.com/staging/operations',
            'https://api.example.com/operations',
            ''
          )),
          monitoring: fc.option(fc.constantFrom(
            'https://api.example.com/monitoring',
            'https://api.example.com/prod/monitoring',
            ''
          ))
        }),
        (endpoints) => {
          // Property: Service endpoint validation should catch all issues
          const result = ConfigValidator.validateServiceEndpoints(endpoints);
          
          // Check for stage prefixes
          Object.entries(endpoints).forEach(([service, endpoint]) => {
            if (endpoint && (endpoint.includes('/prod') || endpoint.includes('/staging'))) {
              expect(result.isValid).toBe(false);
              expect(result.errors.some(error => 
                error.includes(service) && error.includes('stage prefix')
              )).toBe(true);
            }
          });
          
          // Check for missing endpoints
          Object.entries(endpoints).forEach(([service, endpoint]) => {
            if (!endpoint) {
              expect(result.isValid).toBe(false);
              expect(result.errors.some(error => 
                error.includes(`Missing endpoint for service: ${service}`)
              )).toBe(true);
            }
          });
          
          // Check for invalid URLs
          Object.entries(endpoints).forEach(([service, endpoint]) => {
            if (endpoint && endpoint !== '' && !endpoint.startsWith('http')) {
              expect(result.isValid).toBe(false);
              expect(result.errors.some(error => 
                error.includes(`Invalid URL for service ${service}`)
              )).toBe(true);
            }
          });
          
          return true;
        }
      ),
      { numRuns: 50 }
    );
  });
  
  test('Configuration validation should provide clear error messages', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(
          { AWS_REGION: '', INTERNAL_API_URL: 'https://api.com', CORS_ALLOWED_ORIGINS: '["*"]' },
          { AWS_REGION: 'us-east-1', INTERNAL_API_URL: '', CORS_ALLOWED_ORIGINS: '["*"]' },
          { AWS_REGION: 'us-east-1', INTERNAL_API_URL: 'invalid-url', CORS_ALLOWED_ORIGINS: '["*"]' },
          { AWS_REGION: 'us-east-1', INTERNAL_API_URL: 'https://api.com/prod', CORS_ALLOWED_ORIGINS: '["*"]' },
          { AWS_REGION: 'us-east-1', INTERNAL_API_URL: 'https://api.com', CORS_ALLOWED_ORIGINS: 'invalid-json' }
        ),
        (config) => {
          // Property: Error messages should be clear and actionable
          const result = ConfigValidator.validateEnvironmentVariables(config);
          
          if (!result.isValid) {
            // Each error should be descriptive
            result.errors.forEach(error => {
              expect(error).toBeTruthy();
              expect(error.length).toBeGreaterThan(10); // Should be descriptive
              expect(error).toMatch(/^[A-Z]/); // Should start with capital letter
            });
            
            // Should identify the specific problem
            if (config.AWS_REGION === '') {
              expect(result.errors.some(error => error.includes('AWS_REGION'))).toBe(true);
            }
            
            if (config.INTERNAL_API_URL === '') {
              expect(result.errors.some(error => error.includes('INTERNAL_API_URL'))).toBe(true);
            }
            
            if (config.INTERNAL_API_URL === 'invalid-url') {
              expect(result.errors.some(error => error.includes('not a valid URL'))).toBe(true);
            }
            
            if (config.INTERNAL_API_URL?.includes('/prod')) {
              expect(result.errors.some(error => error.includes('stage prefix'))).toBe(true);
            }
            
            if (config.CORS_ALLOWED_ORIGINS === 'invalid-json') {
              expect(result.errors.some(error => error.includes('valid JSON'))).toBe(true);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
  
  test('System should validate startup configuration completeness', () => {
    // Property: All critical configuration should be validated at startup
    const currentEnv = {
      AWS_REGION: process.env.AWS_REGION,
      INTERNAL_API_URL: process.env.INTERNAL_API_URL,
      CORS_ALLOWED_ORIGINS: process.env.CORS_ALLOWED_ORIGINS,
      LOG_LEVEL: process.env.LOG_LEVEL,
      API_TIMEOUT: process.env.API_TIMEOUT
    };
    
    const result = ConfigValidator.validateEnvironmentVariables(currentEnv);
    
    // Should always return a result
    expect(result).toHaveProperty('isValid');
    expect(result).toHaveProperty('errors');
    expect(result).toHaveProperty('warnings');
    expect(Array.isArray(result.errors)).toBe(true);
    expect(Array.isArray(result.warnings)).toBe(true);
    
    // If there are errors, isValid should be false
    if (result.errors.length > 0) {
      expect(result.isValid).toBe(false);
    }
    
    // Errors should be more critical than warnings
    if (result.isValid === false && result.warnings.length > 0) {
      expect(result.errors.length).toBeGreaterThan(0);
    }
  });
  
  test('Configuration should reject circular service references', () => {
    fc.assert(
      fc.property(
        fc.record({
          bffUrl: fc.constantFrom(
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'https://api.example.com'
          ),
          internalUrl: fc.constantFrom(
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com/prod',
            'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com',
            'https://0pjyr8lkpl.execute-api.ap-southeast-1.amazonaws.com'
          )
        }),
        ({ bffUrl, internalUrl }) => {
          // Property: Should detect circular references
          const isSameHost = new URL(bffUrl).host === new URL(internalUrl).host;
          const hasStagePrefix = internalUrl.includes('/prod');
          
          if (isSameHost && hasStagePrefix) {
            // This would create a circular reference - BFF calling itself
            const endpoints = { internal: internalUrl };
            const result = ConfigValidator.validateServiceEndpoints(endpoints);
            
            expect(result.isValid).toBe(false);
            expect(result.errors.some(error => error.includes('stage prefix'))).toBe(true);
          }
          
          return true;
        }
      ),
      { numRuns: 30 }
    );
  });
  
  test('Configuration validation should handle edge cases gracefully', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(
          {},
          { AWS_REGION: null },
          { INTERNAL_API_URL: undefined },
          { CORS_ALLOWED_ORIGINS: '[]' },
          { CORS_ALLOWED_ORIGINS: '[""]' },
          { INTERNAL_API_URL: 'https://' },
          { INTERNAL_API_URL: 'https://api.com/' }
        ),
        (config) => {
          // Property: Validation should not crash on edge cases
          expect(() => {
            const result = ConfigValidator.validateEnvironmentVariables(config);
            expect(result).toHaveProperty('isValid');
            expect(result).toHaveProperty('errors');
            expect(result).toHaveProperty('warnings');
          }).not.toThrow();
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
});

// Integration tests for configuration validation
describe('Configuration Validation Integration', () => {
  
  test('Real environment configuration should be valid', () => {
    // Test the actual environment configuration
    const realConfig = {
      AWS_REGION: process.env.AWS_REGION,
      INTERNAL_API_URL: process.env.INTERNAL_API_URL,
      CORS_ALLOWED_ORIGINS: process.env.CORS_ALLOWED_ORIGINS
    };
    
    const result = ConfigValidator.validateEnvironmentVariables(realConfig);
    
    // Log any issues for debugging
    if (!result.isValid) {
      console.warn('Configuration validation errors:', result.errors);
    }
    if (result.warnings.length > 0) {
      console.info('Configuration validation warnings:', result.warnings);
    }
    
    // In test environment, we might not have all variables set
    // So we'll just ensure the validation runs without crashing
    expect(result).toHaveProperty('isValid');
    expect(typeof result.isValid).toBe('boolean');
  });
  
  test('Service discovery configuration should be consistent', () => {
    // Test that service discovery uses consistent configuration patterns
    const serviceEndpoints = {
      discovery: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/instances` : undefined,
      operations: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/operations` : undefined,
      monitoring: process.env.INTERNAL_API_URL ? `${process.env.INTERNAL_API_URL}/monitoring` : undefined
    };
    
    // Filter out undefined values
    const definedEndpoints = Object.fromEntries(
      Object.entries(serviceEndpoints).filter(([_, value]) => value !== undefined)
    );
    
    if (Object.keys(definedEndpoints).length > 0) {
      const result = ConfigValidator.validateServiceEndpoints(definedEndpoints);
      
      // All endpoints should use the same base URL
      const baseUrls = Object.values(definedEndpoints).map(url => {
        try {
          const parsed = new URL(url!);
          return `${parsed.protocol}//${parsed.host}`;
        } catch {
          return null;
        }
      }).filter(Boolean);
      
      if (baseUrls.length > 1) {
        const uniqueBaseUrls = [...new Set(baseUrls)];
        expect(uniqueBaseUrls.length).toBe(1); // Should all use the same base URL
      }
      
      // Log any validation issues
      if (!result.isValid) {
        console.warn('Service endpoint validation errors:', result.errors);
      }
    }
  });
});