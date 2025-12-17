import { Outlet, Link, useLocation } from 'react-router-dom'
import { Database, LayoutDashboard, DollarSign, Shield, RefreshCw, Users, LogOut } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth/AuthContext'
import PermissionGuard from './PermissionGuard'

export default function Layout() {
  const location = useLocation()
  const queryClient = useQueryClient()
  const { user, logout } = useAuth()

  const navigation = [
    { name: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
    { name: 'Instances', href: '/instances', icon: Database },
    { name: 'Costs', href: '/costs', icon: DollarSign },
    { name: 'Compliance', href: '/compliance', icon: Shield },
    { name: 'Approvals', href: '/approvals', icon: Shield, permission: 'execute_operations' },
  ]

  const handleRefresh = () => {
    queryClient.invalidateQueries()
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <div className="flex items-center">
              <Database className="h-8 w-8 text-blue-600" />
              <h1 className="ml-3 text-xl font-semibold text-gray-900">
                RDS Command Hub
              </h1>
            </div>
            <div className="flex items-center gap-4">
              {user && (
                <div className="text-sm text-gray-600">
                  {user.email}
                </div>
              )}
              <button
                onClick={handleRefresh}
                className="flex items-center gap-2 px-3 py-2 text-sm text-gray-700 hover:text-gray-900 hover:bg-gray-100 rounded-md transition-colors"
              >
                <RefreshCw className="h-4 w-4" />
                Refresh
              </button>
              <button
                onClick={logout}
                className="flex items-center gap-2 px-3 py-2 text-sm text-gray-700 hover:text-gray-900 hover:bg-gray-100 rounded-md transition-colors"
              >
                <LogOut className="h-4 w-4" />
                Logout
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Navigation */}
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex space-x-8">
            {navigation.map((item) => {
              const Icon = item.icon
              const isActive = location.pathname === item.href
              return (
                <Link
                  key={item.name}
                  to={item.href}
                  className={`
                    flex items-center gap-2 px-3 py-4 text-sm font-medium border-b-2 transition-colors
                    ${
                      isActive
                        ? 'border-blue-600 text-blue-600'
                        : 'border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300'
                    }
                  `}
                >
                  <Icon className="h-4 w-4" />
                  {item.name}
                </Link>
              )
            })}
            
            {/* User Management - Only visible for users with manage_users permission */}
            <PermissionGuard permission="manage_users">
              <Link
                to="/users"
                className={`
                  flex items-center gap-2 px-3 py-4 text-sm font-medium border-b-2 transition-colors
                  ${
                    location.pathname === '/users'
                      ? 'border-blue-600 text-blue-600'
                      : 'border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300'
                  }
                `}
              >
                <Users className="h-4 w-4" />
                Users
              </Link>
            </PermissionGuard>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <Outlet />
      </main>
    </div>
  )
}
