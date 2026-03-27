# Middleware Reference

## Stack Order (app.ts)

Middleware executes in this exact order. Position matters for security and functionality.

### 1. helmet() — Security Headers

```typescript
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      scriptSrc: ["'self'", "'unsafe-inline'", "cdn.jsdelivr.net"],
      imgSrc: ["'self'", "data:", "cdn.jsdelivr.net"],
      styleSrc: ["'self'", "'unsafe-inline'", "cdn.jsdelivr.net"],
      connectSrc: ["'self'", "https://proxy.scalar.com"],
    },
  },
}));
```

CSP directives allow Scalar API docs (cdn.jsdelivr.net, proxy.scalar.com).

### 2. cors() — Cross-Origin

```typescript
app.use(cors({ origin: true, credentials: true }));
```

Permissive for development. Production should restrict `origin` to specific domains.

### 3-4. Body & Cookie Parsing

```typescript
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
```

cookieParser must come before any auth middleware that reads cookies.

### 5. pinoHttp() — Request Logging & TraceId

```typescript
app.use(pinoHttp({
  logger,
  autoLogging: false,
  genReqId: (req) => req.headers['x-request-id'] as string || randomUUID(),
}));
```

- Generates unique `req.id` for every request (used as traceId in responses)
- Reads `x-request-id` header if provided (proxy/gateway pass-through)
- Falls back to UUID v4

### 6. Request Timeout

```typescript
app.use((req, res, next) => {
  req.setTimeout(config.server.timeoutMs, () => {
    res.status(408).json({
      error: { code: 'request_timeout', message: '요청 시간이 초과되었습니다.' }
    });
  });
  next();
});
```

Default: 30 seconds. Returns 408 on timeout.

### 7. slowDown() — Progressive Delay

```typescript
app.use(slowDown({
  windowMs: config.slowdown.windowMs,     // 15 min
  delayAfter: config.slowdown.delayAfter, // 50 requests
  delayMs: (used) => (used - config.slowdown.delayAfter) * config.slowdown.delayMs,
}));
```

After 50 requests in 15 minutes, each subsequent request is delayed by 500ms × excess count. Prevents spam without hard-blocking.

### 8. rateLimit() — Hard Limit

```typescript
app.use(rateLimit({
  windowMs: config.rateLimit.windowMs,  // 15 min
  limit: config.rateLimit.max,          // 100 requests
  message: {
    error: {
      code: 'rate_limit_exceeded',
      message: '요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요.',
    },
  },
}));
```

Returns 429 when limit exceeded.

### 9-10. Health Check & API Docs

```typescript
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/docs', apiReference({ /* Scalar OpenAPI 3.1.0 spec */ }));
```

Both are public — no auth required.

### 11. Application Routes

```typescript
app.use('/api/v1', v1Routes);
```

### 12. Error Boundary (MUST be last)

```typescript
app.use(errorBoundary);
```

The error boundary is a 4-parameter Express error handler. It catches all unhandled errors from routes and middleware, logs them with pino, and returns a standardized error response with traceId. In production, 500 error messages are masked to "Internal Server Error".

## Route-Level Middleware

### requireAuth

Applied to protected routes. Three-step process:
1. CSRF validation (state-changing methods only)
2. Access token verification → sets `req.user`
3. Silent refresh if access token expired but refresh token valid

```typescript
router.post('/posts', requireAuth, asyncErrorWrapper((req, res) => controller.create(req, res)));
```

### requireAdmin

Applied after requireAuth. Checks `req.user.role === 'ADMIN'`.

```typescript
router.use(requireAuth, requireAdmin);
router.post('/sync', asyncErrorWrapper((req, res) => controller.sync(req, res)));
```

### requireApiKey

For server-to-server endpoints. Checks `x-api-key` header or `api_key` query param.

```typescript
router.get('/internal/data', requireApiKey, asyncErrorWrapper((req, res) => ...));
```

## asyncErrorWrapper

Every route handler MUST be wrapped:

```typescript
// Correct
router.get('/', asyncErrorWrapper((req, res) => controller.getAll(req, res)));

// Wrong — unhandled promise rejection
router.get('/', (req, res) => controller.getAll(req, res));
```

The wrapper catches promise rejections and passes them to `next()` for the error boundary.
