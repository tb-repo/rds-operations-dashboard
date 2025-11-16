import { useQuery } from '@tanstack/react-query'
import { DollarSign, TrendingDown, TrendingUp } from 'lucide-react'
import { api } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import StatCard from '@/components/StatCard'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, PieChart, Pie, Cell } from 'recharts'

export default function CostDashboard() {
  const { data: costs, isLoading: costsLoading, error: costsError } = useQuery({
    queryKey: ['costs'],
    queryFn: () => api.getCosts(),
  })

  const { data: recommendations, isLoading: recsLoading } = useQuery({
    queryKey: ['recommendations'],
    queryFn: () => api.getRecommendations(),
  })

  if (costsLoading || recsLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (costsError) {
    return <ErrorMessage message="Failed to load cost data" />
  }

  // Calculate totals
  const totalMonthlyCost = costs?.reduce((sum, c) => sum + c.monthly_cost, 0) || 0
  const totalComputeCost = costs?.reduce((sum, c) => sum + c.compute_cost, 0) || 0
  const totalStorageCost = costs?.reduce((sum, c) => sum + c.storage_cost, 0) || 0
  const totalSavings = recommendations?.reduce((sum, r) => sum + r.estimated_savings, 0) || 0

  // Cost by account
  const accountCosts = costs?.reduce((acc, cost) => {
    acc[cost.account_id] = (acc[cost.account_id] || 0) + cost.monthly_cost
    return acc
  }, {} as Record<string, number>) || {}

  const accountData = Object.entries(accountCosts).map(([name, value]) => ({
    name,
    value: parseFloat(value.toFixed(2)),
  }))

  // Cost by region
  const regionCosts = costs?.reduce((acc, cost) => {
    acc[cost.region] = (acc[cost.region] || 0) + cost.monthly_cost
    return acc
  }, {} as Record<string, number>) || {}

  const regionData = Object.entries(regionCosts).map(([name, value]) => ({
    name,
    value: parseFloat(value.toFixed(2)),
  }))

  // Cost breakdown
  const costBreakdown = [
    { name: 'Compute', value: totalComputeCost },
    { name: 'Storage', value: totalStorageCost },
    { name: 'Backup', value: costs?.reduce((sum, c) => sum + c.backup_cost, 0) || 0 },
  ]

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b']

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Cost Analysis</h1>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Total Monthly Cost"
          value={`$${totalMonthlyCost.toFixed(2)}`}
          icon={DollarSign}
          color="blue"
        />
        <StatCard
          title="Compute Cost"
          value={`$${totalComputeCost.toFixed(2)}`}
          icon={DollarSign}
          color="green"
        />
        <StatCard
          title="Storage Cost"
          value={`$${totalStorageCost.toFixed(2)}`}
          icon={DollarSign}
          color="yellow"
        />
        <StatCard
          title="Potential Savings"
          value={`$${totalSavings.toFixed(2)}`}
          icon={TrendingDown}
          color="green"
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Cost by Account */}
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Cost by Account</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={accountData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="name" />
              <YAxis />
              <Tooltip formatter={(value) => `$${value}`} />
              <Bar dataKey="value" fill="#3b82f6" />
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Cost Breakdown */}
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Cost Breakdown</h2>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={costBreakdown}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="value"
              >
                {costBreakdown.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip formatter={(value) => `$${value}`} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Cost by Region */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Cost by Region</h2>
        <ResponsiveContainer width="100%" height={300}>
          <BarChart data={regionData}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis />
            <Tooltip formatter={(value) => `$${value}`} />
            <Legend />
            <Bar dataKey="value" fill="#10b981" name="Monthly Cost" />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Optimization Recommendations */}
      {recommendations && recommendations.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">
            Optimization Recommendations
          </h2>
          <div className="space-y-4">
            {recommendations.map((rec, index) => (
              <div
                key={index}
                className="p-4 bg-green-50 border border-green-200 rounded-lg"
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <TrendingDown className="h-5 w-5 text-green-600" />
                      <h3 className="text-sm font-semibold text-gray-900">
                        {rec.instance_id}
                      </h3>
                      <span className="badge badge-success">
                        Save ${rec.estimated_savings.toFixed(2)}/month
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-gray-700">{rec.reason}</p>
                    <div className="mt-2 grid grid-cols-2 gap-4">
                      <div>
                        <p className="text-xs text-gray-600">Current</p>
                        <p className="text-sm font-medium text-gray-900">
                          {rec.current_config}
                        </p>
                      </div>
                      <div>
                        <p className="text-xs text-gray-600">Recommended</p>
                        <p className="text-sm font-medium text-green-700">
                          {rec.recommended_config}
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Top 10 Most Expensive Instances */}
      {costs && costs.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">
            Top 10 Most Expensive Instances
          </h2>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Instance ID
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Region
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Monthly Cost
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {costs
                  .sort((a, b) => b.monthly_cost - a.monthly_cost)
                  .slice(0, 10)
                  .map((cost) => (
                    <tr key={cost.instance_id}>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        {cost.instance_id}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                        {cost.account_id}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                        {cost.region}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-right font-semibold text-gray-900">
                        ${cost.monthly_cost.toFixed(2)}
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}
