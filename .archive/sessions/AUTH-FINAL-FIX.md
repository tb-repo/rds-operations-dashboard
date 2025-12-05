# Authentication Final Fix - Root Cause Analysis

## Root Cause Identified

After extensive analysis, the `invalid_grant` error is caused by **authorization code reuse**. Here's what's happening:

1. User clicks login → Redirects to Cognito
2. User authenticates → Cognito redirects back with authorization code
3. Callback page loads → Attempts token exchange
4. **Page reloads or React re-renders** → Attempts to use the SAME code again
5. Cognito rejects: `invalid_grant` (code already used)

## Why This Happens

### Authorization Code Rules (OAuth 2.0 / PKCE)
- Authorization codes are **single-use only**
- Once exchanged for tokens, the code becomes invalid
- Attempting to reuse a code results in `invalid_grant`
- Codes also expire after 5-10 minutes

### React Strict Mode
- In development, React Strict Mode causes components to mount twice
- This can trigger the useEffect twice
- Even with our deduplication logic, timing issues can occur

### Browser Behavior
- If the callback URL remains in the browser
- Any page refresh will attempt to reuse the expired code
- Back button can also cause this issue

## The Solution

We need to implement a **one-time code consumption pattern** with immediate URL cleanup:

### 1. Prevent Duplicate Processing (Already Implemented ✓)
```typescript
const processedCodeRef = useRef<string | null>(null)

if (code && processedCodeRef.current === code) {
  console.log('Callback already processing this code, skipping...')
  return
}
```

### 2. Clean URL Immediately After Success (MISSING - Need to Add)
```typescript
// After successful token exchange, clean the URL
const url = new URL(window.location.href)
url.searchParams.delete('code')
url.searchParams.delete('state')
window.history.replaceState({}, document.title, url.toString())
```

### 3. Add Strict Mode Protection (MISSING - Need to Add)
```typescript
// Use a flag to prevent double execution in React Strict Mode
const isProcessingRef = useRef(false)

if (isProcessingRef.current) {
  return
}
isProcessingRef.current = true
```

## Implementation Steps

### Step 1: Update Callback Component

Add URL cleanup and strict mode protection to `Callback.tsx`:

```typescript
useEffect(() => {
  const handleCallback = async () => {
    const code = searchParams.get('code')
    const state = searchParams.get('state')
    
    // Prevent double execution
    if (code && processedCodeRef.current === code) {
      return
    }
    
    if (isProcessingRef.current) {
      return
    }
    
    if (code) {
      processedCodeRef.current = code
      isProcessingRef.current = true
    }
    
    try {
      // ... token exchange ...
      
      // IMPORTANT: Clean URL immediately after success
      const url = new URL(window.location.href)
      url.searchParams.delete('code')
      url.searchParams.delete('state')
      url.searchParams.delete('error')
      window.history.replaceState({}, document.title, url.toString())
      
      // Navigate to dashboard
      navigate('/', { replace: true })
    } catch (err) {
      // Reset on error so user can try again
      processedCodeRef.current = null
      isProcessingRef.current = false
    }
  }
  
  handleCallback()
}, []) // Empty dependency array!
```

### Step 2: Test the Fix

1. **Clear all browser data** for localhost:3000
2. **Use incognito mode** to ensure clean state
3. **Click login** and authenticate
4. **Verify**:
   - Token exchange succeeds
   - URL is cleaned (no `?code=...` in address bar)
   - Dashboard loads successfully
   - No console errors

## Alternative: Use Session Storage

If the above doesn't work, we can use sessionStorage as a backup:

```typescript
// Before redirecting to Cognito
sessionStorage.setItem('pkce_verifier', codeVerifier)

// In callback
const verifier = sessionStorage.getItem('pkce_verifier')
sessionStorage.removeItem('pkce_verifier') // Remove immediately
```

## Why Previous Fixes Didn't Work

1. **PKCE Implementation**: Was actually correct all along
2. **Cognito Configuration**: Was already properly configured
3. **Code Verifier Generation**: Working correctly (43 characters)
4. **Code Challenge**: Properly generated with SHA-256

The issue was never with PKCE itself, but with **code reuse prevention**.

## Testing Checklist

- [ ] Clear browser data
- [ ] Use incognito window
- [ ] Click login
- [ ] Authenticate with Cognito
- [ ] Verify callback succeeds
- [ ] Check URL is cleaned
- [ ] Verify dashboard loads
- [ ] Try refreshing dashboard (should stay logged in)
- [ ] Try back button (should not cause errors)

## Success Criteria

✅ No `invalid_grant` errors
✅ Token exchange completes on first attempt
✅ URL is cleaned after callback
✅ Dashboard loads successfully
✅ Page refresh doesn't cause re-authentication
✅ No duplicate token exchange attempts

## If Still Failing

If the issue persists after these fixes:

1. **Enable Cognito CloudWatch Logs**:
   ```bash
   aws cognito-idp set-user-pool-mfa-config \
     --user-pool-id ap-southeast-1_4tyxh4qJe \
     --user-pool-add-ons AdvancedSecurityMode=AUDIT
   ```

2. **Check CloudWatch Logs** for detailed error messages

3. **Verify Code Challenge Matches**:
   - Log the code_challenge sent during authorization
   - Log the code_verifier sent during token exchange
   - Manually verify SHA-256(verifier) == challenge

4. **Test Without PKCE** (temporarily):
   - Remove `code_challenge` and `code_verifier` parameters
   - This will help isolate if the issue is PKCE-specific

## Next Steps

I'll now implement the URL cleanup fix in the Callback component.
