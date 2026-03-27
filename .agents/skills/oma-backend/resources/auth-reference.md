# Authentication Reference

## Token Architecture

Three tokens work together for secure authentication with CSRF protection:

```
Browser                              Server
  │                                    │
  │─── POST /login ──────────────────→ │
  │                                    │ Generate: accessToken, refreshToken, CSRFToken
  │←── Set-Cookie: accessToken ───────│ (HttpOnly)
  │←── Set-Cookie: refreshToken ──────│ (HttpOnly)
  │←── Set-Cookie: CSRFToken ─────────│ (NOT HttpOnly — JS readable)
  │                                    │
  │─── POST /api/v1/posts ───────────→ │
  │    Cookie: accessToken             │ 1. CSRF check (header vs cookie)
  │    x-csrf-token: <CSRFToken>       │ 2. Verify access token
  │                                    │ 3. Set req.user
  │←── 200 OK ────────────────────────│
  │                                    │
  │─── POST /api/v1/posts ───────────→ │ (10 min later, access token expired)
  │    Cookie: refreshToken            │ 1. Access token expired
  │                                    │ 2. Verify refresh token
  │←── Set-Cookie: NEW tokens ────────│ 3. Silent refresh (new tokens)
  │←── 200 OK ────────────────────────│ 4. Process request normally
```

## Token Generation (utils/token.ts)

### Access Token
```typescript
generateAccessToken(payload: TokenPayload): string
// Signs with config.auth.accessTokenSecret
// Expires in: config.auth.jwtExpiresIn (default: '10m')
// Payload: { userId: string, role?: string, ...rest }
```

### Refresh Token
```typescript
generateRefreshToken(payload: TokenPayload, autoLogin = false): string
// Signs with config.auth.refreshTokenSecret
// Default expiry: 7 days (autoLogin: false) or 365 days (autoLogin: true)
//
// CRITICAL: If payload.exp exists (from previous token), it is PRESERVED.
// This prevents infinite session extension via repeated refreshes.
// The iat field is stripped to prevent jwt library from recalculating exp.
```

### CSRF Token
```typescript
generateCSRFToken(): string
// Returns: crypto.randomBytes(32).toString('hex') → 64-character hex string
// No JWT — just a random value for Double Submit Cookie pattern
```

## Cookie Configuration (utils/token.ts)

### setAuthCookies(res, accessToken, refreshToken, csrfToken, refreshTokenExpSeconds?)

| Cookie | httpOnly | secure | sameSite | maxAge |
|--------|----------|--------|----------|--------|
| `accessToken` | **true** | prod only | lax | 10 min |
| `refreshToken` | **true** | prod only | lax | 7d (or remaining from exp) |
| `CSRFToken` | **false** | prod only | lax | same as refresh |

- `domain`: From `config.auth.cookieDomain` (default: 'localhost')
- If `refreshTokenExpSeconds` is provided, maxAge = `max(remaining_ms, 0)` to sync with token expiry

### clearAuthCookies(res)
Clears all three cookies using the same domain setting.

## CSRF Double Submit Pattern

Only validated for state-changing methods: `POST, PUT, PATCH, DELETE`

```
1. Client reads CSRFToken cookie (not HttpOnly, so JS can read it)
2. Client sends the value in x-csrf-token header
3. Server compares: header value === cookie value
4. Mismatch → 403 { code: 'csrf_invalid' }
```

GET/HEAD/OPTIONS requests skip CSRF validation.

## requireAuth Middleware Flow

```
1. Is method state-changing (POST/PUT/PATCH/DELETE)?
   └── Yes → Validate CSRF (header vs cookie)
       └── Mismatch → 403 csrf_invalid

2. Read accessToken cookie
   └── Valid → Set req.user = decoded payload → PASS
   └── Expired → Go to step 3
   └── Invalid (not expired) → 401 unauthorized

3. Read refreshToken cookie (Silent Refresh)
   └── Valid → Generate new tokens
       ├── Preserve original exp (no infinite renewal)
       ├── Set new cookies on response
       ├── Set req.user = decoded payload
       └── PASS
   └── Expired → 401 session_expired
   └── Missing → 401 unauthorized

4. No tokens at all → 401 unauthorized
```

## Password Hashing (utils/bcrypt.ts)

```typescript
class BcryptUtil {
  static async hash(password: string, pwdKey: string): Promise<string>
  // Combines: password + pwdKey before hashing
  // Salt rounds: 10

  static async compare(password: string, hash: string, pwdKey: string): Promise<boolean>
  // Combines: password + pwdKey before comparing
}
```

The `pwdKey` is an additional secret that makes the hash unique per application. It is NOT the bcrypt salt (bcrypt generates its own salt internally).

## Type Definitions (types/express.d.ts)

```typescript
interface TokenPayload {
  userId: string;
  role?: string;
  [key: string]: any;
}

// Global augmentation — req.user is available in all route handlers
declare global {
  namespace Express {
    interface Request {
      user?: TokenPayload;
    }
  }
}
```

## Error Codes from Auth Middleware

| Code | Status | Cause |
|------|--------|-------|
| `csrf_invalid` | 403 | CSRF header doesn't match cookie |
| `unauthorized` | 401 | Missing or invalid token |
| `session_expired` | 401 | Refresh token expired |
| `forbidden` | 403 | User lacks required role (requireAdmin) |
