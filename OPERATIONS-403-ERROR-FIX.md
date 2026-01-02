# Operations 403 Forbidden Error - Fix Guide

**Date:** December 19, 2025  
**Status:** ⚠️ **USER PERMISSIONS ISSUE**  
**Issue:** 403 Forbidden when performing operations (start, stop, reboot, etc.)

---

## 🔍 **Root Cause Analysis**

### **Problem Identified**
When trying to perform operations like start/stop/reboot on RDS instances, you're getting:
```
Failed to load resource: the server responded with a status of 403 (Forbidden)
API Error: Object(anonymous)@api.ts:58
```

### **Why This Happens**
The 403 Forbidden error occurs because **operations require special permissions** that not all users have:

1. **Authentication** ✅ Working - You're logged in successfully
2. **Authorization** ❌ **FAILING** - You don't have the required permissions
3. **Required Permission:** `execute_operations`
4. **Who Has It:** Only users in `Admin` or `DBA` Cognito groups

### **Permission System**
```
┌─────────────┬─────────────────────────────────────────┐
│    Role     │              Permissions                │
├─────────────┼─────────────────────────────────────────┤
│   Admin     │ ✅ All permissions (including operations) │
│    DBA      │ ✅ Operations + CloudOps (no user mgmt)  │
│  ReadOnly   │ ❌ View only (NO operations)             │
│ No Groups   │ ❌ NO permissions (403 on everything)    │
└─────────────┴─────────────────────────────────────────┘
```

---

## 🔧 **Quick Fix**

### **Option 1: Use Diagnostic Script (Recommended)**
```powershell
# Run the diagnostic script
cd rds-operations-dashboard
.\diagnose-user-permissions.ps1
```

The script will:
- ✅ Check your current Cognito groups
- ✅ Show why you're getting 403 errors
- ✅ Offer to add you to the correct group
- ✅ Explain what each group can do

### **Option 2: Manual Fix via AWS Console**

1. **Open AWS Cognito Console**
   - Go to AWS Console → Cognito → User Pools
   - Find your user pool (likely named `rds-dashboard-users`)

2. **Find Your User**
   - Go to Users tab
   - Search for your email/username

3. **Check Current Groups**
   - Click on your username
   - Look at the "Groups" section
   - If empty or only "ReadOnly" → This is the problem!

4. **Add to Correct Group**
   - Click "Add user to group"
   - Choose either:
     - **DBA** (recommended) - Can perform operations
     - **Admin** - Full access including user management

5. **Log Out and Back In**
   - **IMPORTANT:** You must log out and log back in for changes to take effect
   - Clear browser cache if needed

---

## 🎯 **Which Group Should You Choose?**

### **DBA Group (Recommended for Most Users)**
```
✅ View all dashboards (instances, health, costs, compliance)
✅ Perform operations (start, stop, reboot, snapshot)
✅ Generate CloudOps requests for production changes
✅ Trigger discovery scans
❌ Cannot manage other users
```

### **Admin Group (For Administrators)**
```
✅ Everything DBA can do
✅ Manage users and assign roles
✅ Full system access
```

### **ReadOnly Group (View Only)**
```
✅ View all dashboards
❌ Cannot perform any operations
❌ Cannot generate CloudOps requests
❌ Cannot manage users
```

---

## 🧪 **Verification Steps**

### **After Adding to Group:**

1. **Log Out Completely**
   ```
   - Click logout in the dashboard
   - Clear browser cache/cookies
   - Close all browser tabs
   ```

2. **Log Back In**
   ```
   - Go to dashboard URL
   - Enter credentials again
   - Should see operations buttons enabled
   ```

3. **Test Operations**
   ```
   - Go to an RDS instance
   - Try a safe operation like "Create Snapshot"
   - Should work without 403 error
   ```

### **Expected Behavior After Fix:**
- ✅ **Safe Operations** (immediate): Create snapshot, modify backup window
- ✅ **Risky Operations** (with confirmation): Start, stop, reboot instances
- ✅ **Production Operations** (admin + confirmation): Operations on production instances

---

## 🔍 **Troubleshooting**

### **Still Getting 403 After Adding to Group?**

1. **Check Token Refresh**
   ```powershell
   # Clear browser data completely
   # Or try incognito/private browsing mode
   ```

2. **Verify Group Assignment**
   ```powershell
   # Run diagnostic script again
   .\diagnose-user-permissions.ps1
   ```

3. **Check Browser Console**
   ```javascript
   // Open browser dev tools (F12)
   // Look for JWT token in Network tab
   // Token should include groups in payload
   ```

### **Getting Different Errors?**

| Error Code | Meaning | Solution |
|------------|---------|----------|
| **401 Unauthorized** | Not logged in | Log in again |
| **403 Forbidden** | No permissions | Add to Admin/DBA group |
| **500 Internal Error** | Server issue | Check Lambda logs |

---

## 🛡️ **Security Notes**

### **Why This Security Exists**
- **Prevents Accidents** - Only trained users can perform operations
- **Audit Trail** - All operations are logged with user identity
- **Production Safety** - Extra safeguards for production instances
- **Role Separation** - Different access levels for different responsibilities

### **Production Operations Security**
Even with `execute_operations` permission, production operations have additional safeguards:
- **Admin Privileges Required** - Must be in Admin or DBA group
- **Explicit Confirmation** - Must include `confirm_production: true`
- **Enhanced Logging** - All production operations logged at WARNING level
- **Audit Trail** - 90-day retention of all operation attempts

---

## 📋 **Quick Reference Commands**

### **Check User Groups**
```powershell
aws cognito-idp admin-list-groups-for-user `
  --user-pool-id "YOUR_USER_POOL_ID" `
  --username "your-email@company.com"
```

### **Add User to DBA Group**
```powershell
aws cognito-idp admin-add-user-to-group `
  --user-pool-id "YOUR_USER_POOL_ID" `
  --username "your-email@company.com" `
  --group-name "DBA"
```

### **List All Groups**
```powershell
aws cognito-idp list-groups `
  --user-pool-id "YOUR_USER_POOL_ID"
```

---

## 🎉 **Expected Result After Fix**

Once you're added to the correct group and log back in:

### **Dashboard Changes**
- ✅ Operation buttons become enabled
- ✅ "Execute Operation" buttons appear
- ✅ No more 403 errors in browser console

### **Available Operations**
- ✅ **Create Snapshot** - Backup your database
- ✅ **Start Instance** - Start stopped instances  
- ✅ **Stop Instance** - Stop running instances
- ✅ **Reboot Instance** - Restart instances
- ✅ **Modify Backup Window** - Change backup timing

### **Production Operations**
- ✅ **Safe Operations** - Work immediately on production instances
- ⚠️ **Risky Operations** - Require `confirm_production: true` parameter
- 🔒 **Admin Operations** - Require Admin group membership

---

## 📞 **Need Help?**

### **Run the Diagnostic Script**
```powershell
cd rds-operations-dashboard
.\diagnose-user-permissions.ps1
```

### **Manual Steps Summary**
1. **AWS Console** → Cognito → User Pools → Users
2. **Find your user** → Add to group → Choose "DBA"
3. **Log out completely** → Log back in
4. **Test operations** → Should work!

---

**🎯 The fix is simple: Add your user to the DBA or Admin group in Cognito, then log out and back in!**

**Last Updated:** December 19, 2025  
**Status:** User permissions issue - easily fixable ✅  
**Next Action:** Run diagnostic script or add user to DBA group