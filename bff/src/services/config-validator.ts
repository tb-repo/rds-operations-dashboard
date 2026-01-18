/**
 * Configuration Validator for BFF
 * 
 * Validates all required environment variables and service endpoint accessibility
 * at startup to ensure proper system configuration.
 * 
 * Requirements: 6.5
 */

import axios from 'axios'
import { logger } from '../utils/logger'
import { ServiceDiscovery } from './service-discovery'

export interface ValidationResult {
  valid: boolean
  errors: string[]
  warnings: string[]
  details: {
    environmentVariables: EnvironmentValidationResult
    serviceEndpoints: ServiceEndpointValidationResult
    authentication: AuthenticationValidationResult
    cors: CorsValidationResult
  }
}

export interface EnvironmentValidationResult {
  valid: boolean
  missing: string[]
  invalid: string[]
  warnings: string[]
}

export interface ServiceEndpointValidationResult {
  valid: boolean
  accessible: string[]
  inaccessible: string[]
  errors: { service: string; error: string }[]
}

export interface AuthenticationValidationResult {
  valid: boolean
  cognitoAccessible: boolean
  secretsManagerAccessible: boolean
  apiKeyAvailable: boolean
  errors: string[]
}

export interface CorsValidationResult {
  valid: boolean
  originsConfigured: boolean
  frontendUrlValid: boolean
  errors: string[]
}

export class ConfigValidator {
  private readonly REQUIRED_ENV_VARS = [
    'COGNITO_USER_POOL_ID',
    'COGNITO_REGION'
  ]

  private readonly OPTIONAL_ENV_VARS = [
    'COGNITO_CLIENT_ID',
    'FRONTEND_URL',
    'AUDIT_LOG_GROUP',
    'API_SECRET_ARN',
    'INTERNAL_API_KEY',
    'INTERNAL_API_URL',
    'NODE_ENV',
    'PORT'
  ]

  private readonly SERVICE_ENDPOINTS = [
    'DISCOVERY_ENDPOINT',
    'OPERATIONS_ENDPOINT',
    'MONITORING_ENDPOINT',
    'COMPLIANCE_ENDPOINT',
    'COSTS_ENDPOINT',
    'APPROVALS_ENDPOINT',
    'CLOUDOPS_ENDPOINT'
  ]

  /**
   * Perform comprehensive configuration validation
   */
  public async validateConfiguration(): Promise<ValidationResult> {
    logger.info('Starting configuration validation')

    const environmentValidation = this.validateEnvironmentVariables()
    const serviceEndpointValidation = await this.validateServiceEndpoints()
    const authenticationValidation = await this.validateAuthentication()
    const corsValidation = this.validateCorsConfiguration()

    const allErrors = [
      ...environmentValidation.missing.map(v => `Missing required environment variable: ${v}`),
      ...environmentValidation.invalid.map(v => `Invalid environment variable: ${v}`),
      ...serviceEndpointValidation.errors.map(e => `Service endpoint error (${e.service}): ${e.error}`),
      ...authenticationValidation.errors,
      ...corsValidation.errors
    ]

    const allWarnings = [
      ...environmentValidation.warnings,
      ...serviceEndpointValidation.inaccessible.map(s => `Service endpoint not accessible: ${s}`)
    ]

    const result: ValidationResult = {
      valid: allErrors.length === 0,
      errors: allErrors,
      warnings: allWarnings,
      details: {
        environmentVariables: environmentValidation,
        serviceEndpoints: serviceEndpointValidation,
        authentication: authenticationValidation,
        cors: corsValidation
      }
    }

    if (result.valid) {
      logger.info('Configuration validation passed', {
        accessibleServices: serviceEndpointValidation.accessible.length,
        warnings: allWarnings.length
      })
    } else {
      logger.error('Configuration validation failed', {
        errors: allErrors.length,
        warnings: allWarnings.length,
        details: result.details
      })
    }

    return result
  }

  /**
   * Validate environment variables
   */
  private validateEnvironmentVariables(): EnvironmentValidationResult {
    const missing: string[] = []
    const invalid: string[] = []
    const warnings: string[] = []

    // Check required environment variables
    for (const envVar of this.REQUIRED_ENV_VARS) {
      const value = process.env[envVar]
      if (!value) {
        missing.push(envVar)
      } else if (value.trim() === '') {
        invalid.push(`${envVar} (empty value)`)
      }
    }

    // Check optional environment variables and provide warnings
    for (const envVar of this.OPTIONAL_ENV_VARS) {
      const value = process.env[envVar]
      if (!value) {
        switch (envVar) {
          case 'COGNITO_CLIENT_ID':
            warnings.push('COGNITO_CLIENT_ID not set - some authentication features may not work')
            break
          case 'FRONTEND_URL':
            warnings.push('FRONTEND_URL not set - using default localhost:3000')
            break
          case 'API_SECRET_ARN':
            warnings.push('API_SECRET_ARN not set - falling back to INTERNAL_API_KEY')
            break
          case 'INTERNAL_API_KEY':
            if (!process.env.API_SECRET_ARN) {
              warnings.push('Neither API_SECRET_ARN nor INTERNAL_API_KEY set - API calls may fail')
            }
            break
        }
      }
    }

    // Validate specific environment variable formats
    const cognitoRegion = process.env.COGNITO_REGION
    if (cognitoRegion && !/^[a-z]{2}-[a-z]+-\d+$/.test(cognitoRegion)) {
      invalid.push('COGNITO_REGION (invalid AWS region format)')
    }

    const frontendUrl = process.env.FRONTEND_URL
    if (frontendUrl && !this.isValidUrl(frontendUrl)) {
      invalid.push('FRONTEND_URL (invalid URL format)')
    }

    const internalApiUrl = process.env.INTERNAL_API_URL
    if (internalApiUrl) {
      if (!this.isValidUrl(internalApiUrl)) {
        invalid.push('INTERNAL_API_URL (invalid URL format)')
      } else if (internalApiUrl.includes('/prod')) {
        invalid.push('INTERNAL_API_URL (contains deprecated /prod stage)')
      }
    }

    return {
      valid: missing.length === 0 && invalid.length === 0,
      missing,
      invalid,
      warnings
    }
  }

  /**
   * Validate service endpoints accessibility
   */
  private async validateServiceEndpoints(): Promise<ServiceEndpointValidationResult> {
    const accessible: string[] = []
    const inaccessible: string[] = []
    const errors: { service: string; error: string }[] = []

    try {
      // Initialize service discovery to get endpoints
      const serviceDiscovery = new ServiceDiscovery()
      const endpoints = serviceDiscovery.getAllEndpoints()

      // Test each service endpoint
      const serviceTests = Object.entries(endpoints).map(async ([serviceName, endpoint]) => {
        try {
          const health = await serviceDiscovery.checkServiceHealth(serviceName as any)
          if (health.healthy) {
            accessible.push(serviceName)
          } else {
            inaccessible.push(serviceName)
            if (health.error) {
              errors.push({ service: serviceName, error: health.error })
            }
          }
        } catch (error: any) {
          inaccessible.push(serviceName)
          errors.push({ service: serviceName, error: error.message })
        }
      })

      await Promise.all(serviceTests)

      // Cleanup service discovery
      serviceDiscovery.destroy()

    } catch (error: any) {
      errors.push({ service: 'service-discovery', error: `Failed to initialize service discovery: ${error.message}` })
    }

    return {
      valid: errors.length === 0 && accessible.length > 0,
      accessible,
      inaccessible,
      errors
    }
  }

  /**
   * Validate authentication configuration
   */
  private async validateAuthentication(): Promise<AuthenticationValidationResult> {
    const errors: string[] = []
    let cognitoAccessible = false
    let secretsManagerAccessible = false
    let apiKeyAvailable = false

    // Test Cognito accessibility
    try {
      const cognitoRegion = process.env.COGNITO_REGION
      const userPoolId = process.env.COGNITO_USER_POOL_ID

      if (cognitoRegion && userPoolId) {
        // Try to make a simple request to Cognito (this will fail with auth error, but that's expected)
        const cognitoUrl = `https://cognito-idp.${cognitoRegion}.amazonaws.com/`
        const response = await axios.post(cognitoUrl, {}, {
          timeout: 5000,
          validateStatus: () => true // Accept any status
        })
        
        // If we get any response, Cognito is accessible
        cognitoAccessible = true
      } else {
        errors.push('Cognito configuration incomplete')
      }
    } catch (error: any) {
      if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
        errors.push('Cognito service not accessible')
      } else {
        // Other errors (like auth errors) indicate Cognito is accessible
        cognitoAccessible = true
      }
    }

    // Test Secrets Manager accessibility
    try {
      const secretArn = process.env.API_SECRET_ARN
      if (secretArn) {
        const { SecretsManagerClient, GetSecretValueCommand } = await import('@aws-sdk/client-secrets-manager')
        const client = new SecretsManagerClient({ region: process.env.COGNITO_REGION || 'ap-southeast-1' })
        
        // Try to get the secret (this might fail with permissions, but that's ok)
        try {
          await client.send(new GetSecretValueCommand({ SecretId: secretArn }))
          secretsManagerAccessible = true
          apiKeyAvailable = true
        } catch (secretError: any) {
          if (secretError.name === 'AccessDeniedException' || secretError.name === 'UnauthorizedOperation') {
            // Secrets Manager is accessible, but we don't have permissions
            secretsManagerAccessible = true
            errors.push('Secrets Manager accessible but insufficient permissions')
          } else {
            errors.push(`Secrets Manager error: ${secretError.message}`)
          }
        }
      } else {
        // Check if INTERNAL_API_KEY is available as fallback
        if (process.env.INTERNAL_API_KEY) {
          apiKeyAvailable = true
        } else {
          errors.push('No API key configuration found (neither API_SECRET_ARN nor INTERNAL_API_KEY)')
        }
      }
    } catch (error: any) {
      errors.push(`Failed to test Secrets Manager: ${error.message}`)
    }

    return {
      valid: cognitoAccessible && apiKeyAvailable,
      cognitoAccessible,
      secretsManagerAccessible,
      apiKeyAvailable,
      errors
    }
  }

  /**
   * Validate CORS configuration
   */
  private validateCorsConfiguration(): CorsValidationResult {
    const errors: string[] = []
    let originsConfigured = false
    let frontendUrlValid = false

    const frontendUrl = process.env.FRONTEND_URL
    if (frontendUrl) {
      if (this.isValidUrl(frontendUrl)) {
        frontendUrlValid = true
        originsConfigured = true
      } else {
        errors.push('FRONTEND_URL is not a valid URL')
      }
    } else {
      // Check if we have default origins configured
      const defaultOrigins = [
        'https://d2qvaswtmn22om.cloudfront.net',
        'http://localhost:3000'
      ]
      originsConfigured = true // We have defaults
    }

    // Check for common CORS misconfigurations
    if (frontendUrl && frontendUrl.includes('/prod')) {
      errors.push('FRONTEND_URL should not contain /prod path')
    }

    return {
      valid: errors.length === 0 && originsConfigured,
      originsConfigured,
      frontendUrlValid,
      errors
    }
  }

  /**
   * Validate URL format
   */
  private isValidUrl(url: string): boolean {
    try {
      new URL(url)
      return true
    } catch {
      return false
    }
  }

  /**
   * Generate configuration report
   */
  public generateConfigurationReport(validation: ValidationResult): string {
    const lines: string[] = []
    
    lines.push('='.repeat(60))
    lines.push('BFF CONFIGURATION VALIDATION REPORT')
    lines.push('='.repeat(60))
    lines.push('')
    
    lines.push(`Overall Status: ${validation.valid ? '✅ VALID' : '❌ INVALID'}`)
    lines.push(`Errors: ${validation.errors.length}`)
    lines.push(`Warnings: ${validation.warnings.length}`)
    lines.push('')

    // Environment Variables
    lines.push('Environment Variables:')
    lines.push(`  Status: ${validation.details.environmentVariables.valid ? '✅' : '❌'}`)
    if (validation.details.environmentVariables.missing.length > 0) {
      lines.push(`  Missing: ${validation.details.environmentVariables.missing.join(', ')}`)
    }
    if (validation.details.environmentVariables.invalid.length > 0) {
      lines.push(`  Invalid: ${validation.details.environmentVariables.invalid.join(', ')}`)
    }
    lines.push('')

    // Service Endpoints
    lines.push('Service Endpoints:')
    lines.push(`  Status: ${validation.details.serviceEndpoints.valid ? '✅' : '❌'}`)
    lines.push(`  Accessible: ${validation.details.serviceEndpoints.accessible.length}`)
    lines.push(`  Inaccessible: ${validation.details.serviceEndpoints.inaccessible.length}`)
    if (validation.details.serviceEndpoints.accessible.length > 0) {
      lines.push(`    ✅ ${validation.details.serviceEndpoints.accessible.join(', ')}`)
    }
    if (validation.details.serviceEndpoints.inaccessible.length > 0) {
      lines.push(`    ❌ ${validation.details.serviceEndpoints.inaccessible.join(', ')}`)
    }
    lines.push('')

    // Authentication
    lines.push('Authentication:')
    lines.push(`  Status: ${validation.details.authentication.valid ? '✅' : '❌'}`)
    lines.push(`  Cognito: ${validation.details.authentication.cognitoAccessible ? '✅' : '❌'}`)
    lines.push(`  Secrets Manager: ${validation.details.authentication.secretsManagerAccessible ? '✅' : '❌'}`)
    lines.push(`  API Key: ${validation.details.authentication.apiKeyAvailable ? '✅' : '❌'}`)
    lines.push('')

    // CORS
    lines.push('CORS Configuration:')
    lines.push(`  Status: ${validation.details.cors.valid ? '✅' : '❌'}`)
    lines.push(`  Origins Configured: ${validation.details.cors.originsConfigured ? '✅' : '❌'}`)
    lines.push(`  Frontend URL Valid: ${validation.details.cors.frontendUrlValid ? '✅' : '❌'}`)
    lines.push('')

    // Errors
    if (validation.errors.length > 0) {
      lines.push('ERRORS:')
      validation.errors.forEach(error => {
        lines.push(`  ❌ ${error}`)
      })
      lines.push('')
    }

    // Warnings
    if (validation.warnings.length > 0) {
      lines.push('WARNINGS:')
      validation.warnings.forEach(warning => {
        lines.push(`  ⚠️  ${warning}`)
      })
      lines.push('')
    }

    lines.push('='.repeat(60))
    
    return lines.join('\n')
  }
}

/**
 * Perform startup configuration validation
 */
export async function validateStartupConfiguration(): Promise<ValidationResult> {
  const validator = new ConfigValidator()
  return await validator.validateConfiguration()
}

/**
 * Validate configuration and exit if invalid
 */
export async function validateConfigurationOrExit(): Promise<ValidationResult> {
  const validator = new ConfigValidator()
  const result = await validator.validateConfiguration()
  
  // Always log the configuration report
  const report = validator.generateConfigurationReport(result)
  console.log(report)
  
  if (!result.valid) {
    logger.error('Configuration validation failed - exiting')
    process.exit(1)
  }
  
  if (result.warnings.length > 0) {
    logger.warn('Configuration validation passed with warnings', {
      warnings: result.warnings.length
    })
  }
  
  return result
}