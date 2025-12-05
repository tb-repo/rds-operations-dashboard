import { useNavigate } from 'react-router-dom'
import { ShieldAlert, ArrowLeft } from 'lucide-react'

interface AccessDeniedProps {
  requiredPermission?: string
}

export default function AccessDenied({ requiredPermission }: AccessDeniedProps) {
  const navigate = useNavigate()

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-8 text-center">
        <div className="text-red-600 mb-4">
          <ShieldAlert className="w-16 h-16 mx-auto" />
        </div>
        
        <h1 className="text-3xl font-bold text-gray-900 mb-2">
          Access Denied
        </h1>
        
        <p className="text-gray-600 mb-6">
          You don't have permission to access this resource.
        </p>

        {requiredPermission && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
            <p className="text-sm text-red-800">
              <span className="font-semibold">Required permission:</span>{' '}
              <code className="bg-red-100 px-2 py-1 rounded">
                {requiredPermission}
              </code>
            </p>
          </div>
        )}

        <div className="space-y-3">
          <button
            onClick={() => navigate(-1)}
            className="w-full bg-gray-600 hover:bg-gray-700 text-white font-semibold py-3 px-4 rounded-lg transition-colors duration-200 flex items-center justify-center"
          >
            <ArrowLeft className="w-5 h-5 mr-2" />
            Go Back
          </button>

          <button
            onClick={() => navigate('/')}
            className="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg transition-colors duration-200"
          >
            Go to Dashboard
          </button>
        </div>

        <div className="mt-6 text-sm text-gray-500">
          <p>
            If you believe you should have access, please contact your
            administrator.
          </p>
        </div>
      </div>
    </div>
  )
}
