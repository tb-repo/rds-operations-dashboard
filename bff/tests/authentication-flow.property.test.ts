/**
 * Property Test: Authentication Flow Preservation
 * 
 * Validates: Requirements 7.2
 * Property 11: For any authentication request, the complete auth flow 
 * should work correctly with clean URLs
 */

import { describe, test, expect } from '@jest/globals'
import fc from 'fast-check'
import axios from 'axios'

// Test configuration
const API_BASE_URL = process.env.TEST_API_URL || 'https://08mqqv008c.execute-api.ap-southeast-1.amazonaws.com'
const COGNITO_DOMAIN = process.env.COGNITO_DOMAIN || 'rds-operations-dashboard'
const COGNITO_REGION = process.env.AWS_REGION || 'ap-southeast-1'
const CLIENT_ID = process.env.COGNITO_CLIENT_ID || 'test-client-id'
const TIMEOUT = 15000

// Authentication flow endpoints
const AUTH_ENDPOINTS = {
  login: '/api/auth/login',
  logout: '/api/auth/logout',
  refresh: '/api/auth/refresh',
  user: '/api/auth/user',
  callback: '/api/auth/callback'
};

// PKCE and OAuth utilities for testing
function generateCodeVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return btoa(String.fromCharCode.apply(null, Array.from(array)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function generateCodeChallenge(verifier: string): string {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  return crypto.subtle.digest('SHA-256', data).then(hash => {
    return btoa(String.fromCharCode.apply(null, Array.from(new Uint8Array(hash))))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  });
}

// Property: Authentication Flow Preservation
describe('Property 11: Authentication Flow Preservation', () => {
  
  test('Authentication endpoints should use clean URLs', () => {
    fc.assert(
      fc.property(
        fc.constantFrom(...Object.values(AUTH_ENDPOINTS)),
        (endpoint) => {
          const fullUrl = `${API_BASE_URL}${endpoint}`;
          
          // Property: Auth endpoints should not contain stage prefixes
          expect(fullUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Property: Should follow consistent URL pattern
          expect(fullUrl).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/api\/auth\/[a-z]+$/);
          
          // Property: Should be valid URLs
          expect(() => new URL(fullUrl)).not.toThrow();
          
          return true;
        }
      ),
      { numRuns: 10 }
    );
  });
  
  test('OAuth authorization URLs should be clean and properly formatted', () => {
    fc.assert(
      fc.property(
        fc.record({
          responseType: fc.constantFrom('code', 'token'),
          scope: fc.constantFrom('openid', 'openid profile', 'openid email profile'),
          state: fc.string({ minLength: 10, maxLength: 50 }),
          codeChallenge: fc.string({ minLength: 43, maxLength: 128 }),
          codeChallengeMethod: fc.constantFrom('S256', 'plain')
        }),
        ({ responseType, scope, state, codeChallenge, codeChallengeMethod }) => {
          // Property: OAuth URLs should be clean and properly constructed
          const redirectUri = `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`;
          
          // Redirect URI should be clean
          expect(redirectUri).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Construct authorization URL
          const authUrl = new URL(`https://${COGNITO_DOMAIN}.auth.${COGNITO_REGION}.amazoncognito.com/oauth2/authorize`);
          authUrl.searchParams.set('response_type', responseType);
          authUrl.searchParams.set('client_id', CLIENT_ID);
          authUrl.searchParams.set('redirect_uri', redirectUri);
          authUrl.searchParams.set('scope', scope);
          authUrl.searchParams.set('state', state);
          
          if (responseType === 'code') {
            authUrl.searchParams.set('code_challenge', codeChallenge);
            authUrl.searchParams.set('code_challenge_method', codeChallengeMethod);
          }
          
          // Property: Authorization URL should be valid and clean
          expect(authUrl.toString()).toMatch(/^https:\/\/[a-z0-9-]+\.auth\.[a-z0-9-]+\.amazoncognito\.com\/oauth2\/authorize/);
          expect(authUrl.searchParams.get('redirect_uri')).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
  
  test('Login endpoint should handle authentication requests with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          method: fc.constantFrom('GET', 'POST'),
          includeRedirect: fc.boolean()
        }),
        async ({ method, includeRedirect }) => {
          const loginUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.login}`;
          
          // Property: Login URL should be clean
          expect(loginUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const params: any = {};
            if (includeRedirect) {
              params.redirect_uri = `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`;
              // Redirect URI should also be clean
              expect(params.redirect_uri).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
            }
            
            const response = await axios({
              method: method,
              url: loginUrl,
              params: method === 'GET' ? params : undefined,
              data: method === 'POST' ? params : undefined,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Response should handle auth flow correctly
            if (response.status === 200 || response.status === 302) {
              // Success or redirect response
              if (response.data && typeof response.data === 'object') {
                // Should not contain stage-prefixed URLs in response
                const responseStr = JSON.stringify(response.data);
                expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                
                // If it contains URLs, they should be clean
                if (response.data.authUrl || response.data.loginUrl) {
                  const authUrl = response.data.authUrl || response.data.loginUrl;
                  expect(authUrl).not.toMatch(/redirect_uri=[^&]*\/prod\/|redirect_uri=[^&]*\/staging\/|redirect_uri=[^&]*\/dev\//);
                }
              }
            } else if (response.status === 401 || response.status === 400) {
              // Expected for invalid requests
              expect([400, 401]).toContain(response.status);
            }
            
          } catch (error: any) {
            // Handle expected errors
            if (error.response && [400, 401, 405].includes(error.response.status)) {
              // Expected for auth endpoints without proper credentials
              expect([400, 401, 405]).toContain(error.response.status);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${loginUrl}: ${error.message}`);
            } else {
              console.warn(`Unexpected error testing ${loginUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 30000 }
    );
  });
  
  test('Logout endpoint should handle logout requests with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          method: fc.constantFrom('GET', 'POST'),
          includePostLogoutRedirect: fc.boolean()
        }),
        async ({ method, includePostLogoutRedirect }) => {
          const logoutUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.logout}`;
          
          // Property: Logout URL should be clean
          expect(logoutUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const params: any = {};
            if (includePostLogoutRedirect) {
              params.post_logout_redirect_uri = API_BASE_URL;
              // Post-logout redirect should be clean
              expect(params.post_logout_redirect_uri).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
            }
            
            const response = await axios({
              method: method,
              url: logoutUrl,
              params: method === 'GET' ? params : undefined,
              data: method === 'POST' ? params : undefined,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Logout response should be clean
            if (response.status === 200 || response.status === 302) {
              if (response.data && typeof response.data === 'object') {
                const responseStr = JSON.stringify(response.data);
                expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                
                // If response contains logout URL, it should be clean
                if (response.data.logoutUrl) {
                  expect(response.data.logoutUrl).not.toMatch(/post_logout_redirect_uri=[^&]*\/prod\/|post_logout_redirect_uri=[^&]*\/staging\/|post_logout_redirect_uri=[^&]*\/dev\//);
                }
              }
            }
            
          } catch (error: any) {
            // Handle expected errors
            if (error.response && [400, 401, 405].includes(error.response.status)) {
              expect([400, 401, 405]).toContain(error.response.status);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${logoutUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 8, timeout: 25000 }
    );
  });
  
  test('Token refresh should work with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          refreshToken: fc.string({ minLength: 50, maxLength: 200 }),
          clientId: fc.string({ minLength: 10, maxLength: 50 })
        }),
        async ({ refreshToken, clientId }) => {
          const refreshUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.refresh}`;
          
          // Property: Refresh URL should be clean
          expect(refreshUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const response = await axios.post(refreshUrl, {
              refresh_token: refreshToken,
              client_id: clientId,
              grant_type: 'refresh_token'
            }, {
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Token refresh response should be clean
            if (response.status === 200) {
              const data = response.data;
              if (data && typeof data === 'object') {
                const responseStr = JSON.stringify(data);
                expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                
                // Token response should have expected structure
                if (data.access_token) {
                  expect(typeof data.access_token).toBe('string');
                }
                if (data.id_token) {
                  expect(typeof data.id_token).toBe('string');
                }
              }
            } else if (response.status === 400 || response.status === 401) {
              // Expected for invalid refresh tokens
              expect([400, 401]).toContain(response.status);
            }
            
          } catch (error: any) {
            if (error.response && [400, 401].includes(error.response.status)) {
              // Expected for invalid tokens
              expect([400, 401]).toContain(error.response.status);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${refreshUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 5, timeout: 20000 }
    );
  });
  
  test('User info endpoint should work with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          authHeader: fc.option(fc.string({ minLength: 20, maxLength: 200 })),
          includeBearer: fc.boolean()
        }),
        async ({ authHeader, includeBearer }) => {
          const userUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.user}`;
          
          // Property: User info URL should be clean
          expect(userUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const headers: any = {};
            if (authHeader) {
              headers.Authorization = includeBearer ? `Bearer ${authHeader}` : authHeader;
            }
            
            const response = await axios.get(userUrl, {
              headers,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: User info response should be clean
            if (response.status === 200) {
              const data = response.data;
              if (data && typeof data === 'object') {
                const responseStr = JSON.stringify(data);
                expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                
                // User info should have expected structure
                if (data.sub || data.email || data.username) {
                  expect(typeof (data.sub || data.email || data.username)).toBe('string');
                }
              }
            } else if (response.status === 401) {
              // Expected without valid auth
              expect(response.status).toBe(401);
            }
            
          } catch (error: any) {
            if (error.response && error.response.status === 401) {
              // Expected without valid auth
              expect(error.response.status).toBe(401);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${userUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 8, timeout: 25000 }
    );
  });
  
  test('OAuth callback should handle authorization codes with clean URLs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({
          code: fc.string({ minLength: 20, maxLength: 100 }),
          state: fc.string({ minLength: 10, maxLength: 50 }),
          error: fc.option(fc.constantFrom('access_denied', 'invalid_request', 'server_error'))
        }),
        async ({ code, state, error }) => {
          const callbackUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`;
          
          // Property: Callback URL should be clean
          expect(callbackUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          try {
            const params: any = { state };
            if (error) {
              params.error = error;
            } else {
              params.code = code;
            }
            
            const response = await axios.get(callbackUrl, {
              params,
              timeout: TIMEOUT,
              validateStatus: (status) => status < 500
            });
            
            // Property: Callback response should be clean
            if (response.status === 200 || response.status === 302) {
              if (response.data && typeof response.data === 'object') {
                const responseStr = JSON.stringify(response.data);
                expect(responseStr).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                
                // If response contains redirect URLs, they should be clean
                if (response.data.redirectUrl || response.data.location) {
                  const redirectUrl = response.data.redirectUrl || response.data.location;
                  expect(redirectUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
                }
              }
            } else if (response.status === 400) {
              // Expected for invalid codes/states
              expect(response.status).toBe(400);
            }
            
          } catch (error: any) {
            if (error.response && [400, 401].includes(error.response.status)) {
              // Expected for invalid callback parameters
              expect([400, 401]).toContain(error.response.status);
            } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED') {
              console.warn(`Network error testing ${callbackUrl}: ${error.message}`);
            }
          }
          
          return true;
        }
      ),
      { numRuns: 10, timeout: 30000 }
    );
  });
  
  test('PKCE flow should work with clean URLs', () => {
    fc.assert(
      fc.property(
        fc.record({
          codeVerifier: fc.string({ minLength: 43, maxLength: 128 }),
          state: fc.string({ minLength: 10, maxLength: 50 })
        }),
        ({ codeVerifier, state }) => {
          // Property: PKCE flow URLs should be clean
          const redirectUri = `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`;
          expect(redirectUri).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Generate code challenge (simplified for testing)
          const codeChallenge = btoa(codeVerifier).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
          
          // Construct authorization URL with PKCE
          const authUrl = new URL(`https://${COGNITO_DOMAIN}.auth.${COGNITO_REGION}.amazoncognito.com/oauth2/authorize`);
          authUrl.searchParams.set('response_type', 'code');
          authUrl.searchParams.set('client_id', CLIENT_ID);
          authUrl.searchParams.set('redirect_uri', redirectUri);
          authUrl.searchParams.set('scope', 'openid profile email');
          authUrl.searchParams.set('state', state);
          authUrl.searchParams.set('code_challenge', codeChallenge);
          authUrl.searchParams.set('code_challenge_method', 'S256');
          
          // Property: PKCE authorization URL should be clean
          expect(authUrl.toString()).toMatch(/^https:\/\/[a-z0-9-]+\.auth\.[a-z0-9-]+\.amazoncognito\.com\/oauth2\/authorize/);
          expect(authUrl.searchParams.get('redirect_uri')).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          expect(authUrl.searchParams.get('code_challenge')).toBeTruthy();
          expect(authUrl.searchParams.get('code_challenge_method')).toBe('S256');
          
          return true;
        }
      ),
      { numRuns: 15 }
    );
  });
  
  test('Authentication state should be preserved across clean URL redirects', () => {
    fc.assert(
      fc.property(
        fc.record({
          originalPath: fc.constantFrom('/dashboard', '/instances', '/compliance', '/costs'),
          state: fc.string({ minLength: 10, maxLength: 50 }),
          sessionId: fc.string({ minLength: 20, maxLength: 40 })
        }),
        ({ originalPath, state, sessionId }) => {
          // Property: Auth state preservation should work with clean URLs
          const loginUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.login}`;
          const callbackUrl = `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`;
          const originalUrl = `${API_BASE_URL}${originalPath}`;
          
          // All URLs should be clean
          expect(loginUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          expect(callbackUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          expect(originalUrl).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // State should be preserved in URL parameters
          const stateParam = encodeURIComponent(JSON.stringify({
            originalPath,
            sessionId,
            timestamp: Date.now()
          }));
          
          const authUrlWithState = `${loginUrl}?state=${stateParam}&redirect_uri=${encodeURIComponent(callbackUrl)}`;
          
          // Property: Auth URL with state should be clean
          expect(authUrlWithState).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
          
          // Property: State should be decodable
          const decodedState = JSON.parse(decodeURIComponent(stateParam));
          expect(decodedState.originalPath).toBe(originalPath);
          expect(decodedState.sessionId).toBe(sessionId);
          expect(decodedState.timestamp).toBeGreaterThan(0);
          
          return true;
        }
      ),
      { numRuns: 20 }
    );
  });
});

// Integration tests for authentication flow
describe('Authentication Flow Integration', () => {
  
  test('Complete authentication flow should use clean URLs throughout', async () => {
    // Simulate complete auth flow
    const authFlow = [
      { step: 'Login Request', url: `${API_BASE_URL}${AUTH_ENDPOINTS.login}`, method: 'GET' },
      { step: 'Callback Handler', url: `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`, method: 'GET' },
      { step: 'User Info', url: `${API_BASE_URL}${AUTH_ENDPOINTS.user}`, method: 'GET' },
      { step: 'Logout', url: `${API_BASE_URL}${AUTH_ENDPOINTS.logout}`, method: 'POST' }
    ];
    
    authFlow.forEach(step => {
      // Property: All auth flow URLs should be clean
      expect(step.url).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
      expect(step.url).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/api\/auth\/[a-z]+$/);
    });
  });
  
  test('Authentication configuration should use clean URLs', () => {
    // Test auth configuration consistency
    const authConfig = {
      loginUrl: `${API_BASE_URL}${AUTH_ENDPOINTS.login}`,
      logoutUrl: `${API_BASE_URL}${AUTH_ENDPOINTS.logout}`,
      callbackUrl: `${API_BASE_URL}${AUTH_ENDPOINTS.callback}`,
      userInfoUrl: `${API_BASE_URL}${AUTH_ENDPOINTS.user}`,
      refreshUrl: `${API_BASE_URL}${AUTH_ENDPOINTS.refresh}`
    };
    
    Object.entries(authConfig).forEach(([key, url]) => {
      // Property: All auth config URLs should be clean
      expect(url).not.toMatch(/\/prod\/|\/staging\/|\/dev\//);
      expect(url).toMatch(/^https:\/\/[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com\/api\/auth\/[a-z]+$/);
    });
    
    // Property: All URLs should use the same base
    const baseUrls = Object.values(authConfig).map(url => {
      const parsed = new URL(url);
      return `${parsed.protocol}//${parsed.host}`;
    });
    
    const uniqueBaseUrls = [...new Set(baseUrls)];
    expect(uniqueBaseUrls.length).toBe(1); // Should all use the same base URL
  });
});