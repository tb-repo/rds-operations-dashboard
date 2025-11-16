import { useQuery } from '@tanstack/react-query'
import { Database, AlertTriangle, DollarSign, Shield } from 'lucide-react'
import { api } from '@/lib/api'
import StatCard from '@/components/StatCard'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import StatusBadge from '@/components/StatusBadge'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts'

export default function Dashboard() {
  const { data: instances, isLoading: instancesLoading, error: instancesError } = useQuery({
    queryKey: ['instances'],
    queryFn: () => api.getInstances(),
  })

  const { data: alerts, isLoading: alertsLoading } = useQuery({
    queryKey: ['alerts'],
    queryFn: () => api.getAlerts(),
  })

  const { data: costs, isLoading: costsLoading } = useQuery({
    queryKey: ['costs'],
    queryFn: () => api.getCosts(),
  })

  const { data: compliance, isLoading: complianceLoading } = useQuery({
    queryKey: ['compliance'],
    queryFn: () => api.getCompliance(),
  })

  if (instancesLoading || alertsLoading || costsLoading || complianceLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (instancesError) {
    return <ErrorMessage message="Failed to load dashboard data" />
  }

  // Calculate stats
  const totalInstances = instances?.length || 0
  const activeAlerts = alerts?.filter(a => !a.resolved).length || 0
  const totalMonthlyCost = costs?.reduce((sum, c) => sum + c.monthly_cost, 0) || 0
  const complianceIssues = compliance?.filter(c => c.status === 'non_compliant').length || 0

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

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Dashboard Overview</h1>

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
                {engineData.map((entry, index) => (
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
