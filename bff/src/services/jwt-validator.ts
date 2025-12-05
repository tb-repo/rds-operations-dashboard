import jwt, { JwtPayload } from 'jsonwebtoken'
import jwksClient, { JwksClient, SigningKey } from 'jwks-rsa'
import { logger } from '../utils/logger'

export interface CognitoTokenPayload extends JwtPayload {
  sub: string
  email: string
  email_verified: boolean
  'cognito:groups'?: string[]
  'cognito:username': string
  token_use: 'id' | 'access'
  auth_time: number
}

export interface TokenValidationResult {
  valid: boolean
  payload?: CognitoTokenPayload
  error?: string
}

export class JwtValidator {
  private jwksClient: JwksClient
  private issuer: string
  private audience?: string
  private keyCache: Map<string, SigningKey>
  private cacheExpiry: Map<string, number>
  private readonly CACHE_TTL = 3600000 // 1 hour in milliseconds

  constructor(userPoolId: string, region: string, clientId?: string) {
    this.issuer = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`
    this.audience = clientId
    
    // Initialize JWKS client to fetch Cognito public keys
    this.jwksClient = jwksClient({
      jwksUri: `${this.issuer}/.well-known/jwks.json`,
      cache: true,
      cacheMaxAge: this.CACHE_TTL,
      rateLimit: true,
      jwksRequestsPerMinute: 10,
    })

    this.keyCache = new Map()
    this.cacheExpiry = new Map()

    logger.info('JWT Validator initialized', {
      issuer: this.issuer,
      audience: this.audience,
    })
  }

  /**
   * Validate JWT token from Cognito
   */
  async validateToken(token: string): Promise<TokenValidationResult> {
    try {
      // Decode token without verification to get header
      const decoded = jwt.decode(token, { complete: true })
      
      if (!decoded || typeof decoded === 'string') {
        return {
          valid: false,
          error: 'Invalid token format',
        }
      }

      const { header, payload } = decoded

      // Verify token has required fields
      if (!header.kid) {
        return {
          valid: false,
          error: 'Token missing key ID (kid)',
        }
      }

      // Get signing key
      const signingKey = await this.getSigningKey(header.kid)
      
      if (!signingKey) {
        return {
          valid: false,
          error: 'Unable to find signing key',
        }
      }

      // Verify token signature and claims
      const verifiedPayload = await this.verifyTokenSignature(
        token,
        signingKey.getPublicKey()
      )

      if (!verifiedPayload) {
        return {
          valid: false,
          error: 'Token signature verification failed',
        }
      }

      // Validate token claims
      const claimsValid = this.validateClaims(verifiedPayload as CognitoTokenPayload)
      
      if (!claimsValid.valid) {
        return claimsValid
      }

      logger.debug('Token validated successfully', {
        sub: verifiedPayload.sub,
        email: (verifiedPayload as CognitoTokenPayload).email,
      })

      return {
        valid: true,
        payload: verifiedPayload as CognitoTokenPayload,
      }
    } catch (error) {
      logger.error('Token validation error', {
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      
      return {
        valid: false,
        error: error instanceof Error ? error.message : 'Token validation failed',
      }
    }
  }

  /**
   * Get signing key from JWKS endpoint with caching
   */
  private async getSigningKey(kid: string): Promise<SigningKey | null> {
    try {
      // Check cache first
      const cached = this.keyCache.get(kid)
      const expiry = this.cacheExpiry.get(kid)
      
      if (cached && expiry && Date.now() < expiry) {
        logger.debug('Using cached signing key', { kid })
        return cached
      }

      // Fetch from JWKS endpoint
      logger.debug('Fetching signing key from JWKS', { kid })
      const key = await this.jwksClient.getSigningKey(kid)
      
      // Cache the key
      this.keyCache.set(kid, key)
      this.cacheExpiry.set(kid, Date.now() + this.CACHE_TTL)
      
      return key
    } catch (error) {
      logger.error('Error fetching signing key', {
        kid,
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      return null
    }
  }

  /**
   * Verify token signature using public key
   */
  private async verifyTokenSignature(
    token: string,
    publicKey: string
  ): Promise<JwtPayload | null> {
    try {
      const verifyOptions: jwt.VerifyOptions = {
        issuer: this.issuer,
        algorithms: ['RS256'],
      }

      if (this.audience) {
        verifyOptions.audience = this.audience
      }

      const payload = jwt.verify(token, publicKey, verifyOptions) as JwtPayload
      return payload
    } catch (error) {
      logger.error('Token signature verification failed', {
        error: error instanceof Error ? error.message : 'Unknown error',
      })
      return null
    }
  }

  /**
   * Validate token claims
   */
  private validateClaims(payload: CognitoTokenPayload): TokenValidationResult {
    // Check token use
    if (payload.token_use !== 'id' && payload.token_use !== 'access') {
      return {
        valid: false,
        error: 'Invalid token use',
      }
    }

    // Check expiration
    if (payload.exp && Date.now() >= payload.exp * 1000) {
      return {
        valid: false,
        error: 'Token has expired',
      }
    }

    // Check not before
    if (payload.nbf && Date.now() < payload.nbf * 1000) {
      return {
        valid: false,
        error: 'Token not yet valid',
      }
    }

    // Check issuer
    if (payload.iss !== this.issuer) {
      return {
        valid: false,
        error: 'Invalid token issuer',
      }
    }

    // Check required fields
    if (!payload.sub || !payload.email) {
      return {
        valid: false,
        error: 'Token missing required claims',
      }
    }

    return {
      valid: true,
      payload,
    }
  }

  /**
   * Check if token is expired
   */
  isTokenExpired(token: string): boolean {
    try {
      const decoded = jwt.decode(token) as JwtPayload
      
      if (!decoded || !decoded.exp) {
        return true
      }

      return Date.now() >= decoded.exp * 1000
    } catch {
      return true
    }
  }

  /**
   * Extract payload without verification (for debugging)
   */
  decodeToken(token: string): CognitoTokenPayload | null {
    try {
      const decoded = jwt.decode(token) as CognitoTokenPayload
      return decoded
    } catch {
      return null
    }
  }
}
