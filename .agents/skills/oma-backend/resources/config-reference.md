# Configuration Reference

## Unified Config Pattern (config/unifiedConfig.ts)

All environment variables are validated at startup using a Zod schema. If validation fails, the server does not start — no silent misconfiguration in production.

```typescript
// Pattern: Zod schema → parse process.env → export typed config
const envSchema = z.object({ ... });
const parsed = envSchema.parse(process.env);
export const config = { /* structured groups */ };
```

## Environment Variables

### Core Server

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `NODE_ENV` | enum | `development` | `development`, `test`, `production` |
| `PORT` | number | `8080` | Server port |
| `DATABASE_URL` | string | optional | MySQL connection URL |

### Authentication

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ACCESS_TOKEN_SECRET` | string (min 10) | `default-access-secret-change-in-prod` | JWT signing secret |
| `REFRESH_TOKEN_SECRET` | string (min 10) | `default-refresh-secret-change-in-prod` | Refresh token secret |
| `CSRF_TOKEN_SECRET` | string (min 10) | `default-csrf-secret-change-in-prod` | CSRF validation secret |
| `COOKIE_DOMAIN` | string | `localhost` | Cookie domain |
| `JWT_EXPIRES_IN` | string | `10m` | Access token lifetime |
| `REFRESH_EXPIRES_IN` | string | `7d` | Refresh token lifetime |

### Logging

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `LOG_LEVEL` | string | `info` | Pino log level |

### Rate Limiting

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `RATE_LIMIT_WINDOW_MS` | number | `900000` (15 min) | Rate limit window |
| `RATE_LIMIT_MAX` | number | `100` | Max requests per window |
| `SLOWDOWN_WINDOW_MS` | number | `900000` | Slowdown window |
| `SLOWDOWN_DELAY_AFTER` | number | `50` | Requests before delay starts |
| `SLOWDOWN_DELAY_MS` | number | `500` | Delay increment per excess request |

### Server & API

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `REQUEST_TIMEOUT_MS` | number | `30000` (30s) | Request timeout |
| `PRIVATE_API_KEY` | string | `dev-private-api-key-change-me` | S2S API key |
| `DATA_KR_TOUR_INFO_KEY` | string | **REQUIRED** | Korean Tour API service key |

## Exported Config Structure

```typescript
export const config = {
  env: 'development' | 'test' | 'production',
  server: {
    port: number,
    timeoutMs: number,
  },
  db: {
    url: string | undefined,
  },
  auth: {
    accessTokenSecret: string,
    refreshTokenSecret: string,
    csrfTokenSecret: string,
    cookieDomain: string,
    jwtExpiresIn: string,
    refreshExpiresIn: string,
    privateApiKey: string,
  },
  logging: {
    level: string,
  },
  rateLimit: {
    windowMs: number,
    max: number,
  },
  slowdown: {
    windowMs: number,
    delayAfter: number,
    delayMs: number,
  },
  tourApi: {
    serviceKey: string,
    baseUrl: 'https://apis.data.go.kr',
  },
};
```

## Adding New Environment Variables

1. Add to Zod schema in `config/unifiedConfig.ts` with type, default, and description
2. Add to the exported config object under the appropriate group
3. Update `env.example` file
4. Document in this reference
5. If sensitive, add to GitHub Secrets (see CONTRIBUTING.md)

## Validation Patterns

Zod coerces types automatically:
- `z.coerce.number()` — strings from env become numbers
- `z.string().min(10)` — enforces minimum length for secrets
- `z.enum([...])` — restricts to allowed values
- `.default(value)` — provides fallback if env var not set
- `.optional()` — allows undefined (no fallback)

Startup failure on invalid config is intentional — catching misconfig before any requests are served is safer than runtime errors.
