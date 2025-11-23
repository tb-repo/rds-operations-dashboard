import { useQuery } from '@tanstack/react-query'
import { Shield, AlertTriangle, CheckCircle, XCircle } from 'lucide-react'
import { api } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
import ErrorMessage from '@/components/ErrorMessage'
import StatCard from '@/components/StatCard'
import StatusBadge from '@/components/StatusBadge'

export default function ComplianceDashboard() {
  const { data: compliance, isLoading, error, refetch } = useQuery({
    queryKey: ['compliance'],
    queryFn: () => api.getCompliance(),
  })

  if (isLoading) {
    return <LoadingSpinner size="lg" />
  }

  if (error) {
    return <ErrorMessage message="Failed to load compliance data" onRetry={() => refetch()} />
  }

  // Calculate stats
  const totalChecks = compliance?.length || 0
  const compliantChecks = compliance?.filter(c => c.status === 'compliant').length || 0
  // const nonCompliantChecks = compliance?.filter(c => c.status === 'non_compliant').length || 0
  const complianceRate = totalChecks > 0 ? ((compliantChecks / totalChecks) * 100).toFixed(1) : '100'

  // Group by severity
  const criticalIssues = compliance?.filter(
    c => c.status === 'non_compliant' && c.severity === 'Critical'
  ).length || 0
  const highIssues = compliance?.filter(
    c => c.status === 'non_compliant' && c.severity === 'High'
  ).length || 0
  const mediumIssues = compliance?.filter(
    c => c.status === 'non_compliant' && c.severity === 'Medium'
  ).length || 0

  // Group by instance
  const instanceViolations = compliance?.reduce((acc, check) => {
    if (check.status === 'non_compliant') {
      if (!acc[check.instance_id]) {
        acc[check.instance_id] = []
      }
      acc[check.instance_id].push(check)
    }
    return acc
  }, {} as Record<string, typeof compliance>) || {}

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Compliance Dashboard</h1>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard
          title="Compliance Rate"
          value={`${complianceRate}%`}
          icon={Shield}
          color={parseFloat(complianceRate) >= 90 ? 'green' : 'yellow'}
        />
        <StatCard
          title="Critical Issues"
          value={criticalIssues}
          icon={XCircle}
          color={criticalIssues > 0 ? 'red' : 'green'}
        />
        <StatCard
          title="High Priority"
          value={highIssues}
          icon={AlertTriangle}
          color={highIssues > 0 ? 'yellow' : 'green'}
        />
        <StatCard
          title="Compliant Checks"
          value={compliantChecks}
          icon={CheckCircle}
          color="green"
        />
      </div>

      {/* Severity Summary */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Issues by Severity</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-red-600">Critical</p>
                <p className="text-2xl font-bold text-red-900">{criticalIssues}</p>
              </div>
              <XCircle className="h-8 w-8 text-red-600" />
            </div>
          </div>
          <div className="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-yellow-600">High</p>
                <p className="text-2xl font-bold text-yellow-900">{highIssues}</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-yellow-600" />
            </div>
          </div>
          <div className="p-4 bg-orange-50 border border-orange-200 rounded-lg">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-orange-600">Medium</p>
                <p className="text-2xl font-bold text-orange-900">{mediumIssues}</p>
              </div>
              <AlertTriangle className="h-8 w-8 text-orange-600" />
            </div>
          </div>
        </div>
      </div>

      {/* Violations by Instance */}
      {Object.keys(instanceViolations).length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">
            Non-Compliant Instances
          </h2>
          <div className="space-y-4">
            {Object.entries(instanceViolations).map(([instanceId, checks]) => (
              <div
                key={instanceId}
                className="p-4 bg-gray-50 border border-gray-200 rounded-lg"
              >
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold text-gray-900">{instanceId}</h3>
                  <span className="badge badge-error">
                    {checks.length} violation{checks.length > 1 ? 's' : ''}
                  </span>
                </div>
                <div className="space-y-3">
                  {checks.map((check, index) => (
                    <div
                      key={index}
                      className="p-3 bg-white border border-gray-200 rounded-md"
                    >
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <StatusBadge status={check.severity} />
                            <span className="text-sm font-medium text-gray-900">
                              {check.check_name}
                            </span>
                          </div>
                          <p className="mt-1 text-sm text-gray-600">{check.message}</p>
                          <div className="mt-2 p-2 bg-blue-50 border border-blue-200 rounded">
                            <p className="text-xs font-medium text-blue-900">Remediation:</p>
                            <p className="text-xs text-blue-800">{check.remediation}</p>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* All Compliance Checks */}
      <div className="card">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">All Compliance Checks</h2>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Instance ID
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Check Name
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Severity
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Message
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Checked At
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {compliance?.map((check, index) => (
                <tr key={index} className={check.status === 'non_compliant' ? 'bg-red-50' : ''}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {check.instance_id}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    {check.check_name}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <StatusBadge status={check.status} />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <StatusBadge status={check.severity} />
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-600 max-w-md">
                    {check.message}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    {new Date(check.checked_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {compliance && compliance.length === 0 && (
        <div className="text-center py-12">
          <Shield className="mx-auto h-12 w-12 text-gray-400" />
          <p className="mt-2 text-gray-500">No compliance checks found</p>
        </div>
      )}
    </div>
  )
}
