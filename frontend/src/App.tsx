import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { CognitoService } from './lib/auth/cognito'
import { AuthProvider } from './lib/auth/AuthContext'
import { setTokenGetter } from './lib/api'
import AuthErrorBoundary from './components/AuthErrorBoundary'
import ProtectedRoute from './components/ProtectedRoute'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import InstanceList from './pages/InstanceList'
import InstanceDetail from './pages/InstanceDetail'
import CostDashboard from './pages/CostDashboard'
import ComplianceDashboard from './pages/ComplianceDashboard'
import UserManagement from './pages/UserManagement'
import ComputeMonitoring from './pages/ComputeMonitoring'
import ConnectionMonitoring from './pages/ConnectionMonitoring'
import ApprovalsDashboard from './pages/ApprovalsDashboard'
import Login from './pages/Login'
import Callback from './pages/Callback'
import Logout from './pages/Logout'
import AccessDenied from './pages/AccessDenied'

// Initialize Cognito service
const cognitoService = new CognitoService({
  userPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID || '',
  clientId: import.meta.env.VITE_COGNITO_CLIENT_ID || '',
  region: import.meta.env.VITE_COGNITO_REGION || 'ap-southeast-1',
  domain: import.meta.env.VITE_COGNITO_DOMAIN || '',
  redirectUri: import.meta.env.VITE_COGNITO_REDIRECT_URI || window.location.origin + '/callback',
  logoutUri: import.meta.env.VITE_COGNITO_LOGOUT_URI || window.location.origin,
})

// Set token getter for API client
setTokenGetter(() => cognitoService.getIdToken())

function App() {
  const handleAuthSuccess = () => {
    // Auth context will be updated automatically
    // No need to reload - let React Router handle navigation
    console.log('Authentication successful')
  }

  return (
    <AuthErrorBoundary>
      <AuthProvider cognitoService={cognitoService}>
        <BrowserRouter>
          <Routes>
            {/* Public routes */}
            <Route path="/login" element={<Login />} />
            <Route path="/callback" element={<Callback cognitoService={cognitoService} onAuthSuccess={handleAuthSuccess} />} />
            <Route path="/logout" element={<Logout />} />
            <Route path="/access-denied" element={<AccessDenied />} />

            {/* Protected routes */}
            <Route
              path="/"
              element={
                <ProtectedRoute>
                  <Layout />
                </ProtectedRoute>
              }
            >
              <Route index element={<Navigate to="/dashboard" replace />} />
              
              <Route
                path="dashboard"
                element={
                  <ProtectedRoute requiredPermission="view_instances">
                    <Dashboard />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="instances"
                element={
                  <ProtectedRoute requiredPermission="view_instances">
                    <InstanceList />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="instances/:instanceId"
                element={
                  <ProtectedRoute requiredPermission="view_instances">
                    <InstanceDetail />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="instances/:instanceId/compute"
                element={
                  <ProtectedRoute requiredPermission="view_metrics">
                    <ComputeMonitoring />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="instances/:instanceId/connections"
                element={
                  <ProtectedRoute requiredPermission="view_metrics">
                    <ConnectionMonitoring />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="costs"
                element={
                  <ProtectedRoute requiredPermission="view_costs">
                    <CostDashboard />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="compliance"
                element={
                  <ProtectedRoute requiredPermission="view_compliance">
                    <ComplianceDashboard />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="users"
                element={
                  <ProtectedRoute requiredPermission="manage_users">
                    <UserManagement />
                  </ProtectedRoute>
                }
              />
              
              <Route
                path="approvals"
                element={
                  <ProtectedRoute requiredPermission="execute_operations">
                    <ApprovalsDashboard />
                  </ProtectedRoute>
                }
              />
            </Route>
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </AuthErrorBoundary>
  )
}

export default App
