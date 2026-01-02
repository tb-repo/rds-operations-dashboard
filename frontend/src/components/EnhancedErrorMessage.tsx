/**
 * Enhanced Error Message Component
 * 
 * Displays error messages with integrated error resolution capabilities.
 * Automatically detects and classifies errors, provides resolution suggestions.
 * 
 * Metadata:
 * {
 *   "generated_by": "claude-3.5-sonnet",
 *   "timestamp": "2025-12-16T14:30:00Z",
 *   "version": "1.0.0",
 *   "policy_version": "v1.0.0",
 *   "traceability": "REQ-6.1, 6.2 → DESIGN-Integration → TASK-7",
 *   "review_status": "Pending",
 *   "risk_level": "Level 2",
 *   "reviewed_by": null,
 *   "approved_by": null
 * }
 */

import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { 
  AlertCircle, 
  RefreshCw, 
  Zap, 
  CheckCircle, 
  XCircle,
  Info,
  AlertTriangle
} from 'lucide-react'
import { api } from '@/lib/api'

interface EnhancedErrorMessageProps {
  message: string
  error?: any
  service?: string
  endpoint?: string
  onRetry?: () => void
  autoResolve?: boolean
  showResolutionOptions?: boolean
}

interface ErrorClassification {
  error_id: string
  category: string
  severity: string
  is_critical: boolean
  should_retry: boolean
  classification: any
}

interface ResolutionAttempt {
  attempt_id: string
  error_id: string
  strategy: string
  status: string
  success: boolean
  message: string
  started_at: string
  completed_at?: string
}

export default function EnhancedErrorMessage({ 
  message, 
  error, 
  service = 'unknown',
  endpoint = 'unknown',
  onRetry,
  autoResolve = false,
  showResolutionOptions = true
}: EnhancedErrorMessageProps) {
  const [classification, setClassification] = useState<ErrorClassification | null>(null)
  const [resolutionAttempt, setResolutionAttempt] = useState<ResolutionAttempt | null>(null)
  const [isResolving, setIsResolving] = useState(false)
  const [showDetails, setShowDetails] = useState(false)
  const queryClient = useQueryClient()

  // Extract error details
  const getErrorDetails = () => {
    if (!error) return { statusCode: 500, errorMessage: message }
    
    if (error.response) {
      const status = error.response.status
      const data = error.response.data
      
      return {
        statusCode: status,
        errorMessage: data?.message || data?.error || message,
        requestId: error.response.headers?.['x-request-id'] || `req_${Date.now()}`,
        stackTrace: data?.stack || error.stack
      }
    } else if (error.request) {
      return {
        statusCode: 0,
        errorMessage: 'Network error. Please check your connection.',
        requestId: `req_${Date.now()}`
      }
    } else {
      return {
        statusCode: 500,
        errorMessage: error.message || message,
        requestId: `req_${Date.now()}`
      }
    }
  }

  const errorDetails = getErrorDetails()

  // Detect error mutation
  const detectErrorMutation = useMutation({
    mutationFn: (errorData: any) => api.detectError(errorData),
    onSuccess: (data: ErrorClassification) => {
      setClassification(data)
      
      // Auto-resolve if enabled and error should be retried
      if (autoResolve && data.should_retry && !data.is_critical) {
        handleAutoResolve(data)
      }
    },
    onError: (err) => {
      console.error('Failed to detect error:', err)
    }
  })

  // Resolve error mutation
  const resolveErrorMutation = useMutation({
    mutationFn: (resolutionData: any) => api.resolveError(resolutionData),
    onSuccess: (data: ResolutionAttempt) => {
      setResolutionAttempt(data)
      setIsResolving(false)
      
      // If resolution was successful, invalidate queries and retry
      if (data.success && onRetry) {
        setTimeout(() => {
          onRetry()
          queryClient.invalidateQueries()
        }, 1000)
      }
    },
    onError: (err) => {
      console.error('Failed to resolve error:', err)
      setIsResolving(false)
    }
  })

  // Auto-detect error on mount
  useEffect(() => {
    if (errorDetails.statusCode >= 400) {
      detectErrorMutation.mutate({
        status_code: errorDetails.statusCode,
        error_message: errorDetails.errorMessage,
        service,
        endpoint,
        request_id: errorDetails.requestId,
        context: {
          user_agent: navigator.userAgent,
          url: window.location.href,
          timestamp: new Date().toISOString()
        },
        stack_trace: errorDetails.stackTrace
      })
    }
  }, [errorDetails.statusCode, errorDetails.errorMessage, service, endpoint])

  const handleAutoResolve = (errorClassification: ErrorClassification) => {
    if (isResolving) return
    
    setIsResolving(true)
    
    // Determine resolution strategy based on error category
    let strategy = 'retry_with_backoff'
    if (errorClassification.category === 'authentication') {
      strategy = 'refresh_credentials'
    } else if (errorClassification.category === 'rate_limit') {
      strategy = 'exponential_backoff'
    } else if (errorClassification.category === 'network') {
      strategy = 'circuit_breaker'
    }

    resolveErrorMutation.mutate({
      error_id: errorClassification.error_id,
      resolution_strategy: strategy,
      api_error: {
        status_code: errorDetails.statusCode,
        message: errorDetails.errorMessage,
        service,
        endpoint,
        category: errorClassification.category,
        severity: errorClassification.severity,
        request_id: errorDetails.requestId,
        context: {
          auto_resolve: true,
          strategy_selected: strategy
        }
      }
    })
  }

  const handleManualResolve = (strategy: string) => {
    if (!classification || isResolving) return
    
    setIsResolving(true)
    
    resolveErrorMutation.mutate({
      error_id: classification.error_id,
      resolution_strategy: strategy,
      api_error: {
        status_code: errorDetails.statusCode,
        message: errorDetails.errorMessage,
        service,
        endpoint,
        category: classification.category,
        severity: classification.severity,
        request_id: errorDetails.requestId,
        context: {
          manual_resolve: true,
          strategy_selected: strategy
        }
      }
    })
  }

  const getSeverityColor = (severity: string) => {
    switch (severity?.toLowerCase()) {
      case 'critical': return 'text-red-600 bg-red-50 border-red-200'
      case 'high': return 'text-orange-600 bg-orange-50 border-orange-200'
      case 'medium': return 'text-yellow-600 bg-yellow-50 border-yellow-200'
      case 'low': return 'text-blue-600 bg-blue-50 border-blue-200'
      default: return 'text-red-600 bg-red-50 border-red-200'
    }
  }

  const getSeverityIcon = (severity: string) => {
    switch (severity?.toLowerCase()) {
      case 'critical': return <AlertTriangle className="h-5 w-5" />
      case 'high': return <AlertCircle className="h-5 w-5" />
      case 'medium': return <Info className="h-5 w-5" />
      case 'low': return <Info className="h-5 w-5" />
      default: return <AlertCircle className="h-5 w-5" />
    }
  }

  const getResolutionStrategies = (category: string) => {
    switch (category) {
      case 'authentication':
        return [
          { key: 'refresh_credentials', label: 'Refresh Credentials', description: 'Attempt to refresh authentication tokens' },
          { key: 'retry_with_backoff', label: 'Retry with Backoff', description: 'Retry the request with exponential backoff' }
        ]
      case 'rate_limit':
        return [
          { key: 'exponential_backoff', label: 'Exponential Backoff', description: 'Wait and retry with increasing delays' },
          { key: 'circuit_breaker', label: 'Circuit Breaker', description: 'Temporarily stop requests to allow recovery' }
        ]
      case 'network':
        return [
          { key: 'retry_with_backoff', label: 'Retry with Backoff', description: 'Retry the request with delays' },
          { key: 'circuit_breaker', label: 'Circuit Breaker', description: 'Implement circuit breaker pattern' }
        ]
      case 'database':
        return [
          { key: 'connection_retry', label: 'Connection Retry', description: 'Retry database connection' },
          { key: 'circuit_breaker', label: 'Circuit Breaker', description: 'Prevent cascading failures' }
        ]
      default:
        return [
          { key: 'retry_with_backoff', label: 'Retry with Backoff', description: 'Standard retry mechanism' }
        ]
    }
  }

  return (
    <div className={`card border ${classification ? getSeverityColor(classification.severity) : 'bg-red-50 border-red-200'}`}>
      <div className="flex items-start gap-3">
        {classification ? getSeverityIcon(classification.severity) : <AlertCircle className="h-5 w-5 text-red-600 mt-0.5" />}
        
        <div className="flex-1">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-medium">
              {classification ? `${classification.severity.toUpperCase()} Error` : 'Error'}
            </h3>
            {classification && (
              <span className="text-xs px-2 py-1 rounded-full bg-white bg-opacity-50">
                {classification.category}
              </span>
            )}
          </div>
          
          <p className="mt-1 text-sm">{message}</p>
          
          {/* Error Classification Info */}
          {classification && (
            <div className="mt-2 text-xs space-y-1">
              <div className="flex items-center gap-2">
                <span className="font-medium">Error ID:</span>
                <code className="bg-white bg-opacity-50 px-1 rounded">{classification.error_id}</code>
              </div>
              {classification.is_critical && (
                <div className="flex items-center gap-1 text-red-600">
                  <AlertTriangle className="w-3 h-3" />
                  <span className="font-medium">Critical error - requires immediate attention</span>
                </div>
              )}
            </div>
          )}

          {/* Resolution Status */}
          {resolutionAttempt && (
            <div className="mt-3 p-2 bg-white bg-opacity-50 rounded-lg">
              <div className="flex items-center gap-2 text-xs">
                {resolutionAttempt.success ? (
                  <CheckCircle className="w-4 h-4 text-green-600" />
                ) : (
                  <XCircle className="w-4 h-4 text-red-600" />
                )}
                <span className="font-medium">
                  Resolution {resolutionAttempt.success ? 'Successful' : 'Failed'}
                </span>
                <span className="text-gray-600">({resolutionAttempt.strategy})</span>
              </div>
              <p className="mt-1 text-xs text-gray-600">{resolutionAttempt.message}</p>
            </div>
          )}

          {/* Action Buttons */}
          <div className="mt-3 flex items-center gap-2">
            {onRetry && (
              <button
                onClick={onRetry}
                disabled={isResolving}
                className="inline-flex items-center gap-1.5 text-sm font-medium hover:opacity-80 disabled:opacity-50"
              >
                <RefreshCw className={`h-3.5 w-3.5 ${isResolving ? 'animate-spin' : ''}`} />
                {isResolving ? 'Resolving...' : 'Try again'}
              </button>
            )}

            {classification && showResolutionOptions && !resolutionAttempt?.success && (
              <button
                onClick={() => setShowDetails(!showDetails)}
                className="text-sm font-medium hover:opacity-80"
              >
                {showDetails ? 'Hide' : 'Show'} Resolution Options
              </button>
            )}
          </div>

          {/* Resolution Options */}
          {showDetails && classification && showResolutionOptions && !resolutionAttempt?.success && (
            <div className="mt-3 p-3 bg-white bg-opacity-50 rounded-lg">
              <h4 className="text-sm font-medium mb-2">Available Resolution Strategies:</h4>
              <div className="space-y-2">
                {getResolutionStrategies(classification.category).map((strategy) => (
                  <button
                    key={strategy.key}
                    onClick={() => handleManualResolve(strategy.key)}
                    disabled={isResolving}
                    className="w-full text-left p-2 bg-white bg-opacity-50 rounded hover:bg-opacity-75 disabled:opacity-50 transition-colors"
                  >
                    <div className="flex items-center gap-2">
                      <Zap className="w-4 h-4" />
                      <div>
                        <div className="text-sm font-medium">{strategy.label}</div>
                        <div className="text-xs text-gray-600">{strategy.description}</div>
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Loading State */}
          {(detectErrorMutation.isPending || isResolving) && (
            <div className="mt-2 flex items-center gap-2 text-xs text-gray-600">
              <RefreshCw className="w-3 h-3 animate-spin" />
              <span>
                {detectErrorMutation.isPending ? 'Analyzing error...' : 'Attempting resolution...'}
              </span>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}