# API Convention

> Enforces DRY principle for all backend API calls. Components must never call `apiGet`/`apiPost`/`apiDelete` directly.

## Architecture

```
src/lib/api-client.ts                      <- Shared fetch wrapper (NEVER import directly in components)
src/lib/api-hooks.ts                       <- TanStack Query wrappers (useApiQuery, useApiMutation)
src/features/{name}/lib/{name}-api.ts      <- Feature-specific API functions + response DTO types
```

## Feature Directory Structure

```
src/features/[feature]/
├── components/           # Feature UI components
│   └── skeleton/         # Loading skeleton components
├── lib/                  # API functions + response types (api-client wrapper)
│   └── {feature}-api.ts  # All API calls for this feature
├── types/                # Feature-specific type definitions
└── utils/                # Feature-specific utilities & helpers
```

## Rules

1. **API functions must be defined in `features/{name}/lib/{name}-api.ts`** — never inline in components.
2. **Components import only from the feature api file** — functions and types both come from there.
3. **`apiGet`/`apiPost`/`apiDelete` from `api-client.ts` are used only inside feature api files** — they are internal plumbing, not public API.
4. **Response DTO types are exported from the feature api file** — components reuse these types instead of defining their own.
5. **No duplicate local interfaces** — if a component defines a local interface that mirrors an API response shape, extract it to the feature api file instead.

## Correct Pattern

```typescript
// features/community/lib/community-api.ts
import { apiGet, apiPost } from '@/lib/api-client';

export interface PostListResponse {
  items: CommunityPostSummaryDto[];
  meta: { total: number; page: number; limit: number; totalPages: number };
}

export const fetchRoomPosts = (roomId: string | number, page = 1, limit = 20) =>
  apiGet<PostListResponse>(`/community/rooms/${roomId}/posts`, { page, limit });

// features/community/components/practice-room-page-client.tsx
import { fetchRoomPosts, type PostListResponse } from '@/features/community/lib/community-api';

const postsQuery = useApiQuery<PostListResponse>({
  queryKey: ['room-posts', roomId],
  queryFn: () => fetchRoomPosts(roomId!, page, limit),
});
```

## Forbidden Pattern

```typescript
// WRONG: importing apiGet directly in a component
import { apiGet } from '@/lib/api-client';

const data = useApiQuery({
  queryFn: () => apiGet('/community/rooms/1/posts'),
});
```

## Current Feature API Files

| Feature | API File | Endpoints |
|---------|----------|-----------|
| explore | `explore/lib/explore-api.ts` | tour-places, regions, tags |
| community | `community/lib/community-api.ts` | rooms, posts, comments, likes |
| discovery | `discovery/lib/collections-api.ts` | collections |
| me | `me/lib/me-api.ts` | users/me/stats |

## Why This Matters

Without this convention, each component invents its own fetch calls and response types, leading to:
- **DRY violations** — the same endpoint called with slightly different error handling in 3 places
- **Type drift** — local interfaces that fall out of sync with the actual API response
- **Harder refactoring** — changing an endpoint means hunting through every component instead of updating one file
