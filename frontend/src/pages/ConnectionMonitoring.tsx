import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useParams, useNavigate } from 'react-router-dom'
import { Users, Activity, AlertTriangle, TrendingUp, ArrowLeft, Clock } from 'lucide-react'
import { api } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, Area, AreaChart } from 'recharts'

export default function ConnectionMonitoring() {
  const { instanceId } = useParams<{ instanceId: string }>()
  const navigate = useNavigate()
  const [timeRange, setTimeRange] = useState<'1h' | '6h' | '24h' | '7d'>('6h')

  const { data: instance, isLoading: instanceLoading } = useQuery({
    queryKey: ['instance', instanceId],
    queryFn: () => api.getInstance(instanceId!),
    enabled: !!instanceId,
  })

  const { data: metrics, isLoading: metricsLoading, refetch } = useQuery({
    queryKey: ['connection-metrics', instanceId, timeRange],
    queryFn: () => api.getHealth(instanceId!),
    enabled: !!instanceId,
    refetchInterval: 30000, // Refresh every 30 seconds
  })

  if (instanceLoading || metricsLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (!instance) {
    return <ErrorMessage message="Instance not found" />
  }

  // Prepare chart data
  const chartData = metrics?.map((m) => ({
    time: new Date(m.timestamp).toLocaleTimeString(),
    connections: m.database_connections,
    cpu: m.cpu_utilization,
  })) || []

  // Calculate connection statistics
  const latestMetric = metrics?.[metrics.length - 1]
  const currentConnections = latestMetric?.database_connections || 0
  const maxConnections = metrics ? Math.max(...metrics.map(m => m.database_connections)) : 0
  const minConnections = metrics ? Math.min(...metrics.map(m => m.database_connections)) : 0
  const avgConnections = metrics ? (metrics.reduce((sum, m) => sum + m.database_connections, 0) / metrics.length).toFixed(0) : 0

  // Estimate max connections based on instance class (simplified)
  const estimatedMaxConnections = 100 // This should be calculated based on instance class
  const connectionUtilization = ((currentConnections / estimatedMaxConnections) * 100).toFixed(1)

  // Determine status
  const getConnectionStatus = () => {
    const utilization = (currentConnections / estimatedMaxConnections) * 100
    if (utilization > 80) return { color: 'text-red-600 bg-red-100', status: 'Critical', message: 'Connection pool near capacity' }
    if (utilization > 60) return { color: 'text-yellow-600 bg-yellow-100', status: 'Warning', message: 'High connection usage' }
    return { color: 'text-green-600 bg-green-100', status: 'Healthy', message: 'Connection pool healthy' }
  }

  const connectionStatus = getConnectionStatus()

  // Calculate connection trends
  const recentMetrics = metrics?.slice(-10) || []
  const trend = recentMetrics.length > 1 
    ? recentMetrics[recentMetrics.length - 1].database_connections - recentMetrics[0].database_connections
    : 0

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate(`/instances/${instanceId}`)}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Connection Monitoring</h1>
            <p className="text-sm text-gray-600 mt-1">
              {instance.instance_id} • {instance.engine}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-4">
          {/* Time Range Selector */}
          <select
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value as any)}
            className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          >
            <option value="1h">Last Hour</option>
            <option value="6h">Last 6 Hours</option>
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
          </select>

          <button
            onClick={() => refetch()}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Connection Status Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Users className="w-5 h-5 text-blue-600" />
              <h3 className="text-sm font-medium text-gray-600">Active Connections</h3>
            </div>
          </div>
          <div className={`text-3xl font-bold ${connectionStatus.color} inline-block px-3 py-1 rounded-lg`}>
            {currentConnections}
          </div>
          <p className="text-sm text-gray-500 mt-2">
            {connectionUtilization}% of capacity
          </p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-green-600" />
              <h3 className="text-sm font-medium text-gray-600">Peak Connections</h3>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {maxConnections}
          </div>
          <p className="text-sm text-gray-500 mt-2">
            Max in time range
          </p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Activity className="w-5 h-5 text-purple-600" />
              <h3 className="text-sm font-medium text-gray-600">Average Connections</h3>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {avgConnections}
          </div>
          <p className="text-sm text-gray-500 mt-2">
            Min: {minConnections}
          </p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Clock className="w-5 h-5 text-orange-600" />
              <h3 className="text-sm font-medium text-gray-600">Trend</h3>
            </div>
          </div>
          <div className={`text-3xl font-bold ${trend > 0 ? 'text-red-600' : trend < 0 ? 'text-green-600' : 'text-gray-600'}`}>
            {trend > 0 ? '+' : ''}{trend}
          </div>
          <p className="text-sm text-gray-500 mt-2">
            Last 10 samples
          </p>
        </div>
      </div>

      {/* Status Alert */}
      {connectionStatus.status !== 'Healthy' && (
        <div className={`p-4 rounded-lg border ${
          connectionStatus.status === 'Critical' 
            ? 'bg-red-50 border-red-200' 
            : 'bg-yellow-50 border-yellow-200'
        }`}>
          <div className="flex items-start gap-2">
            <AlertTriangle className={`w-5 h-5 mt-0.5 ${
              connectionStatus.status === 'Critical' ? 'text-red-600' : 'text-yellow-600'
            }`} />
            <div className={`text-sm ${
              connectionStatus.status === 'Critical' ? 'text-red-800' : 'text-yellow-800'
            }`}>
              <p className="font-medium mb-1">{connectionStatus.status}: {connectionStatus.message}</p>
              <p>Consider scaling your instance or optimizing connection pooling in your application.</p>
            </div>
          </div>
        </div>
      )}

      {/* Connection Trend Chart */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Database Connections Over Time</h2>
        <ResponsiveContainer width="100%" height={350}>
          <AreaChart data={chartData}>
            <defs>
              <linearGradient id="colorConnections" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.8}/>
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="time" />
            <YAxis label={{ value: 'Connections', angle: -90, position: 'insideLeft' }} />
            <Tooltip />
            <Area 
              type="monotone" 
              dataKey="connections" 
              stroke="#3b82f6" 
              fillOpacity={1} 
              fill="url(#colorConnections)" 
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Connection Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Connection Distribution</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={chartData.slice(-20)}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="connections" fill="#3b82f6" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Connections vs CPU Usage</h2>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis yAxisId="left" label={{ value: 'Connections', angle: -90, position: 'insideLeft' }} />
              <YAxis yAxisId="right" orientation="right" label={{ value: 'CPU %', angle: 90, position: 'insideRight' }} />
              <Tooltip />
              <Legend />
              <Line yAxisId="left" type="monotone" dataKey="connections" stroke="#3b82f6" strokeWidth={2} name="Connections" />
              <Line yAxisId="right" type="monotone" dataKey="cpu" stroke="#10b981" strokeWidth={2} name="CPU %" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Connection Pool Information */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Connection Pool Information</h2>
        <div className="space-y-4">
          <div>
            <div className="flex justify-between items-center mb-2">
              <span className="text-sm font-medium text-gray-600">Current Utilization</span>
              <span className="text-sm font-semibold text-gray-900">{connectionUtilization}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-4">
              <div 
                className={`h-4 rounded-full transition-all ${
                  parseFloat(connectionUtilization) > 80 ? 'bg-red-600' :
                  parseFloat(connectionUtilization) > 60 ? 'bg-yellow-500' :
                  'bg-green-500'
                }`}
                style={{ width: `${connectionUtilization}%` }}
              />
            </div>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t">
            <div>
              <p className="text-sm text-gray-600">Current</p>
              <p className="text-2xl font-bold text-gray-900">{currentConnections}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600">Average</p>
              <p className="text-2xl font-bold text-gray-900">{avgConnections}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600">Peak</p>
              <p className="text-2xl font-bold text-gray-900">{maxConnections}</p>
            </div>
            <div>
              <p className="text-sm text-gray-600">Estimated Max</p>
              <p className="text-2xl font-bold text-gray-900">{estimatedMaxConnections}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Recommendations */}
      <div className="card bg-blue-50 border border-blue-200">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Optimization Recommendations</h2>
        <div className="space-y-3 text-sm text-gray-700">
          {parseFloat(connectionUtilization) > 70 && (
            <div className="flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 text-blue-600 mt-0.5" />
              <p>
                <strong>High connection usage detected.</strong> Consider implementing connection pooling in your application
                or scaling to a larger instance class.
              </p>
            </div>
          )}
          <div className="flex items-start gap-2">
            <Activity className="w-4 h-4 text-blue-600 mt-0.5" />
            <p>
              <strong>Connection pooling:</strong> Use connection pooling libraries like PgBouncer (PostgreSQL) or 
              ProxySQL (MySQL) to reduce connection overhead.
            </p>
          </div>
          <div className="flex items-start gap-2">
            <Users className="w-4 h-4 text-blue-600 mt-0.5" />
            <p>
              <strong>Monitor idle connections:</strong> Set appropriate timeout values for idle connections to free up resources.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
