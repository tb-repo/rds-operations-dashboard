/**
 * Enhanced Origin Validation and Security Module
 * 
 * Provides comprehensive origin validation with security logging and threat detection.
 * Implements strict allowlist-based validation with detailed audit trails.
 */

import { logger } from '../utils/logger'

export interface SecurityEvent {
  type: 'ORIGIN_BLOCKED' | 'INVALID_ORIGIN_FORMAT' | 'SUSPICIOUS_ORIGIN' | 'ORIGIN_ALLOWED'
  origin: string
  reason: string
  timestamp: Date
  clientIp?: string
  userAgent?: string
  path?: string
  method?: string
}

export interface OriginValidationResult {
  allowed: boolean
  reason: string
  securityEvent?: SecurityEvent
}

export class OriginValidator {
  private allowedOrigins: string[]
  private securityEvents: SecurityEvent[] = []
  private suspiciousPatterns: RegExp[] = [
    /localhost:\d{4,5}$/, // High port localhost (potential tunneling)
    /\d+\.\d+\.\d+\.\d+/, // Direct IP addresses (suspicious for web apps)
    /[<>'"]/,             // Script injection attempts
    /javascript:/,        // JavaScript protocol
    /data:/,              // Data URLs
    /file:/,              // File protocol
    /ftp:/,               // FTP protocol
  ]

  constructor(allowedOrigins: string[]) {
    this.allowedOrigins = allowedOrigins
    logger.info('Origin validator initialized', { 
      allowedOrigins: this.allowedOrigins.length,
      patterns: this.suspiciousPatterns.length
    })
  }

  /**
   * Validates an origin against the allowlist with comprehensive security checks
   */
  validateOrigin(
    origin: string | undefined, 
    clientIp?: string, 
    userAgent?: string,
    path?: string,
    method?: string
  ): OriginValidationResult {
    // Allow requests with no origin (server-to-server, mobile apps)
    if (!origin) {
      return {
        allowed: true,
        reason: 'No origin header (server-to-server or mobile app)'
      }
    }

    // Check for basic format validity
    if (!this.isValidOriginFormat(origin)) {
      const securityEvent: SecurityEvent = {
        type: 'INVALID_ORIGIN_FORMAT',
        origin,
        reason: 'Invalid URL format or unsupported protocol',
        timestamp: new Date(),
        clientIp,
        userAgent,
        path,
        method
      }
      
      this.logSecurityEvent(securityEvent)
      
      return {
        allowed: false,
        reason: 'Invalid origin format',
        securityEvent
      }
    }

    // Check for suspicious patterns
    const suspiciousPattern = this.detectSuspiciousPattern(origin)
    if (suspiciousPattern) {
      const securityEvent: SecurityEvent = {
        type: 'SUSPICIOUS_ORIGIN',
        origin,
        reason: `Matches suspicious pattern: ${suspiciousPattern}`,
        timestamp: new Date(),
        clientIp,
        userAgent,
        path,
        method
      }
      
      this.logSecurityEvent(securityEvent)
      
      // Still check allowlist, but log as suspicious
      if (!this.allowedOrigins.includes(origin)) {
        return {
          allowed: false,
          reason: 'Suspicious origin not in allowlist',
          securityEvent
        }
      }
    }

    // Check against allowlist
    if (this.allowedOrigins.includes(origin)) {
      const securityEvent: SecurityEvent = {
        type: 'ORIGIN_ALLOWED',
        origin,
        reason: 'Origin in allowlist',
        timestamp: new Date(),
        clientIp,
        userAgent,
        path,
        method
      }
      
      // Only log allowed origins at debug level to reduce noise
      logger.debug('Origin allowed', { origin, clientIp, path })
      
      return {
        allowed: true,
        reason: 'Origin in allowlist',
        securityEvent
      }
    }

    // Origin not in allowlist - security event
    const securityEvent: SecurityEvent = {
      type: 'ORIGIN_BLOCKED',
      origin,
      reason: 'Origin not in allowlist',
      timestamp: new Date(),
      clientIp,
      userAgent,
      path,
      method
    }
    
    this.logSecurityEvent(securityEvent)
    
    return {
      allowed: false,
      reason: 'Origin not allowed',
      securityEvent
    }
  }

  /**
   * Validates origin URL format and protocol
   */
  private isValidOriginFormat(origin: string): boolean {
    try {
      const url = new URL(origin)
      // Only allow HTTP/HTTPS protocols
      return ['http:', 'https:'].includes(url.protocol)
    } catch {
      return false
    }
  }

  /**
   * Detects suspicious patterns in origin
   */
  private detectSuspiciousPattern(origin: string): string | null {
    for (const pattern of this.suspiciousPatterns) {
      if (pattern.test(origin)) {
        return pattern.toString()
      }
    }
    return null
  }

  /**
   * Logs security events with appropriate severity
   */
  private logSecurityEvent(event: SecurityEvent): void {
    this.securityEvents.push(event)
    
    // Keep only last 1000 events to prevent memory issues
    if (this.securityEvents.length > 1000) {
      this.securityEvents = this.securityEvents.slice(-1000)
    }

    switch (event.type) {
      case 'ORIGIN_BLOCKED':
        logger.warn('SECURITY: Origin blocked', {
          origin: event.origin,
          reason: event.reason,
          clientIp: event.clientIp,
          userAgent: event.userAgent,
          path: event.path,
          method: event.method,
          timestamp: event.timestamp
        })
        break
        
      case 'INVALID_ORIGIN_FORMAT':
        logger.error('SECURITY: Invalid origin format detected', {
          origin: event.origin,
          reason: event.reason,
          clientIp: event.clientIp,
          userAgent: event.userAgent,
          timestamp: event.timestamp
        })
        break
        
      case 'SUSPICIOUS_ORIGIN':
        logger.warn('SECURITY: Suspicious origin pattern detected', {
          origin: event.origin,
          reason: event.reason,
          clientIp: event.clientIp,
          userAgent: event.userAgent,
          timestamp: event.timestamp
        })
        break
        
      case 'ORIGIN_ALLOWED':
        // Only log at debug level to reduce noise
        logger.debug('Origin validation passed', {
          origin: event.origin,
          timestamp: event.timestamp
        })
        break
    }
  }

  /**
   * Gets recent security events for monitoring
   */
  getRecentSecurityEvents(limit: number = 100): SecurityEvent[] {
    return this.securityEvents.slice(-limit)
  }

  /**
   * Gets security statistics
   */
  getSecurityStats(): {
    totalEvents: number
    blockedOrigins: number
    suspiciousOrigins: number
    invalidFormats: number
    allowedOrigins: number
  } {
    const stats = {
      totalEvents: this.securityEvents.length,
      blockedOrigins: 0,
      suspiciousOrigins: 0,
      invalidFormats: 0,
      allowedOrigins: 0
    }

    this.securityEvents.forEach(event => {
      switch (event.type) {
        case 'ORIGIN_BLOCKED':
          stats.blockedOrigins++
          break
        case 'SUSPICIOUS_ORIGIN':
          stats.suspiciousOrigins++
          break
        case 'INVALID_ORIGIN_FORMAT':
          stats.invalidFormats++
          break
        case 'ORIGIN_ALLOWED':
          stats.allowedOrigins++
          break
      }
    })

    return stats
  }

  /**
   * Updates the allowed origins list
   */
  updateAllowedOrigins(newOrigins: string[]): void {
    this.allowedOrigins = newOrigins
    logger.info('Allowed origins updated', { 
      count: newOrigins.length,
      origins: newOrigins
    })
  }
}