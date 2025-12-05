import { logger } from '../utils/logger'

/**
 * Audit event types
 */
export type AuditEventType =
  | 'AUTH_LOGIN_SUCCESS'
  | 'AUTH_LOGIN_FAILURE'
  | 'AUTH_LOGOUT'
  | 'AUTH_TOKEN_REFRESH'
  | 'AUTHZ_DENIED'
  | 'AUTHZ_GRANTED'
  | 'OPERATION_EXECUTED'
  | 'CLOUDOPS_GENERATED'
  | 'USER_ROLE_CHANGED'
  | 'DISCOVERY_TRIGGERED'

/**
 * Audit log entry structure
 */
export interface AuditLogEntry {
  timestamp: string
  eventType: AuditEventType
  userId: string
  userEmail: string
  ipAddress: string
  userAgent: string
  resource?: string
  action?: string
  result: 'success' | 'failure'
  statusCode?: number
  errorMessage?: string
  requestId?: string
  metadata?: Record<string, any>
}

/**
 * Audit logging service
 */
export class AuditService {
  private enabled: boolean

  constructor(enabled: boolean = true) {
    this.enabled = enabled
    logger.info('Audit service initialized', { enabled: this.enabled })
  }

  /**
   * Log authentication event
   */
  logAuthenticationEvent(
    eventType: 'AUTH_LOGIN_SUCCESS' | 'AUTH_LOGIN_FAILURE' | 'AUTH_LOGOUT' | 'AUTH_TOKEN_REFRESH',
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    result: 'success' | 'failure',
    metadata?: Record<string, any>
  ): void {
    const entry: AuditLogEntry = {
      timestamp: new Date().toISOString(),
      eventType,
      userId,
      userEmail,
      ipAddress,
      userAgent,
      result,
      metadata,
    }

    this.writeAuditLog(entry)
  }

  /**
   * Log authorization event
   */
  logAuthorizationEvent(
    eventType: 'AUTHZ_GRANTED' | 'AUTHZ_DENIED',
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    resource: string,
    action: string,
    result: 'success' | 'failure',
    requestId?: string,
    metadata?: Record<string, any>
  ): void {
    const entry: AuditLogEntry = {
      timestamp: new Date().toISOString(),
      eventType,
      userId,
      userEmail,
      ipAddress,
      userAgent,
      resource,
      action,
      result,
      requestId,
      metadata,
    }

    this.writeAuditLog(entry)
  }

  /**
   * Log operation event
   */
  logOperationEvent(
    eventType: 'OPERATION_EXECUTED' | 'CLOUDOPS_GENERATED' | 'DISCOVERY_TRIGGERED',
    userId: string,
    userEmail: string,
    ipAddress: string,
    userAgent: string,
    resource: string,
    action: string,
    result: 'success' | 'failure',
    requestId?: string,
    metadata?: Record<string, any>
  ): void {
    const entry: AuditLogEntry = {
      timestamp: new Date().toISOString(),
      eventType,
      userId,
      userEmail,
      ipAddress,
      userAgent,
      resource,
      action,
      result,
      requestId,
      metadata,
    }

    this.writeAuditLog(entry)
  }

  /**
   * Log user role change event
   */
  logUserRoleChange(
    adminUserId: string,
    adminEmail: string,
    targetUserId: string,
    targetEmail: string,
    action: 'add_role' | 'remove_role',
    role: string,
    ipAddress: string,
    userAgent: string,
    result: 'success' | 'failure',
    requestId?: string,
    metadata?: Record<string, any>
  ): void {
    const entry: AuditLogEntry = {
      timestamp: new Date().toISOString(),
      eventType: 'USER_ROLE_CHANGED',
      userId: adminUserId,
      userEmail: adminEmail,
      ipAddress,
      userAgent,
      resource: `user:${targetUserId}`,
      action,
      result,
      requestId,
      metadata: {
        ...metadata,
        targetUserId,
        targetEmail,
        role,
      },
    }

    this.writeAuditLog(entry)
  }

  /**
   * Write audit log entry to CloudWatch Logs
   */
  private writeAuditLog(entry: AuditLogEntry): void {
    if (!this.enabled) {
      return
    }

    // Log to structured logger which will send to CloudWatch
    logger.info('AUDIT_LOG', entry)

    // Additional CloudWatch Logs integration can be added here
    // For now, we rely on the Winston logger configuration
    // to send logs to CloudWatch Logs
  }

  /**
   * Enable audit logging
   */
  enable(): void {
    this.enabled = true
    logger.info('Audit logging enabled')
  }

  /**
   * Disable audit logging
   */
  disable(): void {
    this.enabled = false
    logger.warn('Audit logging disabled')
  }

  /**
   * Check if audit logging is enabled
   */
  isEnabled(): boolean {
    return this.enabled
  }
}

// Export singleton instance
export const auditService = new AuditService(
  process.env.ENABLE_AUDIT_LOGGING !== 'false'
)
