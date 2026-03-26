# Backend Agent — Tech Stack Reference (TypeScript / Express)

## Framework: Express

- **Runtime**: Node.js 22+
- **Language**: TypeScript 5.x (strict mode)
- **Framework**: Express 4.x / 5.x
- **Entry point**: `src/app.ts` → `src/server.ts`
- **Router**: `express.Router()` per feature module
- **Middleware chain**: cors → helmet → json → requestLogger → router → errorHandler

```ts
// app.ts
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { resourcesRouter } from './modules/resources/resources.router';
import { errorHandler } from './common/middleware/error-handler';

export const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json());

app.use('/api/resources', resourcesRouter);
app.use(errorHandler);
```

## ORM: Prisma 6+

- **Client**: `@prisma/client` — generated singleton
- **Schema**: `prisma/schema.prisma`
- **Usage**: Import `prisma` singleton, use typed client directly in repository layer

```ts
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';
export const prisma = new PrismaClient();
```

## Validation: Zod

- Define schemas alongside route handlers or in `dto/` files
- Use `schema.parse()` (throws) or `schema.safeParse()` (returns result)
- Infer TypeScript types via `z.infer<typeof Schema>`
- Middleware helper: `validateBody(schema)` wraps safeParse into Express middleware

## Migration: Prisma Migrate

```bash
# Dev — creates migration file + applies
npx prisma migrate dev --name <name>

# Production — applies pending migrations only
npx prisma migrate deploy

# Reset (dev only)
npx prisma migrate reset

# Generate client after schema change
npx prisma generate
```

## Test: Vitest + Supertest

- **Unit**: Vitest for service/repository logic
- **Integration**: Supertest against real Express `app` (no server listen)
- **Config**: `vitest.config.ts` at project root
- **Convention**: `*.test.ts` alongside source, `*.e2e.test.ts` in `tests/`

```bash
npx vitest run          # single pass
npx vitest              # watch mode
npx vitest run --coverage
```

## Linter / Formatter

- **ESLint**: `@typescript-eslint/eslint-plugin` + `@typescript-eslint/parser`
- **Prettier**: format on save, `.prettierrc` at root
- **Commands**:
  ```bash
  npx eslint src --ext .ts
  npx prettier --write src
  ```

## Project Layout

```
src/
  modules/
    resources/
      resources.router.ts      # Express Router
      resources.service.ts     # Business logic
      resources.repository.ts  # Prisma queries
      resources.dto.ts         # Zod schemas + inferred types
  common/
    middleware/
      auth.ts                  # JWT verification middleware
      validate.ts              # Zod validation middleware
      error-handler.ts         # Global error handler
    errors/
      AppError.ts              # Custom error class
  lib/
    prisma.ts                  # Prisma singleton
  app.ts
  server.ts
prisma/
  schema.prisma
  migrations/
```
