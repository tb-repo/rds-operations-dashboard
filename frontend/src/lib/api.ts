import axios from 'axios'

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
})

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response) {
      // Server responded with error status
      console.error('API Error:', error.response.status, error.response.data)
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
  operation_type: 'create_snapshot' | 'reboot' | 'modify_backup_window'
  parameters?: Record<string, any>
}

export interface OperationResult {
  operation_id: string
  status: 'success' | 'failed' | 'in_progress'
  message: string
  started_at: string
  completed_at?: string
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
      `/instances?${params.toString()}`
    )
    return response.data.instances
  },

  getInstance: async (instanceId: string) => {
    const response = await apiClient.get<RDSInstance>(`/instances/${instanceId}`)
    return response.data
  },

  // Health
  getHealth: async (instanceId?: string) => {
    const url = instanceId ? `/health/${instanceId}` : '/health'
    const response = await apiClient.get<{ metrics: HealthMetric[] }>(url)
    return response.data.metrics
  },

  getAlerts: async (instanceId?: string) => {
    const url = instanceId ? `/alerts/${instanceId}` : '/alerts'
    const response = await apiClient.get<{ alerts: HealthAlert[] }>(url)
    return response.data.alerts
  },

  // Costs
  getCosts: async (filters?: { account?: string; region?: string }) => {
    const params = new URLSearchParams()
    if (filters?.account) params.append('account', filters.account)
    if (filters?.region) params.append('region', filters.region)
    
    const response = await apiClient.get<{ costs: CostData[] }>(
      `/costs?${params.toString()}`
    )
    return response.data.costs
  },

  getRecommendations: async () => {
    const response = await apiClient.get<{ recommendations: CostRecommendation[] }>(
      '/costs/recommendations'
    )
    return response.data.recommendations
  },

  // Compliance
  getCompliance: async (instanceId?: string) => {
    const url = instanceId ? `/compliance/${instanceId}` : '/compliance'
    const response = await apiClient.get<{ checks: ComplianceCheck[] }>(url)
    return response.data.checks
  },

  // Operations
  executeOperation: async (request: OperationRequest) => {
    const response = await apiClient.post<OperationResult>('/operations', request)
    return response.data
  },

  generateCloudOpsRequest: async (data: {
    instance_id: string
    request_type: string
    parameters: Record<string, any>
  }) => {
    const response = await apiClient.post<{ request_text: string; s3_path: string }>(
      '/cloudops-request',
      data
    )
    return response.data
  },
}
