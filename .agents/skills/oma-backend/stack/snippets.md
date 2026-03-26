# Backend Agent — Code Snippets (TypeScript / Express / Prisma)

Copy-paste ready patterns. Adapt to the specific task.

---

## 1. Express Router + JWT Auth Middleware

```typescript
// modules/resources/resources.router.ts
import { Router } from 'express';
import { authenticate } from '../../common/middleware/auth';
import { validateBody, validateQuery } from '../../common/middleware/validate';
import { ResourcesService } from './resources.service';
import { CreateResourceSchema, UpdateResourceSchema, ResourceQuerySchema } from './resources.dto';

const service = new ResourcesService();
export const resourcesRouter = Router();

resourcesRouter.use(authenticate); // all routes require JWT

resourcesRouter.get('/', validateQuery(ResourceQuerySchema), async (req, res, next) => {
  try {
    const result = await service.findAll(req.user!.id, req.query as any);
    res.json(result);
  } catch (err) { next(err); }
});

resourcesRouter.get('/:id', async (req, res, next) => {
  try {
    const resource = await service.findOne(req.params.id, req.user!.id);
    res.json(resource);
  } catch (err) { next(err); }
});

resourcesRouter.post('/', validateBody(CreateResourceSchema), async (req, res, next) => {
  try {
    const resource = await service.create(req.body, req.user!.id);
    res.status(201).json(resource);
  } catch (err) { next(err); }
});

resourcesRouter.patch('/:id', validateBody(UpdateResourceSchema), async (req, res, next) => {
  try {
    const resource = await service.update(req.params.id, req.body, req.user!.id);
    res.json(resource);
  } catch (err) { next(err); }
});

resourcesRouter.delete('/:id', async (req, res, next) => {
  try {
    await service.remove(req.params.id, req.user!.id);
    res.status(204).send();
  } catch (err) { next(err); }
});
```

```typescript
// common/middleware/auth.ts
import { RequestHandler } from 'express';
import jwt from 'jsonwebtoken';
import { AppError } from '../errors/AppError';

export const authenticate: RequestHandler = (req, _res, next) => {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new AppError(401, 'Unauthorized');
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET!) as { sub: string };
    req.user = { id: payload.sub };
    next();
  } catch {
    next(new AppError(401, 'Invalid token'));
  }
};
```

---

## 2. Zod Validation Middleware

```typescript
// common/middleware/validate.ts
import { RequestHandler } from 'express';
import { ZodSchema } from 'zod';
import { AppError } from '../errors/AppError';

export const validateBody = (schema: ZodSchema): RequestHandler => (req, _res, next) => {
  const result = schema.safeParse(req.body);
  if (!result.success) {
    return next(new AppError(400, 'Validation failed', result.error.flatten()));
  }
  req.body = result.data;
  next();
};

export const validateQuery = (schema: ZodSchema): RequestHandler => (req, _res, next) => {
  const result = schema.safeParse(req.query);
  if (!result.success) {
    return next(new AppError(400, 'Invalid query params', result.error.flatten()));
  }
  req.query = result.data as any;
  next();
};
```

```typescript
// modules/resources/resources.dto.ts
import { z } from 'zod';

export const CreateResourceSchema = z.object({
  title: z.string().min(1).max(200),
  description: z.string().max(1000).optional(),
  status: z.enum(['active', 'archived']).default('active'),
});

export const UpdateResourceSchema = CreateResourceSchema.partial();

export const ResourceQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  search: z.string().optional(),
  status: z.enum(['active', 'archived']).optional(),
});

export type CreateResourceDto = z.infer<typeof CreateResourceSchema>;
export type UpdateResourceDto = z.infer<typeof UpdateResourceSchema>;
export type ResourceQueryDto = z.infer<typeof ResourceQuerySchema>;
```

---

## 3. Prisma Model Example

```prisma
// prisma/schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String     @id @default(uuid()) @db.Uuid
  email     String     @unique
  password  String
  resources Resource[]
  createdAt DateTime   @default(now()) @map("created_at")
  updatedAt DateTime   @updatedAt @map("updated_at")

  @@map("users")
}

model Resource {
  id          String    @id @default(uuid()) @db.Uuid
  title       String    @db.VarChar(200)
  description String?   @db.Text
  status      String    @default("active") @db.VarChar(20)
  userId      String    @map("user_id") @db.Uuid
  user        User      @relation(fields: [userId], references: [id], onDelete: Cascade)
  createdAt   DateTime  @default(now()) @map("created_at")
  updatedAt   DateTime  @updatedAt @map("updated_at")
  deletedAt   DateTime? @map("deleted_at")

  @@index([userId])
  @@map("resources")
}
```

---

## 4. Dependency Injection (manual, no framework)

Express는 NestJS DI 컨테이너가 없으므로 모듈 레벨 싱글턴 패턴을 사용한다.

```typescript
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };
export const prisma = globalForPrisma.prisma ?? new PrismaClient();
if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
```

```typescript
// modules/resources/index.ts — wire once, export singleton
import { ResourcesRepository } from './resources.repository';
import { ResourcesService } from './resources.service';
import { resourcesRouter as _router } from './resources.router';

const repo = new ResourcesRepository();
export const resourcesService = new ResourcesService(repo);
export { _router as resourcesRouter };
```

---

## 5. Repository Pattern

```typescript
// modules/resources/resources.repository.ts
import { prisma } from '../../lib/prisma';
import { Prisma, Resource } from '@prisma/client';
import { CreateResourceDto, UpdateResourceDto, ResourceQueryDto } from './resources.dto';

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

export class ResourcesRepository {
  async findPaginated(userId: string, query: ResourceQueryDto): Promise<PaginatedResult<Resource>> {
    const { page, limit, search, status } = query;
    const where: Prisma.ResourceWhereInput = {
      userId,
      deletedAt: null,
      ...(status && { status }),
      ...(search && { title: { contains: search, mode: 'insensitive' } }),
    };

    const [items, total] = await prisma.$transaction([
      prisma.resource.findMany({
        where,
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { createdAt: 'desc' },
      }),
      prisma.resource.count({ where }),
    ]);

    return { items, total, page, limit, totalPages: Math.ceil(total / limit) };
  }

  async findOne(id: string, userId: string): Promise<Resource | null> {
    return prisma.resource.findFirst({ where: { id, userId, deletedAt: null } });
  }

  async create(userId: string, data: CreateResourceDto): Promise<Resource> {
    return prisma.resource.create({ data: { ...data, user: { connect: { id: userId } } } });
  }

  async update(id: string, data: UpdateResourceDto): Promise<Resource> {
    return prisma.resource.update({ where: { id }, data });
  }

  async softDelete(id: string): Promise<Resource> {
    return prisma.resource.update({ where: { id }, data: { deletedAt: new Date() } });
  }
}
```

---

## 6. Paginated Query

(5번 Repository의 `findPaginated` 참조)

서비스 레이어에서 호출:

```typescript
// resources.service.ts
async findAll(userId: string, query: ResourceQueryDto): Promise<PaginatedResult<Resource>> {
  return this.repo.findPaginated(userId, query);
}
```

응답 형태:

```json
{
  "items": [...],
  "total": 42,
  "page": 1,
  "limit": 20,
  "totalPages": 3
}
```

---

## 7. Prisma Migration

```bash
# 새 마이그레이션 생성 + 적용 (dev)
npx prisma migrate dev --name add_resources_table

# 프로덕션 적용
npx prisma migrate deploy

# 클라이언트 재생성 (schema 변경 후 항상 실행)
npx prisma generate

# 스키마 확인
npx prisma validate
```

생성되는 마이그레이션 SQL 예:

```sql
-- prisma/migrations/20240101000000_add_resources_table/migration.sql
CREATE TABLE "resources" (
    "id"          UUID         NOT NULL DEFAULT gen_random_uuid(),
    "title"       VARCHAR(200) NOT NULL,
    "description" TEXT,
    "status"      VARCHAR(20)  NOT NULL DEFAULT 'active',
    "user_id"     UUID         NOT NULL,
    "created_at"  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at"  TIMESTAMP(3) NOT NULL,
    "deleted_at"  TIMESTAMP(3),
    CONSTRAINT "resources_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "resources_user_id_idx" ON "resources"("user_id");

ALTER TABLE "resources"
    ADD CONSTRAINT "resources_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
```

---

## 8. Vitest + Supertest Test

```typescript
// tests/resources.e2e.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { app } from '../src/app';
import { prisma } from '../src/lib/prisma';

let authToken: string;

beforeAll(async () => {
  const res = await request(app)
    .post('/api/auth/login')
    .send({ email: 'test@example.com', password: 'password123' });
  authToken = res.body.accessToken;
});

afterAll(async () => {
  await prisma.resource.deleteMany({ where: { title: { startsWith: 'Test' } } });
  await prisma.$disconnect();
});

describe('Resources API', () => {
  it('POST /api/resources — 201 on valid payload', async () => {
    const res = await request(app)
      .post('/api/resources')
      .set('Authorization', `Bearer ${authToken}`)
      .send({ title: 'Test Resource', description: 'desc' });

    expect(res.status).toBe(201);
    expect(res.body).toMatchObject({ title: 'Test Resource', status: 'active' });
  });

  it('GET /api/resources — returns paginated list', async () => {
    const res = await request(app)
      .get('/api/resources')
      .set('Authorization', `Bearer ${authToken}`);

    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('items');
    expect(res.body).toHaveProperty('total');
  });

  it('GET /api/resources/:id — 404 for unknown id', async () => {
    const res = await request(app)
      .get('/api/resources/00000000-0000-0000-0000-000000000000')
      .set('Authorization', `Bearer ${authToken}`);

    expect(res.status).toBe(404);
  });

  it('GET /api/resources — 401 without token', async () => {
    const res = await request(app).get('/api/resources');
    expect(res.status).toBe(401);
  });
});
```

---

## Global Error Handler

```typescript
// common/middleware/error-handler.ts
import { ErrorRequestHandler } from 'express';
import { AppError } from '../errors/AppError';

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof AppError) {
    return res.status(err.status).json({ message: err.message, errors: err.details });
  }
  console.error(err);
  res.status(500).json({ message: 'Internal server error' });
};
```

```typescript
// common/errors/AppError.ts
export class AppError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = 'AppError';
  }
}
```
