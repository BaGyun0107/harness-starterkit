/**
 * API Endpoint Template — TypeScript / Express / Prisma
 *
 * Demonstrates the Router → Service → Repository pattern.
 *
 * Recommended file layout:
 *   src/modules/resources/
 *     resources.router.ts       ← Express Router (this file, bottom section)
 *     resources.service.ts      ← Business logic
 *     resources.repository.ts   ← Prisma queries
 *     resources.dto.ts          ← Zod schemas + inferred types
 *   src/common/
 *     middleware/auth.ts        ← JWT authentication
 *     middleware/validate.ts    ← Zod validation helpers
 *     middleware/error-handler.ts
 *     errors/AppError.ts
 *   src/lib/prisma.ts           ← Prisma singleton
 */

// ─────────────────────────────────────────────────────────────────────────────
// src/common/errors/AppError.ts
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// src/lib/prisma.ts
// ─────────────────────────────────────────────────────────────────────────────

import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };
export const prisma = globalForPrisma.prisma ?? new PrismaClient();
if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;

// ─────────────────────────────────────────────────────────────────────────────
// src/common/middleware/auth.ts
// ─────────────────────────────────────────────────────────────────────────────

import { RequestHandler } from 'express';
import jwt from 'jsonwebtoken';

export const authenticate: RequestHandler = (req, _res, next) => {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return next(new AppError(401, 'Unauthorized'));
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET!) as { sub: string };
    (req as any).user = { id: payload.sub };
    next();
  } catch {
    next(new AppError(401, 'Invalid token'));
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// src/common/middleware/validate.ts
// ─────────────────────────────────────────────────────────────────────────────

import { ZodSchema } from 'zod';

export const validateBody = (schema: ZodSchema): RequestHandler => (req, _res, next) => {
  const result = schema.safeParse(req.body);
  if (!result.success) return next(new AppError(400, 'Validation failed', result.error.flatten()));
  req.body = result.data;
  next();
};

export const validateQuery = (schema: ZodSchema): RequestHandler => (req, _res, next) => {
  const result = schema.safeParse(req.query);
  if (!result.success) return next(new AppError(400, 'Invalid query params', result.error.flatten()));
  (req as any).parsedQuery = result.data;
  next();
};

// ─────────────────────────────────────────────────────────────────────────────
// src/common/middleware/error-handler.ts
// ─────────────────────────────────────────────────────────────────────────────

import { ErrorRequestHandler } from 'express';

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof AppError) {
    return void res.status(err.status).json({ message: err.message, errors: err.details });
  }
  console.error(err);
  res.status(500).json({ message: 'Internal server error' });
};

// ─────────────────────────────────────────────────────────────────────────────
// src/modules/resources/resources.dto.ts
// ─────────────────────────────────────────────────────────────────────────────

import { z } from 'zod';

export const CreateResourceSchema = z.object({
  title: z.string().min(1, 'Title is required').max(200),
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

// ─────────────────────────────────────────────────────────────────────────────
// src/modules/resources/resources.repository.ts
// ─────────────────────────────────────────────────────────────────────────────

import { Prisma, Resource } from '@prisma/client';

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

export class ResourcesRepository {
  async findPaginated(
    userId: string,
    query: ResourceQueryDto,
  ): Promise<PaginatedResult<Resource>> {
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
    return prisma.resource.create({
      data: { ...data, user: { connect: { id: userId } } },
    });
  }

  async update(id: string, data: UpdateResourceDto): Promise<Resource> {
    return prisma.resource.update({ where: { id }, data });
  }

  async softDelete(id: string): Promise<void> {
    await prisma.resource.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// src/modules/resources/resources.service.ts
// ─────────────────────────────────────────────────────────────────────────────

export class ResourcesService {
  constructor(private readonly repo: ResourcesRepository) {}

  async findAll(userId: string, query: ResourceQueryDto): Promise<PaginatedResult<Resource>> {
    return this.repo.findPaginated(userId, query);
  }

  async findOne(id: string, userId: string): Promise<Resource> {
    const resource = await this.repo.findOne(id, userId);
    if (!resource) throw new AppError(404, `Resource ${id} not found`);
    return resource;
  }

  async create(dto: CreateResourceDto, userId: string): Promise<Resource> {
    return this.repo.create(userId, dto);
  }

  async update(id: string, dto: UpdateResourceDto, userId: string): Promise<Resource> {
    await this.findOne(id, userId); // 404 / ownership check
    return this.repo.update(id, dto);
  }

  async remove(id: string, userId: string): Promise<void> {
    await this.findOne(id, userId); // 404 / ownership check
    await this.repo.softDelete(id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// src/modules/resources/resources.router.ts
// ─────────────────────────────────────────────────────────────────────────────

import { Router, Request, Response, NextFunction } from 'express';

const repo = new ResourcesRepository();
const service = new ResourcesService(repo);

export const resourcesRouter = Router();

// All routes require a valid JWT
resourcesRouter.use(authenticate);

// GET /api/resources?page=1&limit=20&search=foo&status=active
resourcesRouter.get(
  '/',
  validateQuery(ResourceQuerySchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const query = (req as any).parsedQuery as ResourceQueryDto;
      const result = await service.findAll((req as any).user.id, query);
      res.json(result);
    } catch (err) { next(err); }
  },
);

// GET /api/resources/:id
resourcesRouter.get(
  '/:id',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const resource = await service.findOne(req.params.id, (req as any).user.id);
      res.json(resource);
    } catch (err) { next(err); }
  },
);

// POST /api/resources
resourcesRouter.post(
  '/',
  validateBody(CreateResourceSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const resource = await service.create(req.body as CreateResourceDto, (req as any).user.id);
      res.status(201).json(resource);
    } catch (err) { next(err); }
  },
);

// PATCH /api/resources/:id
resourcesRouter.patch(
  '/:id',
  validateBody(UpdateResourceSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const resource = await service.update(req.params.id, req.body as UpdateResourceDto, (req as any).user.id);
      res.json(resource);
    } catch (err) { next(err); }
  },
);

// DELETE /api/resources/:id  (soft delete)
resourcesRouter.delete(
  '/:id',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await service.remove(req.params.id, (req as any).user.id);
      res.status(204).send();
    } catch (err) { next(err); }
  },
);
