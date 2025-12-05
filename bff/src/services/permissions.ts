import { logger } from '../utils/logger'

/**
 * Permission types in the system
 */
export type Permission =
  | 'view_instances'
  | 'view_metrics'
  | 'view_compliance'
  | 'view_costs'
  | 'execute_operations'
  | 'generate_cloudops'
  | 'trigger_discovery'
  | 'manage_users'

/**
 * User roles in the system
 */
export type Role = 'Admin' | 'DBA' | 'ReadOnly'

/**
 * Role-to-Permission mapping
 */
const ROLE_PERMISSIONS: Record<Role, Permission[]> = {
  Admin: [
    'view_instances',
    'view_metrics',
    'view_compliance',
    'view_costs',
    'execute_operations',
    'generate_cloudops',
    'trigger_discovery',
    'manage_users',
  ],
  DBA: [
    'view_instances',
    'view_metrics',
    'view_compliance',
    'view_costs',
    'execute_operations',
    'generate_cloudops',
    'trigger_discovery',
  ],
  ReadOnly: [
    'view_instances',
    'view_metrics',
    'view_compliance',
    'view_costs',
  ],
}

/**
 * Endpoint-to-Permission mapping
 */
export const ENDPOINT_PERMISSIONS: Record<string, Permission> = {
  // Instance endpoints
  'GET /api/instances': 'view_instances',
  'GET /api/instances/:id': 'view_instances',
  
  // Metrics endpoints
  'GET /api/metrics': 'view_metrics',
  'GET /api/metrics/:instanceId': 'view_metrics',
  
  // Compliance endpoints
  'GET /api/compliance': 'view_compliance',
  'GET /api/compliance/:instanceId': 'view_compliance',
  
  // Cost endpoints
  'GET /api/costs': 'view_costs',
  'GET /api/costs/trends': 'view_costs',
  'GET /api/costs/:instanceId': 'view_costs',
  
  // Operations endpoints
  'POST /api/operations': 'execute_operations',
  'POST /api/operations/execute': 'execute_operations',
  
  // CloudOps endpoints
  'POST /api/cloudops': 'generate_cloudops',
  'GET /api/cloudops/history': 'generate_cloudops',
  
  // Discovery endpoints
  'POST /api/discovery/trigger': 'trigger_discovery',
  
  // User management endpoints
  'GET /api/users': 'manage_users',
  'POST /api/users/:userId/groups': 'manage_users',
  'DELETE /api/users/:userId/groups/:groupName': 'manage_users',
}

export class PermissionService {
  /**
   * Get all permissions for given roles/groups
   */
  getPermissionsForGroups(groups: string[]): Permission[] {
    const permissions = new Set<Permission>()

    for (const group of groups) {
      if (this.isValidRole(group)) {
        const rolePermissions = ROLE_PERMISSIONS[group as Role]
        rolePermissions.forEach(p => permissions.add(p))
      } else {
        logger.warn('Unknown role/group', { group })
      }
    }

    return Array.from(permissions)
  }

  /**
   * Check if user has a specific permission
   */
  hasPermission(userPermissions: Permission[], requiredPermission: Permission): boolean {
    return userPermissions.includes(requiredPermission)
  }

  /**
   * Check if user has any of the specified permissions
   */
  hasAnyPermission(userPermissions: Permission[], requiredPermissions: Permission[]): boolean {
    return requiredPermissions.some(p => userPermissions.includes(p))
  }

  /**
   * Check if user has all of the specified permissions
   */
  hasAllPermissions(userPermissions: Permission[], requiredPermissions: Permission[]): boolean {
    return requiredPermissions.every(p => userPermissions.includes(p))
  }

  /**
   * Get required permission for an endpoint
   */
  getRequiredPermission(method: string, path: string): Permission | null {
    // Normalize path by removing query parameters
    const normalizedPath = path.split('?')[0]
    
    // Try exact match first
    const exactKey = `${method} ${normalizedPath}`
    if (ENDPOINT_PERMISSIONS[exactKey]) {
      return ENDPOINT_PERMISSIONS[exactKey]
    }

    // Try pattern matching for parameterized routes
    for (const [pattern, permission] of Object.entries(ENDPOINT_PERMISSIONS)) {
      if (this.matchesPattern(method, normalizedPath, pattern)) {
        return permission
      }
    }

    return null
  }

  /**
   * Match request against endpoint pattern
   */
  private matchesPattern(method: string, path: string, pattern: string): boolean {
    const [patternMethod, patternPath] = pattern.split(' ')
    
    if (method !== patternMethod) {
      return false
    }

    // Convert pattern to regex
    // Replace :param with regex to match any value
    const regexPattern = patternPath
      .replace(/:[^/]+/g, '[^/]+')
      .replace(/\//g, '\\/')
    
    const regex = new RegExp(`^${regexPattern}$`)
    return regex.test(path)
  }

  /**
   * Check if a string is a valid role
   */
  private isValidRole(role: string): role is Role {
    return role === 'Admin' || role === 'DBA' || role === 'ReadOnly'
  }

  /**
   * Get all permissions for a specific role
   */
  getRolePermissions(role: Role): Permission[] {
    return ROLE_PERMISSIONS[role] || []
  }

  /**
   * Get all available permissions
   */
  getAllPermissions(): Permission[] {
    return [
      'view_instances',
      'view_metrics',
      'view_compliance',
      'view_costs',
      'execute_operations',
      'generate_cloudops',
      'trigger_discovery',
      'manage_users',
    ]
  }

  /**
   * Get all available roles
   */
  getAllRoles(): Role[] {
    return ['Admin', 'DBA', 'ReadOnly']
  }

  /**
   * Get role description
   */
  getRoleDescription(role: Role): string {
    const descriptions: Record<Role, string> = {
      Admin: 'Full system access including user management',
      DBA: 'Database operations and CloudOps generation',
      ReadOnly: 'View-only access to all dashboards',
    }
    return descriptions[role]
  }

  /**
   * Get permission description
   */
  getPermissionDescription(permission: Permission): string {
    const descriptions: Record<Permission, string> = {
      view_instances: 'View RDS instances and their details',
      view_metrics: 'View performance metrics and health data',
      view_compliance: 'View compliance status and reports',
      view_costs: 'View cost analysis and trends',
      execute_operations: 'Execute operations on non-production instances',
      generate_cloudops: 'Generate CloudOps change requests for production',
      trigger_discovery: 'Trigger manual discovery scans',
      manage_users: 'Manage users and assign roles',
    }
    return descriptions[permission]
  }
}

// Export singleton instance
export const permissionService = new PermissionService()
