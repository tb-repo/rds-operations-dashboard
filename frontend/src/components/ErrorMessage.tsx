import { AlertCircle, RefreshCw } from 'lucide-react'

interface ErrorMessageProps {
  message: string
  error?: any
  onRetry?: () => void
}

export default function ErrorMessage({ message, error, onRetry }: ErrorMessageProps) {
  // Extract user-friendly error message
  const getErrorDetails = () => {
    if (!error) return null
    
    if (error.response) {
      const status = error.response.status
      const data = error.response.data
      
      switch (status) {
        case 400:
          return 'Invalid request. Please check your input and try again.'
        case 401:
          return 'Your session has expired. Please log in again.'
        case 403:
          return 'You don\'t have permission to access this resource.'
        case 404:
          return 'The requested resource was not found.'
        case 500:
          return 'Server error. Please try again later.'
        case 503:
          return 'Service temporarily unavailable. Please try again in a few moments.'
        default:
          return data?.message || data?.error || null
      }
    } else if (error.request) {
      return 'Network error. Please check your connection and try again.'
    } else if (error.message) {
      return error.message
    }
    return null
  }

  const errorDetails = getErrorDetails()

  return (
    <div className="card bg-red-50 border-red-200">
      <div className="flex items-start gap-3">
        <AlertCircle className="h-5 w-5 text-red-600 mt-0.5" />
        <div className="flex-1">
          <h3 className="text-sm font-medium text-red-800">Error</h3>
          <p className="mt-1 text-sm text-red-700">{message}</p>
          {errorDetails && (
            <p className="mt-1 text-xs text-red-600">{errorDetails}</p>
          )}
          {onRetry && (
            <button
              onClick={onRetry}
              className="mt-3 inline-flex items-center gap-1.5 text-sm font-medium text-red-600 hover:text-red-500"
            >
              <RefreshCw className="h-3.5 w-3.5" />
              Try again
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
