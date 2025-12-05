import { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth, Permission } from '../lib/auth/AuthContext'
import LoadingSpinner from './LoadingSpinner'

interface ProtectedRouteProps {
  children: ReactNode
  requiredPermission?: Permission
  requiredPermissions?: Permission[]
  requireAll?: boolean
  fallback?: ReactNode
}

export default function ProtectedRoute({
  children,
  requiredPermission,
  requiredPermissions,
  requireAll = false,
  fallback,
}: ProtectedRouteProps) {
  const { isAuthenticated, isLoading, hasPermission, hasAnyPermission, hasAllPermissions, user } = useAuth()

  console.log('ProtectedRoute check:', {
    isLoading,
    isAuthenticated,
    hasUser: !!user,
    userGroups: user?.groups,
    userPermissions: user?.permissions,
    requiredPermission,
    requiredPermissions
  })

  // Show loading spinner while checking authentication
  if (isLoading) {
    console.log('ProtectedRoute: Still loading auth state')
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  // Redirect to login if not authenticated
  if (!isAuthenticated) {
    console.log('ProtectedRoute: Not authenticated, redirecting to login')
    return <Navigate to="/login" replace />
  }

  // Check permissions if required
  if (requiredPermission) {
    if (!hasPermission(requiredPermission)) {
      if (fallback) {
        return <>{fallback}</>
      }
      return <Navigate to="/access-denied" replace state={{ requiredPermission }} />
    }
  }

  if (requiredPermissions && requiredPermissions.length > 0) {
    const hasRequiredPermissions = requireAll
      ? hasAllPermissions(requiredPermissions)
      : hasAnyPermission(requiredPermissions)

    if (!hasRequiredPermissions) {
      if (fallback) {
        return <>{fallback}</>
      }
      return (
        <Navigate
          to="/access-denied"
          replace
          state={{ requiredPermissions, requireAll }}
        />
      )
    }
  }

  return <>{children}</>
}
