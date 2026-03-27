# Backend Checklist

Run through every item before submitting your work.

## Architecture

- [ ] Controller extends `BaseController`
- [ ] Controller uses `handleSuccess()` / `handleError()` (never raw `res.json()`)
- [ ] Controller implements `resolve{Domain}ErrorStatus(error): number`
- [ ] Service contains all business logic (not in controller or repository)
- [ ] Repository defines `Create{X}Input` / `Update{X}Input` interfaces
- [ ] Route handlers wrapped with `asyncErrorWrapper()`
- [ ] Module-level singleton wiring (Repo → Service → Controller in route file)

## Authentication & Security

- [ ] Protected routes use `requireAuth` middleware
- [ ] Admin routes use `requireAuth` + `requireAdmin`
- [ ] S2S endpoints use `requireApiKey`
- [ ] No hardcoded secrets — all from `config.auth.*`
- [ ] CSRF header (`x-csrf-token`) required for POST/PUT/PATCH/DELETE
- [ ] Token operations use utility functions from `utils/token.ts`
- [ ] Password hashing uses `BcryptUtil` (not raw bcrypt)
- [ ] Rate limiting applied (global + per-endpoint where needed)
- [ ] Input validation enforced (no raw user input in queries)
- [ ] No secrets in code or logs

## Database

- [ ] Soft delete: queries include `deletedAt: null` filter
- [ ] Soft delete: "delete" operations use `update({ deletedAt: new Date() })`
- [ ] BigInt IDs serialized correctly (polyfill loaded at startup)
- [ ] Pagination returns `{ items, meta: { total, page, limit, totalPages } }`
- [ ] Multi-step operations wrapped in `prisma.$transaction()`
- [ ] No `$queryRaw` with string interpolation (parameterized only)
- [ ] Relationship loading explicit via `include` (no lazy loading)
- [ ] Indexes on foreign keys and frequently queried columns
- [ ] No N+1 queries; loading strategy explicit
- [ ] Migrations created and tested

## Error Handling

- [ ] Domain errors thrown as `new Error('ERROR_CODE')` (string codes)
- [ ] Error codes mapped to HTTP status in controller's `resolve*ErrorStatus`
- [ ] Validation errors return 400 with `details` array (`{ field, message, code }`)
- [ ] 500 errors masked in production (no stack traces leaked)
- [ ] Error logs include: method, path, status, duration, traceId, userId

## Logging

- [ ] Uses `logger` from `utils/logger.ts` (not `console.log`)
- [ ] Log entries include context: userId, operation name, relevant IDs
- [ ] Sensitive data not logged (password, tokens — redaction handles most)

## Input Validation

- [ ] All inputs validated (Zod schema or `validateRequest()`)
- [ ] Request params parsed with type-safe helpers (`parseBigIntId`, `parseRequiredString`)
- [ ] Pagination params have defaults (page=1, limit=20)
- [ ] String inputs trimmed before use

## API Response Format

- [ ] Success: `{ success: true, status, message?, data }`
- [ ] Error: `{ success: false, status, error: { code, message, timestamp, traceId, details? } }`
- [ ] Pagination: `{ success: true, data: { items }, meta: { total, page, limit, totalPages } }`
- [ ] RESTful conventions followed (proper HTTP methods, status codes)

## Configuration

- [ ] New env vars added to Zod schema in `unifiedConfig.ts`
- [ ] Defaults provided for non-critical vars
- [ ] Sensitive vars have minimum length validation
- [ ] `env.example` updated with new variables

## Testing

- [ ] Unit tests for service layer logic
- [ ] Integration tests for endpoints (happy + error paths)
- [ ] Auth scenarios tested (missing token, expired, wrong role)

## Code Quality

- [ ] No business logic in route handlers
- [ ] Async/await used consistently
- [ ] Type annotations on all function signatures
- [ ] Clean architecture layers respected
