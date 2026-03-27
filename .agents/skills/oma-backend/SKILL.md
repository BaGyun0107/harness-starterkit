---
name: oma-backend
description: |
  Backend specialist for APIs, databases, authentication with clean architecture
  (BaseController/Service/Repository pattern). Use for API, endpoint, REST, database,
  server, migration, auth, middleware, logging, config, error handling, and deployment work.
  Covers the full production stack: Express 5, Prisma 6, Zod validation, JWT auth with
  CSRF Double Submit, Pino structured logging, rate limiting, graceful shutdown.
  Use this skill whenever backend code needs to follow established patterns.
---

# Backend Agent — API & Server Specialist

## When to use
- Building REST API endpoints (CRUD, search, aggregation)
- Authentication and authorization (JWT, CSRF, role-based)
- Database design, migrations, seed scripts
- Server-side business logic and validation
- Middleware, error handling, logging setup
- Background jobs and scheduled tasks
- Server configuration and deployment

## When NOT to use
- Frontend UI → use oma-frontend
- Mobile-specific code → use oma-mobile
- Database schema design only → use oma-db

## Architecture Overview

```
Request → Middleware Stack → Router → Controller → Service → Repository → Prisma
                                         ↓
                                   BaseController
                                (handleSuccess / handleError / validateRequest)
```

Every controller extends `BaseController` which provides standardized success/error responses with traceId, timestamps, and production-safe error masking. Business logic lives in Services, data access in Repositories. Controllers only orchestrate.

### Layer Responsibilities

| Layer | Does | Does NOT |
|-------|------|----------|
| **Controller** | Parse request, validate input, call service, return response | Business logic, direct DB access |
| **Service** | Business logic, orchestrate repos, external API calls | HTTP concerns, raw SQL |
| **Repository** | Prisma queries, input/output interfaces, soft delete filtering | Business decisions, HTTP |

### Module Structure (per domain)

```
src/
├── controllers/{Domain}Controller.ts    # extends BaseController
├── services/{domain}Service.ts          # business logic
├── repositories/{Domain}Repository.ts   # Prisma queries
├── routes/{domain}Routes.ts             # Express router + middleware
└── types/                               # shared interfaces
```

Each route file instantiates its own Repository → Service → Controller as module-level singletons. No DI container — manual wiring.

## Middleware Stack (order matters)

The middleware stack in `app.ts` executes in this exact order. New middleware must be inserted at the correct position:

```
1. helmet()           — Security headers + CSP
2. cors()             — origin: true, credentials: true
3. express.json()     — Body parsing
4. cookieParser()     — Cookie parsing (before auth)
5. pinoHttp()         — Request logging + traceId generation
6. timeout            — 30s request timeout → 408
7. slowDown()         — Progressive delay after 50 req/15min
8. rateLimit()        — Hard limit 100 req/15min → 429
9. /health            — Health check endpoint
10. /docs             — Scalar API Reference
11. /api/v1/*         — Application routes
12. errorBoundary     — Global error handler (MUST be last)
```

Read `resources/middleware-reference.md` for implementation details of each middleware.

## Authentication System

Three-token architecture with CSRF Double Submit pattern:

| Token | Cookie Name | HttpOnly | Lifetime | Purpose |
|-------|------------|----------|----------|---------|
| Access Token | `accessToken` | Yes | 10 min | API authentication |
| Refresh Token | `refreshToken` | Yes | 7d (365d auto-login) | Silent refresh |
| CSRF Token | `CSRFToken` | **No** | Same as refresh | Double Submit validation |

**Silent Refresh**: When access token expires, `requireAuth` middleware automatically generates new tokens using the refresh token. The original refresh token's `exp` is preserved to prevent infinite session extension.

**CSRF Validation**: State-changing methods (POST/PUT/PATCH/DELETE) must send `x-csrf-token` header matching the `CSRFToken` cookie value.

Read `resources/auth-reference.md` for token generation, cookie configuration, and middleware flow.

## Error Handling

All controllers extend `BaseController` which provides:

**Success Response:**
```json
{ "success": true, "status": 200, "message": "optional", "data": { ... } }
```

**Error Response:**
```json
{
  "success": false, "status": 400,
  "error": {
    "code": "validation_error",
    "message": "Human-readable message",
    "timestamp": "2026-03-27T00:00:00.000Z",
    "traceId": "req-uuid",
    "details": [{ "field": "name", "message": "required", "code": "missing_field" }]
  }
}
```

Each controller implements `resolve{Domain}ErrorStatus(error): number` to map domain error codes (strings like `'USER_NOT_FOUND'`) to HTTP status codes. 500 errors have their message masked in production.

## Configuration

All environment variables are validated at startup via Zod schema in `config/unifiedConfig.ts`. Invalid config halts the server immediately — no silent failures.

Read `resources/config-reference.md` for the full variable list, defaults, and config structure.

## Logging

Pino-based structured logging with three outputs:

| Target | Level | Path | Rotation |
|--------|-------|------|----------|
| Combined | info+ | `logs/combined-*.log` | Daily, 14 days, 20MB |
| Error | error+ | `logs/error-*.log` | Daily, 14 days, 20MB |
| Console | debug (dev) / info (prod) | stdout | — |

**Sensitive field redaction**: `password, token, authorization, cookie, secret` (including nested paths) are automatically redacted.

**Request context**: Every log entry includes `traceId` (from pino-http), `userId` (from req.user), request method, path, and duration.

## Database Patterns

- **IDs**: User uses CUID (`@default(cuid())`), all other models use BigInt autoincrement
- **Soft Delete**: All models have `deletedAt DateTime?` — every query must filter `deletedAt: null`
- **Coordinates**: `Decimal(13, 10)` for WGS84 lat/lng
- **BigInt Serialization**: `bigint-polyfill.ts` enables `JSON.stringify()` for BigInt values
- **Query Logging**: All Prisma queries logged at debug level via pino

Read `resources/orm-reference.md` for transaction patterns, pagination, and relationship loading.

## Utility Reference

| Utility | File | Purpose |
|---------|------|---------|
| `asyncErrorWrapper` | `utils/asyncErrorWrapper.ts` | Wraps async handlers to catch promise rejections |
| `BcryptUtil` | `utils/bcrypt.ts` | Hash/compare with password + pwdKey concatenation (10 rounds) |
| `generateOrderNo` | `utils/nanoid.ts` | `YYMMDD-XXXXXX` format (Crockford Base32) |
| `getClientIp` | `utils/ip.ts` | Extracts IP (x-forwarded-for → cf-connecting-ip → req.ip) |
| `httpClient` | `utils/axios.ts` | Axios with interceptors, 30s timeout, error mapping |
| `logger` | `utils/logger.ts` | Pino instance with KST timestamps, rotation, redaction |
| `prisma` | `utils/prisma.ts` | Singleton PrismaClient with query logging |
| Token utils | `utils/token.ts` | generateAccessToken, generateRefreshToken, generateCSRFToken, setAuthCookies, clearAuthCookies |
| Tag parsers | `utils/tagRequestParsers.ts` | parseBigIntId, parseRequiredString, parseTagIds |
| Tag mappers | `utils/tagMappers.ts` | toTagDto, toTagCategoryDto, withMappedTags |

## Server Lifecycle

**Startup** (`server.ts`):
1. Import bigint-polyfill
2. Start Express server on configured port
3. Initialize cron jobs
4. Log startup + docs URL

**Graceful Shutdown**:
- Listens for `SIGTERM` and `SIGINT`
- Closes server, waits for active connections
- Force exits after 10 seconds if connections don't close

## Core Rules

1. **Every controller extends BaseController** — use handleSuccess/handleError, never raw res.json()
2. **Every route handler wrapped** with `asyncErrorWrapper()` — no unhandled promise rejections
3. **All inputs validated** with Zod schemas or `validateRequest()` — fail fast with 400
4. **Soft delete everywhere** — never use `delete`, always update `deletedAt`; every query filters `deletedAt: null`
5. **Domain error codes** — throw `new Error('USER_NOT_FOUND')`, resolve to HTTP status in controller
6. **No business logic in controllers** — controllers parse, validate, delegate to service
7. **Parameterized queries only** — Prisma handles this, but never use `$queryRaw` with string interpolation
8. **Token secrets in config** — never hardcode; all auth config from unifiedConfig
9. **Log with context** — always include userId, traceId, operation name in log entries
10. **Repository input/output interfaces** — define `Create{X}Input`, `Update{X}Input` per repository

## Stack Detection

1. **Project files first** — Read `package.json`, `prisma/schema.prisma`, `tsconfig.json`
2. **stack/ second** — Use `stack/` for supplementary coding conventions and snippets
3. **Neither exists** — Ask user or suggest `/stack-set`

## References

**Architecture & Patterns:**
- Middleware details: `resources/middleware-reference.md`
- Auth system: `resources/auth-reference.md`
- Config variables: `resources/config-reference.md`
- Error handling: `resources/error-playbook.md`

**Coding:**
- Execution steps: `resources/execution-protocol.md`
- Code examples: `resources/examples.md`
- ORM reference: `resources/orm-reference.md`
- Checklist: `resources/checklist.md`

**Stack-Specific:**
- Tech stack: `stack/tech-stack.md`
- Snippets: `stack/snippets.md`
- API template: `stack/api-template.ts`

**Shared:**
- Context loading: `../_shared/core/context-loading.md`
- Skill routing: `../_shared/core/skill-routing.md`
- Prompt structure: `../_shared/core/prompt-structure.md`
