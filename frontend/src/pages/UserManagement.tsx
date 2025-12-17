import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Users, UserPlus, UserMinus, Shield } from 'lucide-react'
import { apiClient } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'

interface UserInfo {
  id: string
  email: string
  name?: string
  groups: string[]
  status: string
  createdAt: string
  lastLogin?: string
}

export default function UserManagement() {
  const queryClient = useQueryClient()
  const [selectedUser, setSelectedUser] = useState<string | null>(null)
  const [selectedRole, setSelectedRole] = useState<string>('')

  const { data: usersData, isLoading, error } = useQuery({
    queryKey: ['users'],
    queryFn: async () => {
      const response = await apiClient.get<{ users: UserInfo[]; total: number }>('/api/users')
      return response.data
    },
  })

  const addRoleMutation = useMutation({
    mutationFn: async ({ userId, role }: { userId: string; role: string }) => {
      await apiClient.post(`/api/users/${userId}/groups`, { group: role })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      setSelectedUser(null)
      setSelectedRole('')
      alert('Role added successfully')
    },
    onError: (error: any) => {
      alert(`Failed to add role: ${error.response?.data?.message || error.message}`)
    },
  })

  const removeRoleMutation = useMutation({
    mutationFn: async ({ userId, role }: { userId: string; role: string }) => {
      await apiClient.delete(`/api/users/${userId}/groups/${role}`)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      alert('Role removed successfully')
    },
    onError: (error: any) => {
      alert(`Failed to remove role: ${error.response?.data?.message || error.message}`)
    },
  })

  if (isLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (error) {
    return <ErrorMessage message="Failed to load users" />
  }

  const users = usersData?.users || []
  const availableRoles = ['Admin', 'DBA', 'ReadOnly']

  const handleAddRole = () => {
    if (!selectedUser || !selectedRole) return
    
    if (confirm(`Add ${selectedRole} role to this user?`)) {
      addRoleMutation.mutate({ userId: selectedUser, role: selectedRole })
    }
  }

  const handleRemoveRole = (userId: string, role: string) => {
    if (confirm(`Remove ${role} role from this user?`)) {
      removeRoleMutation.mutate({ userId, role })
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">User Management</h1>
          <p className="text-sm text-gray-600 mt-1">
            Manage user roles and permissions
          </p>
        </div>
        <div className="flex items-center gap-2 text-sm text-gray-600">
          <Users className="w-5 h-5" />
          <span>{users.length} users</span>
        </div>
      </div>

      {/* Users Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  User
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Email
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Roles
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {users.map((user) => (
                <tr key={user.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="flex-shrink-0 h-10 w-10 bg-blue-100 rounded-full flex items-center justify-center">
                        <Shield className="h-5 w-5 text-blue-600" />
                      </div>
                      <div className="ml-4">
                        <div className="text-sm font-medium text-gray-900">
                          {user.name || user.id}
                        </div>
                        <div className="text-sm text-gray-500">
                          {user.id}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">{user.email}</div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex flex-wrap gap-2">
                      {user.groups.length > 0 ? (
                        user.groups.map((role) => (
                          <span
                            key={role}
                            className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
                          >
                            {role}
                            <button
                              onClick={() => handleRemoveRole(user.id, role)}
                              className="ml-1 hover:text-blue-900"
                              title="Remove role"
                            >
                              <UserMinus className="w-3 h-3" />
                            </button>
                          </span>
                        ))
                      ) : (
                        <span className="text-sm text-gray-500">No roles</span>
                      )}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span
                      className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                        user.status === 'CONFIRMED'
                          ? 'bg-green-100 text-green-800'
                          : 'bg-yellow-100 text-yellow-800'
                      }`}
                    >
                      {user.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <button
                      onClick={() => setSelectedUser(user.id)}
                      className="text-blue-600 hover:text-blue-900 flex items-center gap-1"
                    >
                      <UserPlus className="w-4 h-4" />
                      Add Role
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add Role Modal */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">
              Add Role to User
            </h3>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Select Role
                </label>
                <select
                  value={selectedRole}
                  onChange={(e) => setSelectedRole(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500"
                >
                  <option value="">Choose a role...</option>
                  {availableRoles.map((role) => (
                    <option key={role} value={role}>
                      {role}
                    </option>
                  ))}
                </select>
              </div>

              <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
                <p className="text-sm text-blue-800">
                  <strong>Admin:</strong> Full system access including user management<br />
                  <strong>DBA:</strong> Database operations and CloudOps generation<br />
                  <strong>ReadOnly:</strong> View-only access to all dashboards
                </p>
              </div>
            </div>

            <div className="mt-6 flex gap-3">
              <button
                onClick={handleAddRole}
                disabled={!selectedRole || addRoleMutation.isPending}
                className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {addRoleMutation.isPending ? 'Adding...' : 'Add Role'}
              </button>
              <button
                onClick={() => {
                  setSelectedUser(null)
                  setSelectedRole('')
                }}
                className="flex-1 bg-gray-200 text-gray-800 px-4 py-2 rounded-lg hover:bg-gray-300"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
