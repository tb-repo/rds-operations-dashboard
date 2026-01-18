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
  // Discovery and refresh with better error handling
  const { 
    data: instances, 
    isLoading: instancesLoading, 
    error: instancesError,
    refetch: refetchInstances 
  } = useQuery({
    queryKey: ['instances'],
    queryFn: () => api.getInstances(),
    retry: 3, // Retry failed requests up to 3 times
    retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000), // Exponential backoff
    staleTime: 30000, // Consider data stale after 30 seconds
    refetchInterval: 60000, // Auto-refresh every 60 seconds
    refetchIntervalInBackground: false, // Don't refresh when tab is not active
  })

  const { 
    data: alerts, 
    isLoading: alertsLoading,
    refetch: refetchAlerts 
  } = useQuery({
    queryKey: ['alerts'],
    queryFn: () => api.getAlerts(),
    retry: 2,
    retryDelay: 1000,
    staleTime: 60000, // Alerts can be stale for longer
  })

  const { 
    data: costs, 
    isLoading: costsLoading,
    refetch: refetchCosts 
  } = useQuery({
    queryKey: ['costs'],
    queryFn: () => api.getCosts(),
    retry: 2,
    retryDelay: 1000,
    staleTime: 300000, // Cost data can be stale for 5 minutes
  })

  const { 
    data: compliance, 
    isLoading: complianceLoading,
    refetch: refetchCompliance 
  } = useQuery({
    queryKey: ['compliance'],
    queryFn: () => api.getCompliance(),
    retry: 2,
    retryDelay: 1000,
    staleTime: 300000, // Compliance data can be stale for 5 minutes
  })

  const handleRefreshAll = async () => {
    try {
      console.log('Refreshing all dashboard data...')
      
      // Show loading state
      const refreshPromises = [
        refetchInstances(),
        refetchAlerts(),
        refetchCosts(),
        refetchCompliance()
      ]
      
      await Promise.all(refreshPromises)
      
      console.log('Dashboard data refreshed successfully')
      
      // Optional: Show success message briefly
      // You could add a toast notification here
      
    } catch (error) {
      console.error('Failed to refresh dashboard data:', error)
      alert(`Failed to refresh dashboard data. 
      
Error: ${error instanceof Error ? error.message : 'Unknown error'}

Please try again or contact support if the issue persists.`)
    }
  }

  if (instancesLoading || alertsLoading || costsLoading || complianceLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px] space-y-4">
        <LoadingSpinner size="lg" />
        <div className="text-center">
          <p className="text-gray-600">Loading dashboard data...</p>
          <p className="text-sm text-gray-500 mt-1">
            Fetching instances, alerts, costs, and compliance data
          </p>
        </div>
      </div>
    )
  }

  if (instancesError) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px] space-y-4">
        <AlertTriangle className="w-12 h-12 text-red-500" />
        <div className="text-center">
          <h2 className="text-lg font-semibold text-gray-900 mb-2">
            Failed to Load Dashboard Data
          </h2>
          <p className="text-gray-600 mb-4">
            Unable to fetch instance data from the backend API.
          </p>
          <ErrorMessage 
            message="Dashboard data unavailable" 
            error={instancesError}
            onRetry={handleRefreshAll}
          />
          <div className="mt-4 text-sm text-gray-500">
            <p>Possible causes:</p>
            <ul className="list-disc list-inside mt-1 space-y-1">
              <li>Backend API is unavailable</li>
              <li>Authentication token has expired</li>
              <li>Network connectivity issues</li>
              <li>Discovery system needs configuration</li>
            </ul>
          </div>
        </div>
      </div>
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
      
      // Show more informative message
      alert(`Discovery triggered successfully! 
      
Current status: ${totalInstances} instance(s) found
Expected: 3 instances across multiple regions

The system will scan all configured accounts and regions. 
Please wait 30-60 seconds and click Refresh to see updated results.`)
      
      // Refresh instances after a longer delay to allow discovery to complete
      setTimeout(() => {
        refetchInstances()
      }, 10000) // Increased to 10 seconds
    } catch (error) {
      console.error('Failed to trigger discovery:', error)
      alert(`Failed to trigger discovery. 
      
Error: ${error instanceof Error ? error.message : 'Unknown error'}

Please check:
1. Your permissions include 'trigger_discovery'
2. The discovery system is properly configured
3. Cross-account roles are set up correctly

Contact your administrator if the issue persists.`)
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
          {/* Refresh Button with loading state */}
          <button
            onClick={handleRefreshAll}
            disabled={instancesLoading || alertsLoading || costsLoading || complianceLoading}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-colors ${
              instancesLoading || alertsLoading || costsLoading || complianceLoading
                ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
            }`}
            title="Refresh all dashboard data"
          >
            <RefreshCw className={`w-4 h-4 ${
              instancesLoading || alertsLoading || costsLoading || complianceLoading 
                ? 'animate-spin' 
                : ''
            }`} />
            {instancesLoading || alertsLoading || costsLoading || complianceLoading 
              ? 'Refreshing...' 
              : 'Refresh'
            }
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

      {/* Instance Discovery Status Warning */}
      {totalInstances < 3 && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
          <div className="flex items-start">
            <AlertTriangle className="w-5 h-5 text-yellow-600 mt-0.5 mr-3 flex-shrink-0" />
            <div className="flex-1">
              <h3 className="text-sm font-medium text-yellow-800">
                Incomplete Instance Discovery
              </h3>
              <p className="mt-1 text-sm text-yellow-700">
                Currently showing {totalInstances} instance(s), but 3 instances are expected across multiple regions.
                The discovery system may need to be configured for cross-account access or additional regions.
              </p>
              <div className="mt-3">
                <PermissionGuard permission="trigger_discovery">
                  <button
                    onClick={handleTriggerDiscovery}
                    className="text-sm bg-yellow-100 text-yellow-800 px-3 py-1 rounded hover:bg-yellow-200 transition-colors"
                  >
                    Trigger Full Discovery
                  </button>
                </PermissionGuard>
              </div>
            </div>
          </div>
        </div>
      )}

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
