import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios'

// BFF API URL (no API key needed - handled by BFF)
const API_BASE_URL = import.meta.env.VITE_BFF_API_URL || import.meta.env.VITE_API_BASE_URL
const API_KEY = import.meta.env.VITE_API_KEY // Only used for direct API access (fallback)

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
    // Only add API key if using direct API (not BFF)
    ...(API_KEY && !import.meta.env.VITE_BFF_API_URL && { 'x-api-key': API_KEY }),
  },
  timeout: 30000,
  // Enable automatic request cancellation on component unmount
  signal: undefined, // Will be set per-request by React Query
})

// Token getter function (will be set by App.tsx)
let getAccessToken: (() => string | null) | null = null

export function setTokenGetter(getter: () => string | null) {
  getAccessToken = getter
}

// Request interceptor to add authentication token
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    // Add Authorization header if token is available
    if (getAccessToken) {
      const token = getAccessToken()
      console.log('API Request Interceptor:', {
        url: config.url,
        hasToken: !!token,
        tokenPreview: token ? token.substring(0, 20) + '...' : 'none'
      })
      if (token) {
        config.headers.Authorization = `Bearer ${token}`
      } else {
        console.warn('No token available for API request:', config.url)
      }
    } else {
      console.warn('Token getter not configured')
    }
    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error: AxiosError) => {
    if (error.response) {
      // Server responded with error status
      console.error('API Error:', {
        status: error.response.status,
        statusText: error.response.statusText,
        data: error.response.data,
        url: error.config?.url,
        method: error.config?.method
      })

      // Handle 401 Unauthorized - redirect to login
      if (error.response.status === 401) {
        console.warn('Unauthorized - redirecting to login')
        // Clear any stored session data
        window.location.href = '/login'
      }

      // Handle 403 Forbidden - show access denied
      if (error.response.status === 403) {
        console.warn('Forbidden - insufficient permissions', {
          url: error.config?.url,
          response: error.response.data
        })
        // Could redirect to access denied page or show error message
        window.location.href = '/access-denied'
      }
    } else if (error.request) {
      // Request made but no response
      console.error('Network Error:', error.message)
    } else {
      console.error('Request Error:', error.message)
    }
    return Promise.reject(error)
  }
)

export interface RDSInstance {
  instance_id: string
  account_id: string
  region: string
  engine: string
  engine_version: string
  instance_class: string
  status: string
  storage_type: string
  allocated_storage: number
  multi_az: boolean
  publicly_accessible: boolean
  endpoint?: string
  port?: number
  tags: Record<string, string>
  created_at: string
  last_updated: string
}

export interface HealthMetric {
  instance_id: string
  timestamp: string
  cpu_utilization: number
  database_connections: number
  freeable_memory: number
  free_storage_space: number
  read_latency: number
  write_latency: number
  status: 'healthy' | 'warning' | 'critical'
}

export interface HealthAlert {
  alert_id: string
  instance_id: string
  severity: 'Critical' | 'High' | 'Medium' | 'Low'
  metric_name: string
  threshold: number
  current_value: number
  message: string
  created_at: string
  resolved: boolean
}

export interface CostData {
  instance_id: string
  account_id: string
  region: string
  monthly_cost: number
  compute_cost: number
  storage_cost: number
  backup_cost: number
  date: string
}

export interface CostRecommendation {
  instance_id: string
  recommendation_type: string
  current_config: string
  recommended_config: string
  estimated_savings: number
  reason: string
}

export interface ComplianceCheck {
  instance_id: string
  check_name: string
  status: 'compliant' | 'non_compliant'
  severity: 'Critical' | 'High' | 'Medium' | 'Low'
  message: string
  remediation: string
  checked_at: string
}

export interface OperationRequest {
  instance_id: string
  operation_type: 'create_snapshot' | 'reboot' | 'modify_backup_window' | 'stop_instance' | 'start_instance' | 'enable_storage_autoscaling' | 'modify_storage'
  parameters?: Record<string, any>
}

export interface OperationResult {
  operation_id: string
  status: 'success' | 'failed' | 'in_progress'
  message: string
  started_at: string
  completed_at?: string
}

export interface CloudOpsRequest {
  instance_id: string
  request_type: 'scaling' | 'parameter_change' | 'maintenance'
  changes: Record<string, any>
  requested_by?: string
}

export interface CloudOpsResponse {
  request_id: string
  instance_id: string
  request_type: string
  markdown_url: string
  text_url: string
  created_at: string
}

// API functions
export const api = {
  // Instances
  getInstances: async (filters?: {
    account?: string
    region?: string
    engine?: string
    status?: string
  }) => {
    const params = new URLSearchParams()
    if (filters?.account) params.append('account', filters.account)
    if (filters?.region) params.append('region', filters.region)
    if (filters?.engine) params.append('engine', filters.engine)
    if (filters?.status) params.append('status', filters.status)
    
    const response = await apiClient.get<{ instances: RDSInstance[] }>(
      `/api/instances?${params.toString()}`
    )
    return response.data.instances
  },

  getInstance: async (instanceId: string) => {
    const response = await apiClient.get<{ instance: RDSInstance }>(`/api/instances/${instanceId}`)
    return response.data.instance
  },

  // Health
  getHealth: async (instanceId?: string) => {
    const url = instanceId ? `/api/health/${instanceId}` : '/api/health'
    const response = await apiClient.get<{ metrics: HealthMetric[] }>(url)
    return response.data.metrics
  },

  getAlerts: async (instanceId?: string) => {
    // Use /health endpoint instead of /alerts (they're the same)
    const url = instanceId ? `/api/health/${instanceId}` : '/api/health'
    const response = await apiClient.get<{ alerts: HealthAlert[] }>(url)
    return response.data.alerts || []
  },

  // Costs
  getCosts: async (filters?: { account?: string; region?: string }) => {
    const params = new URLSearchParams()
    if (filters?.account) params.append('account', filters.account)
    if (filters?.region) params.append('region', filters.region)
    
    const response = await apiClient.get<{ costs?: CostData[]; total_cost?: number; message?: string }>(
      `/api/costs?${params.toString()}`
    )
    // API returns {total_cost, costs: {}} but frontend expects array
    // Return empty array if costs not available yet
    return response.data.costs || []
  },

  getRecommendations: async () => {
    const response = await apiClient.get<{ recommendations: CostRecommendation[] }>(
      '/api/costs?action=recommendations'
    )
    return response.data.recommendations || []
  },

  // Compliance
  getCompliance: async (instanceId?: string) => {
    const url = instanceId ? `/api/compliance/${instanceId}` : '/api/compliance'
    const response = await apiClient.get<{ checks?: ComplianceCheck[]; message?: string }>(url)
    return response.data.checks || []
  },

  // Operations
  executeOperation: async (request: OperationRequest) => {
    const response = await apiClient.post<OperationResult>('/api/operations', request)
    return response.data
  },

  // CloudOps Requests
  generateCloudOpsRequest: async (request: CloudOpsRequest) => {
    const response = await apiClient.post<CloudOpsResponse>('/api/cloudops', request)
    return response.data
  },

  getCloudOpsHistory: async (instanceId?: string) => {
    const url = instanceId 
      ? `/api/cloudops/history?instance_id=${instanceId}`
      : '/api/cloudops/history'
    const response = await apiClient.get<{ requests: CloudOpsResponse[] }>(url)
    return response.data.requests || []
  },

  // Discovery
  triggerDiscovery: async () => {
    const response = await apiClient.post<{ message: string; execution_id?: string }>(
      '/api/discovery/trigger'
    )
    return response.data
  },

  // Error Resolution
  getErrorDashboard: async (widgets?: string[]) => {
    const params = new URLSearchParams()
    if (widgets && widgets.length > 0) {
      params.append('widgets', widgets.join(','))
    }
    
    const response = await apiClient.get(
      `/api/errors/dashboard?${params.toString()}`
    )
    return response.data
  },

  getErrorStatistics: async () => {
    const response = await apiClient.get('/api/errors/statistics')
    return response.data
  },

  detectError: async (errorData: {
    status_code: number
    error_message: string
    service: string
    endpoint: string
    request_id: string
    context?: Record<string, any>
    user_id?: string
    stack_trace?: string
  }) => {
    const response = await apiClient.post('/api/errors/detect', errorData)
    return response.data
  },

  resolveError: async (resolutionData: {
    error_id: string
    resolution_strategy?: string
    api_error: {
      status_code: number
      message: string
      service: string
      endpoint: string
      category: string
      severity: string
      request_id?: string
      user_id?: string
      context?: Record<string, any>
    }
    context?: Record<string, any>
  }) => {
    const response = await apiClient.post('/api/errors/resolve', resolutionData)
    return response.data
  },

  rollbackResolution: async (attemptId: string) => {
    const response = await apiClient.post('/api/errors/rollback', {
      attempt_id: attemptId
    })
    return response.data
  },

  getResolutionAttempt: async (attemptId: string) => {
    const response = await apiClient.get(`/api/errors/attempts/${attemptId}`)
    return response.data
  },

  getErrorResolutionHealth: async () => {
    const response = await apiClient.get('/api/errors/health')
    return response.data
  },
}
