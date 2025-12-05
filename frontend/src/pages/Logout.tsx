import { useEffect } from 'react'
import { useAuth } from '../lib/auth/AuthContext'
import LoadingSpinner from '../components/LoadingSpinner'

export default function Logout() {
  const { logout } = useAuth()

  useEffect(() => {
    // Perform logout
    logout()
  }, [logout])

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-8 text-center">
        <LoadingSpinner size="lg" />
        <h2 className="text-2xl font-bold text-gray-900 mt-4 mb-2">
          Signing Out
        </h2>
        <p className="text-gray-600">Please wait while we sign you out...</p>
      </div>
    </div>
  )
}
