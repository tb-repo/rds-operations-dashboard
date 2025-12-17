import { useEffect } from 'react'
import { useAuth } from '../lib/auth/AuthContext'
import { useNavigate } from 'react-router-dom'
import { Database, Lock } from 'lucide-react'

export default function Login() {
  const { login, isAuthenticated } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    // If already authenticated, redirect to dashboard
    if (isAuthenticated) {
      navigate('/')
    }
  }, [isAuthenticated, navigate])

  const handleLogin = async () => {
    await login()
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow-xl p-8">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-blue-600 rounded-full mb-4">
            <Database className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            RDS Command Hub
          </h1>
          <p className="text-gray-600">
            Secure access for database administrators
          </p>
        </div>

        <div className="space-y-6">
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <div className="flex items-start">
              <Lock className="w-5 h-5 text-blue-600 mt-0.5 mr-3 flex-shrink-0" />
              <div className="text-sm text-blue-800">
                <p className="font-medium mb-1">Secure Authentication</p>
                <p>
                  You will be redirected to the corporate login page to sign in
                  with your credentials.
                </p>
              </div>
            </div>
          </div>

          <button
            onClick={handleLogin}
            className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg transition-colors duration-200 flex items-center justify-center"
          >
            <Lock className="w-5 h-5 mr-2" />
            Sign In with Corporate Account
          </button>

          <div className="text-center text-sm text-gray-500">
            <p>Need help? Contact your administrator</p>
          </div>
        </div>
      </div>
    </div>
  )
}
