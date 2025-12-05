import { useEffect, useState, useRef } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { CognitoService } from '../lib/auth/cognito'
import { useAuth } from '../lib/auth/AuthContext'
import LoadingSpinner from '../components/LoadingSpinner'

interface CallbackProps {
  cognitoService: CognitoService
  onAuthSuccess: () => void
}

export default function Callback({ cognitoService, onAuthSuccess }: CallbackProps) {
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const { refreshAuth } = useAuth()
  const [error, setError] = useState<string | null>(null)
  const processedCodeRef = useRef<string | null>(null)
  const isProcessingRef = useRef(false)

  // Clean URL helper function
  const cleanUrl = () => {
    const url = new URL(window.location.href)
    url.searchParams.delete('code')
    url.searchParams.delete('state')
    url.searchParams.delete('error')
    window.history.replaceState({}, document.title, url.toString())
  }

  useEffect(() => {
    const handleCallback = async () => {
      const code = searchParams.get('code')
      const state = searchParams.get('state')
      const errorParam = searchParams.get('error')
      
      // Prevent double execution by tracking the specific code we've processed
      if (code && processedCodeRef.current === code) {
        console.log('Callback already processing this code, skipping...')
        return
      }
      
      // Prevent double execution in React Strict Mode
      if (isProcessingRef.current) {
        console.log('Callback already in progress, skipping...')
        return
      }
      
      if (code) {
        processedCodeRef.current = code
        isProcessingRef.current = true
      }
      
      console.log('Starting callback processing...')
      
      try {

        if (errorParam) {
          setError(`Authentication failed: ${errorParam}`)
          cleanUrl()
          setTimeout(() => navigate('/login'), 3000)
          return
        }

        if (!code) {
          setError('No authorization code received')
          setTimeout(() => navigate('/login'), 3000)
          return
        }

        // Exchange code for tokens (pass state parameter)
        const tokens = await cognitoService.handleCallback(code, state || undefined)

        // Set session
        const payload = cognitoService.parseToken(tokens.idToken)
        cognitoService.setSession({
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: payload.exp * 1000,
        })

        console.log('Session set successfully')

        // Clean URL immediately after successful token exchange
        // This prevents the authorization code from being reused if the page reloads
        cleanUrl()

        // Notify parent component of successful auth
        onAuthSuccess()

        // Refresh auth context to load user data from the new session
        console.log('Refreshing auth context...')
        refreshAuth()

        // Small delay to ensure auth context updates before navigation
        setTimeout(() => {
          console.log('Navigating to dashboard...')
          navigate('/', { replace: true })
        }, 100)
      } catch (err) {
        console.error('Callback error:', err)
        // Reset so user can try again
        processedCodeRef.current = null
        isProcessingRef.current = false
        cleanUrl()
        setError('Failed to complete authentication')
        setTimeout(() => navigate('/login'), 3000)
      }
    }

    handleCallback()
  }, []) // Empty dependency array to prevent re-execution

  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
        <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-8 text-center">
          <div className="text-red-600 mb-4">
            <svg
              className="w-16 h-16 mx-auto"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
          </div>
          <h2 className="text-2xl font-bold text-gray-900 mb-2">
            Authentication Error
          </h2>
          <p className="text-gray-600 mb-4">{error}</p>
          <p className="text-sm text-gray-500">Redirecting to login...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-white rounded-lg shadow-lg p-8 text-center">
        <LoadingSpinner size="lg" />
        <h2 className="text-2xl font-bold text-gray-900 mt-4 mb-2">
          Completing Sign In
        </h2>
        <p className="text-gray-600">Please wait while we verify your credentials...</p>
      </div>
    </div>
  )
}
