import { useQuery } from '@tanstack/react-query'
import { Database, AlertTriangle, DollarSign, Shield, RefreshCw } from 'lucide-react'
import { api } from '@/lib/api'
import { useAuth } from '@/lib/auth/AuthContext'
import PermissionGuard from '@/components/PermissionGuard'
import StatCard from '@/components/StatCard'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import StatusBadge from '@/components/StatusBadge'
import ErrorResolutionWidget from '@/components/ErrorResolutionWidget'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts'

export default function Dashboard() {
  const { user } = useAuth()
  const { 
    data: instances, 
    isLoading: instancesLoading, 
    error: instancesError,
    refetch: refetchInstances 
  } = useQuery({
    queryKey: ['instances'],
    queryFn: () => api.getInstances(),
  })

  const { 
    data: alerts, 
    isLoading: alertsLoading,
    refetch: refetchAlerts 
  } = useQuery({
    queryKey: ['alerts'],
    queryFn: () => api.getAlerts(),
  })

  const { 
    data: costs, 
    isLoading: costsLoading,
    refetch: refetchCosts 
  } = useQuery({
    queryKey: ['costs'],
    queryFn: () => api.getCosts(),
  })

  const { 
    data: compliance, 
    isLoading: complianceLoading,
    refetch: refetchCompliance 
  } = useQuery({
    queryKey: ['compliance'],
    queryFn: () => api.getCompliance(),
  })

  const handleRefreshAll = () => {
    refetchInstances()
    refetchAlerts()
    refetchCosts()
    refetchCompliance()
  }

  if (instancesLoading || alertsLoading || costsLoading || complianceLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (instancesError) {
    return (
      <ErrorMessage 
        message="Failed to load dashboard data" 
        error={instancesError}
        onRetry={handleRefreshAll}
      />
    )
  }

  // Calculate stats
  const totalInstances = instances?.length || 0
  const activeAlerts = Array.isArray(alerts) ? alerts.filter(a => !a.resolved).length : 0
  const totalMonthlyCost = Array.isArray(costs) ? costs.reduce((sum, c) => sum + c.monthly_cost, 0) : 0
  const complianceIssues = Array.isArray(compliance) ? compliance.filter(c => c.status === 'non_compliant').length : 0

  // Engine distribution
  const engineCounts = instances?.reduce((acc, inst) => {
    acc[inst.engine] = (acc[inst.engine] || 0) + 1
    return acc
  }, {} as Record<string, number>) || {}

  const engineData = Object.entries(engineCounts).map(([name, value]) => ({
    name,
    value,
  }))

  // Region distribution
  const regionCounts = instances?.reduce((acc, inst) => {
    acc[inst.region] = (acc[inst.region] || 0) + 1
    return acc
  }, {} as Record<string, number>) || {}

  const regionData = Object.entries(regionCounts).map(([name, value]) => ({
    name,
    value,
  }))

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899']

  const handleTriggerDiscovery = async () => {
    try {
      console.log('Triggering discovery...')
      const result = await api.triggerDiscovery()
      console.log('Discovery triggered successfully:', result)
      alert('Discovery triggered successfully! Instances will be refreshed shortly.')
      // Refresh instances after a short delay to allow discovery to complete
      setTimeout(() => {
        refetchInstances()
      }, 5000)
    } catch (error) {
      console.error('Failed to trigger discovery:', error)
      alert('Failed to trigger discovery. Please check your permissions and try again.')
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Dashboard Overview</h1>
          {user && (
            <p className="text-sm text-gray-600 mt-1">
              Welcome back, {user.email} ({user.groups.join(', ')})
            </p>
          )}
        </div>
        
        <div className="flex items-center gap-3">
          {/* Refresh Button */}
          <button
            onClick={handleRefreshAll}
            className="flex items-center gap-2 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors"
            title="Refresh dashboard data"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
          
          {/* Trigger Discovery Button - Only for users with trigger_discovery permission */}
          <PermissionGuard permission="trigger_discovery">
            <button
              onClick={handleTriggerDiscovery}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              <RefreshCw className="w-4 h-4" />
              Trigger Discovery
            </button>
          </PermissionGuard>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Total Instances"
          value={totalInstances}
          icon={Database}
          color="blue"
        />
        <StatCard
          title="Active Alerts"
          value={activeAlerts}
          icon={AlertTriangle}
          color={activeAlerts > 0 ? 'red' : 'green'}
        />
        <StatCard
          title="Monthly Cost"
          value={`$${totalMonthlyCost.toFixed(2)}`}
          icon={DollarSign}
          color="green"
        />
        <StatCard
          title="Compliance Issues"
          value={complianceIssues}
          icon={Shield}
          color={complianceIssues > 0 ? 'yellow' : 'green'}
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Engine Distribution */}
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Instances by Engine</h2>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={engineData}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="value"
              >
                {engineData.map((_entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Region Distribution */}
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Instances by Region</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={regionData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="name" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="value" fill="#3b82f6" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Error Resolution Widget */}
      <PermissionGuard permission="view_metrics">
        <ErrorResolutionWidget />
      </PermissionGuard>

      {/* Recent Alerts */}
      {alerts && alerts.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Recent Alerts</h2>
          <div className="space-y-3">
            {alerts.slice(0, 5).map((alert) => (
              <div
                key={alert.alert_id}
                className="flex items-start justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <StatusBadge status={alert.severity} />
                    <span className="text-sm font-medium text-gray-900">
                      {alert.instance_id}
                    </span>
                  </div>
                  <p className="mt-1 text-sm text-gray-600">{alert.message}</p>
                </div>
                <span className="text-xs text-gray-500">
                  {new Date(alert.created_at).toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
