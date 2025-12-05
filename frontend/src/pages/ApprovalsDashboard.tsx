import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { 
  CheckCircle, 
  XCircle, 
  Clock, 
  AlertTriangle,
  ThumbsUp,
  ThumbsDown,
  MessageSquare,
  User,
  Calendar,
  DollarSign,
  Shield
} from 'lucide-react'
import { apiClient } from '@/lib/api'
import LoadingSpinner from '@/components/LoadingSpinner'
// import ErrorMessage from '@/components/ErrorMessage' // Unused
import { useAuth } from '@/lib/auth/AuthContext'

interface ApprovalRequest {
  request_id: string
  operation_type: string
  instance_id: string
  parameters: Record<string, any>
  requested_by: string
  requested_at: string
  risk_level: 'low' | 'medium' | 'high'
  environment: string
  justification: string
  estimated_cost?: number
  estimated_duration?: string
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'executed' | 'cancelled'
  approvals_required: number
  approvals_received: number
  approved_by: string[]
  approved_at?: string
  rejected_by?: string
  rejected_at?: string
  rejection_reason?: string
  expires_at: string
  executed_at?: string
  comments: Array<{
    user: string
    timestamp: string
    action: string
    comment: string
  }>
}

export default function ApprovalsDashboard() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const [selectedTab, setSelectedTab] = useState<'pending' | 'my-requests' | 'all'>('pending')
  const [selectedRequest, setSelectedRequest] = useState<ApprovalRequest | null>(null)
  const [showApproveModal, setShowApproveModal] = useState(false)
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [comments, setComments] = useState('')
  const [rejectionReason, setRejectionReason] = useState('')

  // Fetch pending approvals
  const { data: pendingApprovals, isLoading: pendingLoading } = useQuery({
    queryKey: ['pending-approvals'],
    queryFn: async () => {
      const response = await apiClient.post('/approvals', {
        operation: 'get_pending_approvals',
        user_email: user?.email
      })
      return response.data as ApprovalRequest[]
    },
    refetchInterval: 30000, // Refresh every 30 seconds
  })

  // Fetch user's requests
  const { data: myRequests, isLoading: myRequestsLoading } = useQuery({
    queryKey: ['my-requests'],
    queryFn: async () => {
      const response = await apiClient.post('/approvals', {
        operation: 'get_user_requests',
        user_email: user?.email
      })
      return response.data as ApprovalRequest[]
    },
    refetchInterval: 30000,
  })

  // Approve mutation
  const approveMutation = useMutation({
    mutationFn: async ({ requestId, comments }: { requestId: string; comments?: string }) => {
      const response = await apiClient.post('/approvals', {
        operation: 'approve_request',
        request_id: requestId,
        approved_by: user?.email,
        comments
      })
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-approvals'] })
      queryClient.invalidateQueries({ queryKey: ['my-requests'] })
      setShowApproveModal(false)
      setSelectedRequest(null)
      setComments('')
    },
  })

  // Reject mutation
  const rejectMutation = useMutation({
    mutationFn: async ({ requestId, reason }: { requestId: string; reason: string }) => {
      const response = await apiClient.post('/approvals', {
        operation: 'reject_request',
        request_id: requestId,
        rejected_by: user?.email,
        reason
      })
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pending-approvals'] })
      queryClient.invalidateQueries({ queryKey: ['my-requests'] })
      setShowRejectModal(false)
      setSelectedRequest(null)
      setRejectionReason('')
    },
  })

  // Cancel mutation
  const cancelMutation = useMutation({
    mutationFn: async (requestId: string) => {
      const response = await apiClient.post('/approvals', {
        operation: 'cancel_request',
        request_id: requestId,
        cancelled_by: user?.email
      })
      return response.data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['my-requests'] })
      setSelectedRequest(null)
    },
  })

  const handleApprove = (request: ApprovalRequest) => {
    setSelectedRequest(request)
    setShowApproveModal(true)
  }

  const handleReject = (request: ApprovalRequest) => {
    setSelectedRequest(request)
    setShowRejectModal(true)
  }

  const handleCancel = (request: ApprovalRequest) => {
    if (confirm('Are you sure you want to cancel this request?')) {
      cancelMutation.mutate(request.request_id)
    }
  }

  const confirmApprove = () => {
    if (selectedRequest) {
      approveMutation.mutate({
        requestId: selectedRequest.request_id,
        comments: comments || undefined
      })
    }
  }

  const confirmReject = () => {
    if (selectedRequest && rejectionReason.trim()) {
      rejectMutation.mutate({
        requestId: selectedRequest.request_id,
        reason: rejectionReason
      })
    }
  }

  const getRiskLevelColor = (level: string) => {
    switch (level) {
      case 'low': return 'text-green-600 bg-green-100'
      case 'medium': return 'text-yellow-600 bg-yellow-100'
      case 'high': return 'text-red-600 bg-red-100'
      default: return 'text-gray-600 bg-gray-100'
    }
  }

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending': return 'text-yellow-600 bg-yellow-100'
      case 'approved': return 'text-green-600 bg-green-100'
      case 'rejected': return 'text-red-600 bg-red-100'
      case 'expired': return 'text-gray-600 bg-gray-100'
      case 'executed': return 'text-blue-600 bg-blue-100'
      case 'cancelled': return 'text-gray-600 bg-gray-100'
      default: return 'text-gray-600 bg-gray-100'
    }
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString()
  }

  const isExpiringSoon = (expiresAt: string) => {
    const expiryDate = new Date(expiresAt)
    const now = new Date()
    const hoursUntilExpiry = (expiryDate.getTime() - now.getTime()) / (1000 * 60 * 60)
    return hoursUntilExpiry < 24 && hoursUntilExpiry > 0
  }

  const canApprove = (request: ApprovalRequest) => {
    return (
      request.status === 'pending' &&
      request.requested_by !== user?.email &&
      !request.approved_by.includes(user?.email || '')
    )
  }

  const canCancel = (request: ApprovalRequest) => {
    return (
      request.requested_by === user?.email &&
      (request.status === 'pending' || request.status === 'approved')
    )
  }

  const renderApprovalCard = (request: ApprovalRequest) => (
    <div key={request.request_id} className="card hover:shadow-lg transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-2">
            <h3 className="text-lg font-semibold text-gray-900">
              {request.operation_type.replace(/_/g, ' ').toUpperCase()}
            </h3>
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${getRiskLevelColor(request.risk_level)}`}>
              {request.risk_level.toUpperCase()}
            </span>
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(request.status)}`}>
              {request.status.toUpperCase()}
            </span>
          </div>
          <p className="text-sm text-gray-600">Instance: {request.instance_id}</p>
          <p className="text-sm text-gray-600">Environment: {request.environment}</p>
        </div>
        {isExpiringSoon(request.expires_at) && request.status === 'pending' && (
          <div className="flex items-center gap-1 text-orange-600">
            <AlertTriangle className="w-4 h-4" />
            <span className="text-xs">Expiring Soon</span>
          </div>
        )}
      </div>

      <div className="space-y-3 mb-4">
        <div className="flex items-start gap-2">
          <User className="w-4 h-4 text-gray-400 mt-0.5" />
          <div className="flex-1">
            <p className="text-xs text-gray-500">Requested by</p>
            <p className="text-sm font-medium">{request.requested_by}</p>
          </div>
        </div>

        <div className="flex items-start gap-2">
          <Calendar className="w-4 h-4 text-gray-400 mt-0.5" />
          <div className="flex-1">
            <p className="text-xs text-gray-500">Requested at</p>
            <p className="text-sm">{formatDate(request.requested_at)}</p>
          </div>
        </div>

        <div className="flex items-start gap-2">
          <MessageSquare className="w-4 h-4 text-gray-400 mt-0.5" />
          <div className="flex-1">
            <p className="text-xs text-gray-500">Justification</p>
            <p className="text-sm">{request.justification}</p>
          </div>
        </div>

        {request.estimated_cost && (
          <div className="flex items-start gap-2">
            <DollarSign className="w-4 h-4 text-gray-400 mt-0.5" />
            <div className="flex-1">
              <p className="text-xs text-gray-500">Estimated Cost</p>
              <p className="text-sm font-medium">${request.estimated_cost.toFixed(2)}/month</p>
            </div>
          </div>
        )}

        <div className="flex items-start gap-2">
          <Shield className="w-4 h-4 text-gray-400 mt-0.5" />
          <div className="flex-1">
            <p className="text-xs text-gray-500">Approvals</p>
            <p className="text-sm">
              {request.approvals_received} of {request.approvals_required} received
            </p>
            {request.approved_by.length > 0 && (
              <p className="text-xs text-gray-600 mt-1">
                Approved by: {request.approved_by.join(', ')}
              </p>
            )}
          </div>
        </div>

        {request.rejection_reason && (
          <div className="bg-red-50 border border-red-200 rounded p-3">
            <p className="text-xs text-red-600 font-medium">Rejection Reason:</p>
            <p className="text-sm text-red-700">{request.rejection_reason}</p>
            <p className="text-xs text-red-600 mt-1">
              Rejected by {request.rejected_by} at {formatDate(request.rejected_at!)}
            </p>
          </div>
        )}
      </div>

      <div className="flex gap-2 pt-4 border-t">
        {canApprove(request) && (
          <button
            onClick={() => handleApprove(request)}
            className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          >
            <ThumbsUp className="w-4 h-4" />
            Approve
          </button>
        )}
        {canApprove(request) && (
          <button
            onClick={() => handleReject(request)}
            className="flex items-center gap-2 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors"
          >
            <ThumbsDown className="w-4 h-4" />
            Reject
          </button>
        )}
        {canCancel(request) && (
          <button
            onClick={() => handleCancel(request)}
            className="flex items-center gap-2 px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition-colors"
          >
            <XCircle className="w-4 h-4" />
            Cancel
          </button>
        )}
        <button
          onClick={() => setSelectedRequest(request)}
          className="flex items-center gap-2 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors ml-auto"
        >
          View Details
        </button>
      </div>
    </div>
  )

  if (pendingLoading || myRequestsLoading) {
    return <LoadingSpinner size="lg" />
  }

  const displayRequests = selectedTab === 'pending' 
    ? pendingApprovals || []
    : myRequests || []

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Approval Workflow</h1>
        <p className="text-sm text-gray-600 mt-1">
          Manage approval requests for high-risk RDS operations
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Pending Approvals</p>
              <p className="text-2xl font-bold text-yellow-600">
                {pendingApprovals?.length || 0}
              </p>
            </div>
            <Clock className="w-8 h-8 text-yellow-600" />
          </div>
        </div>

        <div className="card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">My Requests</p>
              <p className="text-2xl font-bold text-blue-600">
                {myRequests?.length || 0}
              </p>
            </div>
            <User className="w-8 h-8 text-blue-600" />
          </div>
        </div>

        <div className="card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Approved Today</p>
              <p className="text-2xl font-bold text-green-600">
                {myRequests?.filter(r => 
                  r.status === 'approved' && 
                  new Date(r.approved_at!).toDateString() === new Date().toDateString()
                ).length || 0}
              </p>
            </div>
            <CheckCircle className="w-8 h-8 text-green-600" />
          </div>
        </div>

        <div className="card">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">Rejected</p>
              <p className="text-2xl font-bold text-red-600">
                {myRequests?.filter(r => r.status === 'rejected').length || 0}
              </p>
            </div>
            <XCircle className="w-8 h-8 text-red-600" />
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setSelectedTab('pending')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              selectedTab === 'pending'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            Pending Approvals ({pendingApprovals?.length || 0})
          </button>
          <button
            onClick={() => setSelectedTab('my-requests')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              selectedTab === 'my-requests'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            My Requests ({myRequests?.length || 0})
          </button>
        </nav>
      </div>

      {/* Approval Cards */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {displayRequests.length === 0 ? (
          <div className="col-span-2 text-center py-12">
            <Clock className="w-16 h-16 text-gray-400 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-gray-900 mb-2">
              No {selectedTab === 'pending' ? 'pending approvals' : 'requests'} found
            </h3>
            <p className="text-gray-600">
              {selectedTab === 'pending' 
                ? 'There are no approval requests waiting for your review.'
                : 'You haven\'t created any approval requests yet.'}
            </p>
          </div>
        ) : (
          displayRequests.map(renderApprovalCard)
        )}
      </div>

      {/* Approve Modal */}
      {showApproveModal && selectedRequest && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-semibold mb-4">Approve Request</h3>
            <p className="text-sm text-gray-600 mb-4">
              You are about to approve the request for <strong>{selectedRequest.operation_type}</strong> on{' '}
              <strong>{selectedRequest.instance_id}</strong>.
            </p>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Comments (Optional)
              </label>
              <textarea
                value={comments}
                onChange={(e) => setComments(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500"
                rows={3}
                placeholder="Add any comments about this approval..."
              />
            </div>
            <div className="flex gap-3">
              <button
                onClick={confirmApprove}
                disabled={approveMutation.isPending}
                className="flex-1 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50"
              >
                {approveMutation.isPending ? 'Approving...' : 'Confirm Approval'}
              </button>
              <button
                onClick={() => {
                  setShowApproveModal(false)
                  setComments('')
                }}
                className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reject Modal */}
      {showRejectModal && selectedRequest && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h3 className="text-lg font-semibold mb-4">Reject Request</h3>
            <p className="text-sm text-gray-600 mb-4">
              Please provide a reason for rejecting this request.
            </p>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Rejection Reason *
              </label>
              <textarea
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-red-500"
                rows={3}
                placeholder="Explain why this request is being rejected..."
                required
              />
            </div>
            <div className="flex gap-3">
              <button
                onClick={confirmReject}
                disabled={rejectMutation.isPending || !rejectionReason.trim()}
                className="flex-1 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
              >
                {rejectMutation.isPending ? 'Rejecting...' : 'Confirm Rejection'}
              </button>
              <button
                onClick={() => {
                  setShowRejectModal(false)
                  setRejectionReason('')
                }}
                className="flex-1 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Request Details Modal */}
      {selectedRequest && !showApproveModal && !showRejectModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <div className="flex items-start justify-between mb-4">
              <h3 className="text-lg font-semibold">Request Details</h3>
              <button
                onClick={() => setSelectedRequest(null)}
                className="text-gray-400 hover:text-gray-600"
              >
                <XCircle className="w-6 h-6" />
              </button>
            </div>
            
            <div className="space-y-4">
              <div>
                <p className="text-sm text-gray-600">Request ID</p>
                <p className="font-mono text-sm">{selectedRequest.request_id}</p>
              </div>
              
              <div>
                <p className="text-sm text-gray-600">Operation</p>
                <p className="font-medium">{selectedRequest.operation_type}</p>
              </div>
              
              <div>
                <p className="text-sm text-gray-600">Parameters</p>
                <pre className="bg-gray-50 p-3 rounded text-xs overflow-x-auto">
                  {JSON.stringify(selectedRequest.parameters, null, 2)}
                </pre>
              </div>
              
              {selectedRequest.comments.length > 0 && (
                <div>
                  <p className="text-sm text-gray-600 mb-2">Comments</p>
                  <div className="space-y-2">
                    {selectedRequest.comments.map((comment, idx) => (
                      <div key={idx} className="bg-gray-50 p-3 rounded">
                        <p className="text-xs text-gray-600">
                          {comment.user} - {formatDate(comment.timestamp)}
                        </p>
                        <p className="text-sm mt-1">{comment.comment}</p>
                      </div>
                    ))}
                  </div>
                </div>
              )}
              
              <div>
                <p className="text-sm text-gray-600">Expires At</p>
                <p className="text-sm">{formatDate(selectedRequest.expires_at)}</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
