import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
// import { Activity, HardDrive, Cpu, Database as DatabaseIcon } from 'lucide-react'
import { api, OperationRequest } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import StatusBadge from '@/components/StatusBadge'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'

export default function InstanceDetail() {
  const { instanceId } = useParams<{ instanceId: string }>()
  const queryClient = useQueryClient()
  const [selectedOperation, setSelectedOperation] = useState<string>('')

  const { data: instance, isLoading: instanceLoading, error: instanceError } = useQuery({
    queryKey: ['instance', instanceId],
    queryFn: () => api.getInstance(instanceId!),
    enabled: !!instanceId,
  })

  const { data: health, isLoading: healthLoading } = useQuery({
    queryKey: ['health', instanceId],
    queryFn: () => api.getHealth(instanceId!),
    enabled: !!instanceId,
    retry: false, // Don't retry if endpoint doesn't exist
  })

  const { data: alerts } = useQuery({
    queryKey: ['alerts', instanceId],
    queryFn: () => api.getAlerts(instanceId!),
    enabled: !!instanceId,
    retry: false, // Don't retry if endpoint doesn't exist
  })

  const operationMutation = useMutation({
    mutationFn: (request: OperationRequest) => api.executeOperation(request),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['instance', instanceId] })
      setSelectedOperation('')
      alert('Operation executed successfully')
    },
    onError: (error: any) => {
      alert(`Operation failed: ${error.response?.data?.message || error.message}`)
    },
  })

  if (instanceLoading || healthLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (instanceError || !instance) {
    return <ErrorMessage message="Failed to load instance details" />
  }

  const handleOperation = () => {
    if (!selectedOperation) return

    const request: OperationRequest = {
      instance_id: instanceId!,
      operation_type: selectedOperation as any,
    }

    if (confirm(`Are you sure you want to execute ${selectedOperation}?`)) {
      operationMutation.mutate(request)
    }
  }

  // Prepare chart data
  const chartData = health?.map((h) => ({
    time: new Date(h.timestamp).toLocaleTimeString(),
    cpu: h.cpu_utilization,
    connections: h.database_connections,
    memory: ((h.freeable_memory / (1024 * 1024 * 1024))).toFixed(2), // Convert to GB
  })) || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex justify-between items-start">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{instance.instance_id}</h1>
          <p className="mt-1 text-sm text-gray-600">
            {instance.engine} {instance.engine_version} • {instance.instance_class}
          </p>
        </div>
        <StatusBadge status={instance.status} />
      </div>

      {/* Instance Details */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div className="card">
          <h3 className="text-sm font-medium text-gray-600 mb-2">Account & Region</h3>
          <p className="text-lg font-semibold text-gray-900">{instance.account_id}</p>
          <p className="text-sm text-gray-600">{instance.region}</p>
        </div>

        <div className="card">
          <h3 className="text-sm font-medium text-gray-600 mb-2">Storage</h3>
          <p className="text-lg font-semibold text-gray-900">
            {instance.allocated_storage} GB
          </p>
          <p className="text-sm text-gray-600">{instance.storage_type}</p>
        </div>

        <div className="card">
          <h3 className="text-sm font-medium text-gray-600 mb-2">Configuration</h3>
          <p className="text-sm text-gray-900">
            Multi-AZ: {instance.multi_az ? 'Enabled' : 'Disabled'}
          </p>
          <p className="text-sm text-gray-900">
            Public: {instance.publicly_accessible ? 'Yes' : 'No'}
          </p>
        </div>
      </div>

      {/* Metrics Charts */}
      {chartData.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Performance Metrics</h2>
          <div className="space-y-6">
            <div>
              <h3 className="text-sm font-medium text-gray-600 mb-2">CPU Utilization (%)</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div>
              <h3 className="text-sm font-medium text-gray-600 mb-2">Database Connections</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="connections" stroke="#10b981" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </div>

            <div>
              <h3 className="text-sm font-medium text-gray-600 mb-2">Freeable Memory (GB)</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="memory" stroke="#f59e0b" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      )}

      {/* Active Alerts */}
      {alerts && alerts.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Active Alerts</h2>
          <div className="space-y-3">
            {alerts.map((alert) => (
              <div
                key={alert.alert_id}
                className="flex items-start justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <StatusBadge status={alert.severity} />
                    <span className="text-sm font-medium text-gray-900">
                      {alert.metric_name}
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-gray-600">{alert.message}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Operations */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Self-Service Operations</h2>
        <div className="flex gap-4">
          <select
            value={selectedOperation}
            onChange={(e) => setSelectedOperation(e.target.value)}
            className="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500"
          >
            <option value="">Select an operation...</option>
            <option value="create_snapshot">Create Snapshot</option>
            <option value="reboot">Reboot Instance</option>
            <option value="modify_backup_window">Modify Backup Window</option>
          </select>
          <button
            onClick={handleOperation}
            disabled={!selectedOperation || operationMutation.isPending}
            className="btn-primary"
          >
            {operationMutation.isPending ? 'Executing...' : 'Execute'}
          </button>
        </div>
        <p className="mt-2 text-sm text-gray-600">
          Note: Operations are only available for non-production instances
        </p>
      </div>

      {/* Tags */}
      {instance.tags && Object.keys(instance.tags).length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Tags</h2>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {Object.entries(instance.tags).map(([key, value]) => (
              <div key={key} className="p-3 bg-gray-50 rounded-lg">
                <p className="text-xs font-medium text-gray-600">{key}</p>
                <p className="text-sm text-gray-900">{value}</p>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
