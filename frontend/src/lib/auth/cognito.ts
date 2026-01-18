// import { CognitoUserPool } from 'amazon-cognito-identity-js' // Unused for now

export interface CognitoConfig {
  userPoolId: string
  clientId: string
  region: string
  domain: string
  redirectUri: string
  logoutUri: string
}

export interface TokenResponse {
  idToken: string
  accessToken: string
  refreshToken: string
}

export interface Session {
  idToken: string
  accessToken: string
  refreshToken: string
  expiresAt: number
}

export class CognitoService {
  // private userPool: CognitoUserPool // Unused for now
  private config: CognitoConfig
  private session: Session | null = null
  private codeVerifier: string | null = null

  constructor(config: CognitoConfig) {
    this.config = config
    // Initialize user pool for potential future use
    // this.userPool = new CognitoUserPool({
    //   UserPoolId: config.userPoolId,
    //   ClientId: config.clientId,
    // })
  }

  /**
   * Generate cryptographically secure code verifier for PKCE
   * Must be 43-128 characters, using unreserved characters [A-Z] [a-z] [0-9] - . _ ~
   */
  private generateCodeVerifier(): string {
    // Generate 32 random bytes (256 bits)
    const array = new Uint8Array(32)
    crypto.getRandomValues(array)
    
    // Convert to base64url (URL-safe base64)
    // This will produce a 43-character string from 32 bytes
    return this.base64UrlEncode(array.buffer)
  }

  /**
   * Generate random string for nonce/state
   */
  private generateRandomString(length: number): string {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    const randomValues = new Uint8Array(length)
    crypto.getRandomValues(randomValues)
    return Array.from(randomValues)
      .map((v) => charset[v % charset.length])
      .join('')
  }

  /**
   * Generate SHA256 hash for PKCE code challenge
   */
  private async sha256(plain: string): Promise<ArrayBuffer> {
    const encoder = new TextEncoder()
    const data = encoder.encode(plain)
    return await crypto.subtle.digest('SHA-256', data)
  }

  /**
   * Base64 URL encode
   */
  private base64UrlEncode(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '')
  }

  /**
   * Generate PKCE code challenge
   */
  private async generateCodeChallenge(codeVerifier: string): Promise<string> {
    const hashed = await this.sha256(codeVerifier)
    return this.base64UrlEncode(hashed)
  }

  /**
   * Redirect to Cognito Hosted UI for login
   */
  async login(): Promise<void> {
    const authUrl = await this.buildAuthUrl()
    window.location.href = authUrl
  }

  /**
   * Build Cognito Hosted UI authorization URL with PKCE
   */
  private async buildAuthUrl(): Promise<string> {
    // Generate PKCE code verifier and challenge
    this.codeVerifier = this.generateCodeVerifier()
    const codeChallenge = await this.generateCodeChallenge(this.codeVerifier)
    
    // Create state parameter that includes the code verifier (base64 encoded for URL safety)
    const stateData = {
      verifier: this.codeVerifier,
      nonce: this.generateRandomString(16)
    }
    const state = btoa(JSON.stringify(stateData))
    
    console.log('Login - generating PKCE:', {
      codeVerifierLength: this.codeVerifier.length,
      codeVerifierPreview: this.codeVerifier.substring(0, 20) + '...',
      codeVerifierFull: this.codeVerifier,
      codeChallengeLength: codeChallenge.length,
      codeChallengePreview: codeChallenge.substring(0, 20) + '...',
      codeChallengeFull: codeChallenge,
      stateLength: state.length
    })
    
    // Verify PKCE by regenerating challenge from verifier
    const verifyChallenge = await this.generateCodeChallenge(this.codeVerifier)
    console.log('PKCE Verification:', {
      originalChallenge: codeChallenge,
      regeneratedChallenge: verifyChallenge,
      match: codeChallenge === verifyChallenge
    })

    const params = new URLSearchParams({
      client_id: this.config.clientId,
      response_type: 'code',
      scope: 'openid email profile',
      redirect_uri: this.config.redirectUri,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
      state: state,
    })

    const authUrl = `https://${this.config.domain}/oauth2/authorize?${params.toString()}`
    console.log('Login - redirecting with state parameter')
    
    return authUrl
  }

  /**
   * Handle OAuth callback and exchange code for tokens
   */
  async handleCallback(code: string, state?: string): Promise<TokenResponse> {
    try {
      // Retrieve code verifier from state parameter
      let codeVerifier: string | null = null
      
      if (state) {
        try {
          console.log('Callback - raw state parameter:', state)
          // Decode the base64 state parameter directly (no URL decoding needed)
          const stateData = JSON.parse(atob(state))
          codeVerifier = stateData.verifier
          console.log('Callback - extracted code verifier from state:', {
            hasCodeVerifier: !!codeVerifier,
            codeVerifierLength: codeVerifier?.length,
            codeVerifierFull: codeVerifier,
            code: code.substring(0, 10) + '...'
          })
        } catch (e) {
          console.error('Failed to parse state parameter:', e)
        }
      }
      
      if (!codeVerifier) {
        console.error('PKCE code verifier not found in state parameter')
        throw new Error('PKCE code verifier not found. Please try logging in again.')
      }

      const tokenUrl = `https://${this.config.domain}/oauth2/token`
      
      const params = new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: this.config.clientId,
        code,
        redirect_uri: this.config.redirectUri,
        code_verifier: codeVerifier,
      })

      console.log('Exchanging code for tokens with PKCE...', {
        codeVerifierLength: codeVerifier.length,
        codeVerifierPreview: codeVerifier.substring(0, 20) + '...',
        codeVerifierFull: codeVerifier,
        redirectUri: this.config.redirectUri,
        codePreview: code.substring(0, 20) + '...',
        tokenUrl,
        bodyParams: params.toString()
      })
      
      // Verify the code verifier would generate the expected challenge
      const expectedChallenge = await this.generateCodeChallenge(codeVerifier)
      console.log('Token Exchange - Expected Code Challenge:', {
        codeVerifier: codeVerifier,
        expectedChallenge: expectedChallenge,
        expectedChallengeLength: expectedChallenge.length
      })

      const response = await fetch(tokenUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
      })

      // Code verifier was in state parameter, no need to clear storage

      if (!response.ok) {
        const errorText = await response.text()
        console.error('Token exchange failed:', {
          status: response.status,
          statusText: response.statusText,
          error: errorText,
          params: {
            grant_type: 'authorization_code',
            client_id: this.config.clientId,
            redirect_uri: this.config.redirectUri,
            code: code.substring(0, 10) + '...',
            hasCodeVerifier: true
          }
        })
        throw new Error(`Failed to exchange code for tokens: ${errorText}`)
      }

      const data = await response.json()

      console.log('Token exchange successful')

      // Store session in memory
      this.session = {
        idToken: data.id_token,
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
        expiresAt: Date.now() + data.expires_in * 1000,
      }

      return {
        idToken: data.id_token,
        accessToken: data.access_token,
        refreshToken: data.refresh_token,
      }
    } catch (error) {
      console.error('Error handling callback:', error)
      throw error
    }
  }

  /**
   * Logout and clear session
   */
  logout(): void {
    // Clear session from memory
    this.session = null

    // Redirect to Cognito logout endpoint
    // Using logout_uri parameter to redirect to custom sign-out page
    const logoutUrl = `https://${this.config.domain}/logout?client_id=${this.config.clientId}&logout_uri=${encodeURIComponent(this.config.logoutUri)}`
    console.log('Logout URL:', logoutUrl)
    window.location.href = logoutUrl
  }

  /**
   * Get current session
   */
  getCurrentSession(): Session | null {
    if (!this.session) {
      return null
    }

    // Check if token is expired
    if (Date.now() >= this.session.expiresAt) {
      this.session = null
      return null
    }

    return this.session
  }

  /**
   * Refresh access token using refresh token
   */
  async refreshToken(refreshToken: string): Promise<TokenResponse> {
    try {
      const tokenUrl = `https://${this.config.domain}/oauth2/token`
      
      const params = new URLSearchParams({
        grant_type: 'refresh_token',
        client_id: this.config.clientId,
        refresh_token: refreshToken,
      })

      const response = await fetch(tokenUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: params.toString(),
      })

      if (!response.ok) {
        throw new Error('Failed to refresh token')
      }

      const data = await response.json()

      // Update session
      if (this.session) {
        this.session = {
          ...this.session,
          idToken: data.id_token,
          accessToken: data.access_token,
          expiresAt: Date.now() + data.expires_in * 1000,
        }
      }

      return {
        idToken: data.id_token,
        accessToken: data.access_token,
        refreshToken: this.session?.refreshToken || refreshToken,
      }
    } catch (error) {
      console.error('Error refreshing token:', error)
      throw error
    }
  }

  /**
   * Check if token is valid (not expired)
   */
  isTokenValid(token: string): boolean {
    try {
      const payload = this.parseToken(token)
      return payload.exp * 1000 > Date.now()
    } catch {
      return false
    }
  }

  /**
   * Parse JWT token
   */
  parseToken(token: string): any {
    try {
      const base64Url = token.split('.')[1]
      const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/')
      const jsonPayload = decodeURIComponent(
        atob(base64)
          .split('')
          .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
          .join('')
      )
      return JSON.parse(jsonPayload)
    } catch (error) {
      console.error('Error parsing token:', error)
      throw error
    }
  }

  /**
   * Set session (used after callback)
   */
  setSession(session: Session): void {
    this.session = session
  }

  /**
   * Get ID token
   */
  getIdToken(): string | null {
    const token = this.session?.idToken || null
    console.log('getIdToken called:', {
      hasSession: !!this.session,
      hasToken: !!token,
      tokenPreview: token ? token.substring(0, 30) + '...' : 'none'
    })
    return token
  }

  /**
   * Get access token
   */
  getAccessToken(): string | null {
    return this.session?.accessToken || null
  }
}
