interface StatusBadgeProps {
  status: string
}

export default function StatusBadge({ status }: StatusBadgeProps) {
  const getStatusColor = (status: string) => {
    const normalized = status.toLowerCase()
    if (normalized === 'available' || normalized === 'healthy' || normalized === 'compliant') {
      return 'badge-success'
    }
    if (normalized === 'warning' || normalized === 'backing-up' || normalized === 'modifying') {
      return 'badge-warning'
    }
    if (normalized === 'critical' || normalized === 'failed' || normalized === 'non_compliant') {
      return 'badge-error'
    }
    return 'badge-info'
  }

  return (
    <span className={`badge ${getStatusColor(status)}`}>
      {status}
    </span>
  )
}
