/**
 * Service Discovery for BFF
 * 
 * Implements proper service discovery logic to eliminate circular dependencies
 * and ensure BFF calls the correct backend services.
 * 
 * Requirements: 2.1, 2.2, 5.2
 */

import axios from 'axios'
import { logger } from '../utils/logger'

export interface ServiceEndpoints {
  discovery: string
  operations: string
  monitoring: string
  compliance: string
  costs: string
  approvals: string
  cloudops: string
}

export interface ServiceHealth {
  service: string
  endpoint: string
  healthy: boolean
  responseTime?: number
  lastChecked: Date
  error?: string
}

export class ServiceDiscovery {
  private endpoints: ServiceEndpoints
  private healthCache: Map<string, ServiceHealth> = new Map()
  private healthCheckInterval: NodeJS.Timeout | null = null
  private readonly HEALTH_CHECK_INTERVAL = 60000 // 1 minute
  private readonly HEALTH_CHECK_TIMEOUT = 5000 // 5 seconds
  
  constructor() {
    this.endpoints = this.loadServiceEndpoints()
    this.validateConfiguration()
    this.startHealthChecking()
    
    logger.info('Service Discovery initialized', {
      endpoints: this.endpoints,
      healthCheckInterval: this.HEALTH_CHECK_INTERVAL
    })
  }
  
  /**
   * Load service endpoints from environment variables
   */
  private loadServiceEndpoints(): ServiceEndpoints {
    const baseUrl = process.env.INTERNAL_API_URL?.replace(/\/$/, '') || ''
    
    // Check for circular reference
    const bffUrl = process.env.BFF_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
    if (baseUrl === bffUrl || baseUrl.includes('/prod')) {
      logger.error('Circular reference detected in service discovery', {
        internalApiUrl: baseUrl,
        bffApiUrl: bffUrl
      })
      throw new Error('Circular reference: INTERNAL_API_URL cannot be the same as BFF URL or contain /prod')
    }
    
    return {
      discovery: process.env.DISCOVERY_ENDPOINT || `${baseUrl}/instances`,
      operations: process.env.OPERATIONS_ENDPOINT || `${baseUrl}/operations`,
      monitoring: process.env.MONITORING_ENDPOINT || `${baseUrl}/monitoring`,
      compliance: process.env.COMPLIANCE_ENDPOINT || `${baseUrl}/compliance`,
      costs: process.env.COSTS_ENDPOINT || `${baseUrl}/costs`,
      approvals: process.env.APPROVALS_ENDPOINT || `${baseUrl}/approvals`,
      cloudops: process.env.CLOUDOPS_ENDPOINT || `${baseUrl}/cloudops`
    }
  }
  
  /**
   * Validate service discovery configuration
   */
  private validateConfiguration(): void {
    const issues: string[] = []
    
    // Check for empty endpoints
    Object.entries(this.endpoints).forEach(([service, endpoint]) => {
      if (!endpoint || endpoint === '/') {
        issues.push(`${service} endpoint is empty or invalid`)
      }
      
      // Check for stage prefixes
      if (endpoint.includes('/prod/') || endpoint.includes('/staging/') || endpoint.includes('/dev/')) {
        issues.push(`${service} endpoint contains stage prefix: ${endpoint}`)
      }
      
      // Check for circular references
      const bffUrl = process.env.BFF_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
      if (endpoint.startsWith(bffUrl)) {
        issues.push(`${service} endpoint creates circular reference: ${endpoint}`)
      }
    })
    
    if (issues.length > 0) {
      logger.error('Service Discovery configuration issues', { issues })
      throw new Error(`Service Discovery configuration errors: ${issues.join(', ')}`)
    }
    
    logger.info('Service Discovery configuration validated successfully')
  }
  
  /**
   * Get endpoint for a specific service
   */
  public getEndpoint(service: keyof ServiceEndpoints): string {
    const endpoint = this.endpoints[service]
    if (!endpoint) {
      throw new Error(`Unknown service: ${service}`)
    }
    
    logger.debug('Service endpoint resolved', { service, endpoint })
    return endpoint
  }
  
  /**
   * Get all service endpoints
   */
  public getAllEndpoints(): ServiceEndpoints {
    return { ...this.endpoints }
  }
  
  /**
   * Check health of a specific service
   */
  public async checkServiceHealth(service: keyof ServiceEndpoints): Promise<ServiceHealth> {
    const endpoint = this.getEndpoint(service)
    const startTime = Date.now()
    
    try {
      const healthUrl = this.getHealthCheckUrl(service, endpoint)
      const apiKey = process.env.INTERNAL_API_KEY || ''
      
      const response = await axios.get(healthUrl, {
        timeout: this.HEALTH_CHECK_TIMEOUT,
        headers: {
          'x-api-key': apiKey,
          'User-Agent': 'RDS-Dashboard-BFF-HealthCheck/1.0'
        },
        validateStatus: (status) => status < 500 // Accept 4xx as "healthy" (auth required)
      })
      
      const responseTime = Date.now() - startTime
      const health: ServiceHealth = {
        service,
        endpoint,
        healthy: true,
        responseTime,
        lastChecked: new Date()
      }
      
      this.healthCache.set(service, health)
      logger.debug('Service health check passed', { service, endpoint, responseTime })
      
      return health
      
    } catch (error: any) {
      const responseTime = Date.now() - startTime
      const health: ServiceHealth = {
        service,
        endpoint,
        healthy: false,
        responseTime,
        lastChecked: new Date(),
        error: error.message
      }
      
      this.healthCache.set(service, health)
      logger.warn('Service health check failed', { service, endpoint, error: error.message })
      
      return health
    }
  }
  
  /**
   * Get health check URL for a service
   */
  private getHealthCheckUrl(service: keyof ServiceEndpoints, endpoint: string): string {
    // For most services, we can try a simple GET request
    // Some services might have dedicated health endpoints
    switch (service) {
      case 'discovery':
        return endpoint // /instances endpoint serves as health check
      case 'operations':
        return endpoint // /operations endpoint serves as health check
      default:
        return endpoint
    }
  }
  
  /**
   * Get health status for all services
   */
  public async checkAllServicesHealth(): Promise<ServiceHealth[]> {
    const services = Object.keys(this.endpoints) as (keyof ServiceEndpoints)[]
    const healthChecks = services.map(service => this.checkServiceHealth(service))
    
    return Promise.all(healthChecks)
  }
  
  /**
   * Get cached health status
   */
  public getCachedHealth(service: keyof ServiceEndpoints): ServiceHealth | null {
    return this.healthCache.get(service) || null
  }
  
  /**
   * Get all cached health statuses
   */
  public getAllCachedHealth(): ServiceHealth[] {
    return Array.from(this.healthCache.values())
  }
  
  /**
   * Start periodic health checking
   */
  private startHealthChecking(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval)
    }
    
    // Initial health check
    this.checkAllServicesHealth().catch(error => {
      logger.error('Initial health check failed', { error: error.message })
    })
    
    // Periodic health checks
    this.healthCheckInterval = setInterval(async () => {
      try {
        await this.checkAllServicesHealth()
        logger.debug('Periodic health check completed')
      } catch (error: any) {
        logger.error('Periodic health check failed', { error: error.message })
      }
    }, this.HEALTH_CHECK_INTERVAL)
    
    logger.info('Health checking started', { interval: this.HEALTH_CHECK_INTERVAL })
  }
  
  /**
   * Stop health checking
   */
  public stopHealthChecking(): void {
    if (this.healthCheckInterval) {
      clearInterval(this.healthCheckInterval)
      this.healthCheckInterval = null
      logger.info('Health checking stopped')
    }
  }
  
  /**
   * Get service discovery statistics
   */
  public getStatistics(): {
    totalServices: number
    healthyServices: number
    unhealthyServices: number
    averageResponseTime: number
    lastHealthCheck: Date | null
  } {
    const allHealth = this.getAllCachedHealth()
    const healthyServices = allHealth.filter(h => h.healthy).length
    const unhealthyServices = allHealth.filter(h => !h.healthy).length
    
    const responseTimes = allHealth
      .filter(h => h.responseTime !== undefined)
      .map(h => h.responseTime!)
    
    const averageResponseTime = responseTimes.length > 0
      ? responseTimes.reduce((sum, time) => sum + time, 0) / responseTimes.length
      : 0
    
    const lastHealthCheck = allHealth.length > 0
      ? new Date(Math.max(...allHealth.map(h => h.lastChecked.getTime())))
      : null
    
    return {
      totalServices: Object.keys(this.endpoints).length,
      healthyServices,
      unhealthyServices,
      averageResponseTime,
      lastHealthCheck
    }
  }
  
  /**
   * Create HTTP client with proper headers for internal API calls
   */
  public createInternalApiClient(apiKey: string) {
    return axios.create({
      timeout: 30000,
      headers: {
        'x-api-key': apiKey,
        'User-Agent': 'RDS-Dashboard-BFF/1.0',
        'x-bff-request': 'true',
        'Content-Type': 'application/json'
      }
    })
  }
  
  /**
   * Make a request to a backend service with proper error handling
   */
  public async callService<T = any>(
    service: keyof ServiceEndpoints,
    path: string = '',
    options: {
      method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
      data?: any
      params?: any
      apiKey: string
    }
  ): Promise<T> {
    const endpoint = this.getEndpoint(service)
    const url = `${endpoint}${path}`
    const client = this.createInternalApiClient(options.apiKey)
    
    logger.info('Calling backend service', {
      service,
      url,
      method: options.method || 'GET'
    })
    
    try {
      const response = await client.request({
        method: options.method || 'GET',
        url,
        data: options.data,
        params: options.params
      })
      
      logger.info('Backend service call successful', {
        service,
        url,
        status: response.status
      })
      
      return response.data
      
    } catch (error: any) {
      logger.error('Backend service call failed', {
        service,
        url,
        error: error.message,
        status: error.response?.status,
        statusText: error.response?.statusText
      })
      
      // Update health cache to reflect the failure
      const health: ServiceHealth = {
        service,
        endpoint,
        healthy: false,
        lastChecked: new Date(),
        error: error.message
      }
      this.healthCache.set(service, health)
      
      throw error
    }
  }
  
  /**
   * Cleanup resources
   */
  public destroy(): void {
    this.stopHealthChecking()
    this.healthCache.clear()
    logger.info('Service Discovery destroyed')
  }
}

// Singleton instance
let serviceDiscoveryInstance: ServiceDiscovery | null = null

/**
 * Get the singleton ServiceDiscovery instance
 */
export function getServiceDiscovery(): ServiceDiscovery {
  if (!serviceDiscoveryInstance) {
    serviceDiscoveryInstance = new ServiceDiscovery()
  }
  return serviceDiscoveryInstance
}

/**
 * Initialize service discovery (for testing or explicit initialization)
 */
export function initializeServiceDiscovery(): ServiceDiscovery {
  if (serviceDiscoveryInstance) {
    serviceDiscoveryInstance.destroy()
  }
  serviceDiscoveryInstance = new ServiceDiscovery()
  return serviceDiscoveryInstance
}

/**
 * Cleanup service discovery
 */
export function destroyServiceDiscovery(): void {
  if (serviceDiscoveryInstance) {
    serviceDiscoveryInstance.destroy()
    serviceDiscoveryInstance = null
  }
}