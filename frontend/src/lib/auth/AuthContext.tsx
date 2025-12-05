import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { CognitoService, Session } from './cognito'

export type Permission =
  | 'view_instances'
  | 'view_metrics'
  | 'view_compliance'
  | 'view_costs'
  | 'execute_operations'
  | 'generate_cloudops'
  | 'trigger_discovery'
  | 'manage_users'

export interface User {
  id: string
  email: string
  name?: string
  groups: string[]
  permissions: Permission[]
  attributes: Record<string, string>
}

export interface AuthContextType {
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  permissions: Permission[]
  login: () => Promise<void>
  logout: () => void
  refreshAuth: () => void
  hasPermission: (permission: Permission) => boolean
  hasAnyPermission: (permissions: Permission[]) => boolean
  hasAllPermissions: (permissions: Permission[]) => boolean
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

interface AuthProviderProps {
  children: ReactNode
  cognitoService: CognitoService
}

// Role-to-Permission mapping (matches backend)
const ROLE_PERMISSIONS: Record<string, Permission[]> = {
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

export function AuthProvider({ children, cognitoService }: AuthProviderProps) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    // Check for existing session on mount
    const session = cognitoService.getCurrentSession()
    if (session) {
      loadUserFromSession(session)
    } else {
      setIsLoading(false)
    }
  }, [])

  const loadUserFromSession = (session: Session) => {
    try {
      const payload = cognitoService.parseToken(session.idToken)
      
      const groups = payload['cognito:groups'] || []
      const permissions = getPermissionsForGroups(groups)

      console.log('User token payload:', {
        email: payload.email,
        groups: groups,
        permissions: permissions,
        allClaims: payload
      })

      const userData: User = {
        id: payload.sub,
        email: payload.email,
        name: payload.name,
        groups,
        permissions,
        attributes: {
          email_verified: payload.email_verified,
          ...payload,
        },
      }

      setUser(userData)
      console.log('User loaded:', userData)
    } catch (error) {
      console.error('Error loading user from session:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const getPermissionsForGroups = (groups: string[]): Permission[] => {
    const permissions = new Set<Permission>()

    for (const group of groups) {
      const groupPermissions = ROLE_PERMISSIONS[group] || []
      groupPermissions.forEach(p => permissions.add(p))
    }

    return Array.from(permissions)
  }

  const login = async () => {
    await cognitoService.login()
  }

  const logout = () => {
    setUser(null)
    cognitoService.logout()
  }

  const refreshAuth = () => {
    console.log('Refreshing auth state...')
    const session = cognitoService.getCurrentSession()
    if (session) {
      console.log('Session found, loading user data')
      loadUserFromSession(session)
    } else {
      console.log('No session found')
      setUser(null)
      setIsLoading(false)
    }
  }

  const hasPermission = (permission: Permission): boolean => {
    if (!user) return false
    return user.permissions.includes(permission)
  }

  const hasAnyPermission = (permissions: Permission[]): boolean => {
    if (!user) return false
    return permissions.some(p => user.permissions.includes(p))
  }

  const hasAllPermissions = (permissions: Permission[]): boolean => {
    if (!user) return false
    return permissions.every(p => user.permissions.includes(p))
  }

  const value: AuthContextType = {
    user,
    isAuthenticated: !!user,
    isLoading,
    permissions: user?.permissions || [],
    login,
    logout,
    refreshAuth,
    hasPermission,
    hasAnyPermission,
    hasAllPermissions,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextType {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
