import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useParams, useNavigate } from 'react-router-dom'
import { Cpu, HardDrive, Activity, TrendingUp, AlertCircle, ArrowLeft } from 'lucide-react'
import { api } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import { LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts'

export default function ComputeMonitoring() {
  const { instanceId } = useParams<{ instanceId: string }>()
  const navigate = useNavigate()
  const [timeRange, setTimeRange] = useState<'1h' | '6h' | '24h' | '7d'>('6h')

  const { data: instance, isLoading: instanceLoading } = useQuery({
    queryKey: ['instance', instanceId],
    queryFn: () => api.getInstance(instanceId!),
    enabled: !!instanceId,
  })

  const { data: metrics, isLoading: metricsLoading, refetch } = useQuery({
    queryKey: ['compute-metrics', instanceId, timeRange],
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
    cpu: m.cpu_utilization,
    memory: ((m.freeable_memory / (1024 * 1024 * 1024))).toFixed(2),
    readLatency: m.read_latency,
    writeLatency: m.write_latency,
    freeStorage: (m.free_storage_space / (1024 * 1024 * 1024)).toFixed(2),
  })) || []

  // Calculate current values (latest metric)
  const latestMetric = metrics?.[metrics.length - 1]
  const currentCPU = latestMetric?.cpu_utilization || 0
  const currentMemory = latestMetric ? (latestMetric.freeable_memory / (1024 * 1024 * 1024)).toFixed(2) : 0
  const currentReadLatency = latestMetric?.read_latency || 0
  // const currentWriteLatency = latestMetric?.write_latency || 0 // Unused
  const currentFreeStorage = latestMetric ? (latestMetric.free_storage_space / (1024 * 1024 * 1024)).toFixed(2) : 0

  // Calculate averages
  const avgCPU = metrics ? (metrics.reduce((sum, m) => sum + m.cpu_utilization, 0) / metrics.length).toFixed(2) : 0
  const avgReadLatency = metrics ? (metrics.reduce((sum, m) => sum + m.read_latency, 0) / metrics.length).toFixed(2) : 0
  const avgWriteLatency = metrics ? (metrics.reduce((sum, m) => sum + m.write_latency, 0) / metrics.length).toFixed(2) : 0

  // Determine status colors
  const getCPUColor = (cpu: number) => {
    if (cpu > 80) return 'text-red-600 bg-red-100'
    if (cpu > 60) return 'text-yellow-600 bg-yellow-100'
    return 'text-green-600 bg-green-100'
  }

  const getLatencyColor = (latency: number) => {
    if (latency > 10) return 'text-red-600 bg-red-100'
    if (latency > 5) return 'text-yellow-600 bg-yellow-100'
    return 'text-green-600 bg-green-100'
  }

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
            <h1 className="text-2xl font-bold text-gray-900">Compute Monitoring</h1>
            <p className="text-sm text-gray-600 mt-1">
              {instance.instance_id} • {instance.instance_class}
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

      {/* Current Metrics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Cpu className="w-5 h-5 text-blue-600" />
              <h3 className="text-sm font-medium text-gray-600">CPU Utilization</h3>
            </div>
          </div>
          <div className={`text-3xl font-bold ${getCPUColor(currentCPU)} inline-block px-3 py-1 rounded-lg`}>
            {currentCPU.toFixed(1)}%
          </div>
          <p className="text-sm text-gray-500 mt-2">Avg: {avgCPU}%</p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <Activity className="w-5 h-5 text-green-600" />
              <h3 className="text-sm font-medium text-gray-600">Free Memory</h3>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {currentMemory} GB
          </div>
          <p className="text-sm text-gray-500 mt-2">Available RAM</p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-purple-600" />
              <h3 className="text-sm font-medium text-gray-600">Read Latency</h3>
            </div>
          </div>
          <div className={`text-3xl font-bold ${getLatencyColor(currentReadLatency)} inline-block px-3 py-1 rounded-lg`}>
            {currentReadLatency.toFixed(2)} ms
          </div>
          <p className="text-sm text-gray-500 mt-2">Avg: {avgReadLatency} ms</p>
        </div>

        <div className="card">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-2">
              <HardDrive className="w-5 h-5 text-orange-600" />
              <h3 className="text-sm font-medium text-gray-600">Free Storage</h3>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">
            {currentFreeStorage} GB
          </div>
          <p className="text-sm text-gray-500 mt-2">Available space</p>
        </div>
      </div>

      {/* CPU Utilization Chart */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">CPU Utilization Over Time</h2>
        <ResponsiveContainer width="100%" height={300}>
          <AreaChart data={chartData}>
            <defs>
              <linearGradient id="colorCpu" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.8}/>
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="time" />
            <YAxis label={{ value: 'CPU %', angle: -90, position: 'insideLeft' }} />
            <Tooltip />
            <Area type="monotone" dataKey="cpu" stroke="#3b82f6" fillOpacity={1} fill="url(#colorCpu)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {/* Memory and Storage */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Free Memory (GB)</h2>
          <ResponsiveContainer width="100%" height={250}>
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Line type="monotone" dataKey="memory" stroke="#10b981" strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Free Storage (GB)</h2>
          <ResponsiveContainer width="100%" height={250}>
            <LineChart data={chartData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Line type="monotone" dataKey="freeStorage" stroke="#f59e0b" strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Disk I/O Latency */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Disk I/O Latency (ms)</h2>
        <ResponsiveContainer width="100%" height={300}>
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="time" />
            <YAxis label={{ value: 'Latency (ms)', angle: -90, position: 'insideLeft' }} />
            <Tooltip />
            <Legend />
            <Line type="monotone" dataKey="readLatency" stroke="#8b5cf6" strokeWidth={2} name="Read Latency" />
            <Line type="monotone" dataKey="writeLatency" stroke="#ec4899" strokeWidth={2} name="Write Latency" />
          </LineChart>
        </ResponsiveContainer>
        <div className="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <div className="flex items-start gap-2">
            <AlertCircle className="w-5 h-5 text-blue-600 mt-0.5" />
            <div className="text-sm text-blue-800">
              <p className="font-medium mb-1">Performance Insights</p>
              <p>Average Write Latency: {avgWriteLatency} ms</p>
              <p>Current status: {currentCPU > 80 ? 'High CPU usage detected' : 'Performance is normal'}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Instance Details */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Instance Configuration</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <p className="text-sm text-gray-600">Instance Class</p>
            <p className="text-lg font-semibold text-gray-900">{instance.instance_class}</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Engine</p>
            <p className="text-lg font-semibold text-gray-900">{instance.engine} {instance.engine_version}</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Storage</p>
            <p className="text-lg font-semibold text-gray-900">{instance.allocated_storage} GB ({instance.storage_type})</p>
          </div>
          <div>
            <p className="text-sm text-gray-600">Multi-AZ</p>
            <p className="text-lg font-semibold text-gray-900">{instance.multi_az ? 'Enabled' : 'Disabled'}</p>
          </div>
        </div>
      </div>
    </div>
  )
}
