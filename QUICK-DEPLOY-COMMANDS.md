# ⚡ Quick Deploy Commands - Copy & Paste

**For experienced users who just need the commands.**

---

## 🚀 Full Deployment (Copy All)

```powershell
# Navigate to project
cd rds-operations-dashboard

# Install dependencies
cd infrastructure && npm install && cd ..
cd bff && npm install && cd ..
cd frontend && npm install && cd ..

# Deploy Auth Stack (replace email)
.\scripts\deploy-auth.ps1 -AdminEmail "your-email@company.com" -Environment prod

# Deploy BFF Stack
.\scripts\deploy-bff.ps1 -Environment prod

# Update frontend .env with BFF API URL (manual step)
# Edit frontend/.env and set VITE_API_URL=<BFF_API_URL>

# Test locally
cd frontend
npm run dev
```

---

## 📋 Individual Commands

### Deploy Auth Only
```powershell
.\scripts\deploy-auth.ps1 -AdminEmail "admin@company.com" -Environment prod
```

### Deploy BFF Only
```powershell
.\scripts\deploy-bff.ps1 -Environment prod
```

### Create Additional Users
```powershell
# DBA User
.\scripts\create-cognito-user.ps1 -Email "dba@company.com" -Group DBA

# ReadOnly User
.\scripts\create-cognito-user.ps1 -Email "readonly@company.com" -Group ReadOnly
```

### Test Locally
```powershell
cd frontend
npm run dev
# Open http://localhost:3000
```

---

## 🔍 Verification Commands

### Check Auth Stack
```powershell
aws cloudformation describe-stacks --stack-name RDSDashboard-Auth-prod
```

### Check BFF Stack
```powershell
aws cloudformation describe-stacks --stack-name RDSDashboard-BFF-prod
```

### Check User Groups
```powershell
aws cognito-idp admin-list-groups-for-user `
  --user-pool-id <USER_POOL_ID> `
  --username your-email@company.com
```

### View BFF Logs
```powershell
aws logs tail /aws/lambda/rds-dashboard-bff --follow
```

### View Audit Logs
```powershell
aws logs tail /aws/rds-dashboard/audit --follow
```

---

## 🗑️ Cleanup Commands

### Delete BFF Stack
```powershell
cd infrastructure
npx aws-cdk destroy RDSDashboard-BFF-prod
```

### Delete Auth Stack
```powershell
cd infrastructure
npx aws-cdk destroy RDSDashboard-Auth-prod
```

---

## 📝 Save These Values

After deployment, save these values:

```
User Pool ID:     _____________________________
Client ID:        _____________________________
Domain:           _____________________________
BFF API URL:      _____________________________
Admin Password:   _____________________________
DBA Password:     _____________________________
ReadOnly Password: ___________________________
```

---

## ✅ Quick Test Checklist

- [ ] Can access http://localhost:3000
- [ ] Can click "Login" and see Cognito UI
- [ ] Can log in with admin credentials
- [ ] Email shows in header
- [ ] "Users" link visible in navigation
- [ ] Can access User Management page
- [ ] Can view all dashboards
- [ ] Logout works

---

**For detailed instructions, see `DEPLOYMENT-CHECKLIST.md`**

