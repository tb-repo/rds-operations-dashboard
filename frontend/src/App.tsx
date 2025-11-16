import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import InstanceList from './pages/InstanceList'
import InstanceDetail from './pages/InstanceDetail'
import CostDashboard from './pages/CostDashboard'
import ComplianceDashboard from './pages/ComplianceDashboard'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="instances" element={<InstanceList />} />
          <Route path="instances/:instanceId" element={<InstanceDetail />} />
          <Route path="costs" element={<CostDashboard />} />
          <Route path="compliance" element={<ComplianceDashboard />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}

export default App
