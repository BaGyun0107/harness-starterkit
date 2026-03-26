# Frontend Agent — Code Snippets (Next.js 15 / App Router)

Copy-paste ready patterns. Adapt to the specific task.

---

## 1. Page (Server Component) + Auth Guard

```tsx
// app/(dashboard)/resources/page.tsx
import { redirect } from 'next/navigation';
import { getServerSession } from '@/lib/auth/session';
import { ResourceList } from '@/features/resources/components/resource-list';

export default async function ResourcesPage() {
  const session = await getServerSession();
  if (!session) redirect('/login');

  return (
    <main className="container py-8">
      <h1 className="text-2xl font-bold mb-6">Resources</h1>
      <ResourceList />
    </main>
  );
}
```

```ts
// lib/auth/session.ts
import { cookies } from 'next/headers';

export async function getServerSession() {
  const cookieStore = await cookies();
  const token = cookieStore.get('access-token')?.value;
  if (!token) return null;
  // verify JWT or call /api/me
  return { token };
}
```

---

## 2. Zod Validation Schema

```ts
// lib/validations/resource.ts
import { z } from 'zod';

export const createResourceSchema = z.object({
  title: z.string().min(1, '제목을 입력해 주세요').max(200),
  description: z.string().max(1000).optional(),
  status: z.enum(['active', 'archived']).default('active'),
});

export const updateResourceSchema = createResourceSchema.partial();

export type CreateResourceInput = z.infer<typeof createResourceSchema>;
export type UpdateResourceInput = z.infer<typeof updateResourceSchema>;
```

---

## 3. shadcn/ui + React Hook Form

```tsx
// features/resources/components/create-resource-form.tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { createResourceSchema, type CreateResourceInput } from '@/lib/validations/resource';
import { useCreateResource } from '../hooks/use-resources';
import {
  Form, FormControl, FormField, FormItem, FormLabel, FormMessage,
} from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';

export function CreateResourceForm({ onSuccess }: { onSuccess?: () => void }) {
  const form = useForm<CreateResourceInput>({
    resolver: zodResolver(createResourceSchema),
    defaultValues: { title: '', description: '', status: 'active' },
  });

  const { mutate, isPending } = useCreateResource();

  function onSubmit(values: CreateResourceInput) {
    mutate(values, { onSuccess });
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="title"
          render={({ field }) => (
            <FormItem>
              <FormLabel>제목</FormLabel>
              <FormControl>
                <Input placeholder="리소스 제목" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="description"
          render={({ field }) => (
            <FormItem>
              <FormLabel>설명</FormLabel>
              <FormControl>
                <Textarea placeholder="설명 (선택)" {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit" disabled={isPending}>
          {isPending ? '저장 중...' : '저장'}
        </Button>
      </form>
    </Form>
  );
}
```

---

## 4. Zustand Store (with persist)

```ts
// store/use-auth-store.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface User {
  id: string;
  email: string;
  name: string;
}

interface AuthState {
  user: User | null;
  accessToken: string | null;
  setAuth: (user: User, token: string) => void;
  clearAuth: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      accessToken: null,
      setAuth: (user, accessToken) => set({ user, accessToken }),
      clearAuth: () => set({ user: null, accessToken: null }),
    }),
    { name: 'auth-storage' },
  ),
);
```

---

## 5. TanStack Query — API + Hooks

```ts
// features/resources/api.ts
import { useAuthStore } from '@/store/use-auth-store';

const BASE = process.env.NEXT_PUBLIC_API_URL ?? '';

function authHeaders() {
  const token = useAuthStore.getState().accessToken;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...authHeaders(), ...init?.headers },
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<T>;
}

export const resourcesApi = {
  getAll: (params?: Record<string, string>) => {
    const qs = params ? '?' + new URLSearchParams(params).toString() : '';
    return request<PaginatedResult<Resource>>(`/api/resources${qs}`);
  },
  getOne: (id: string) => request<Resource>(`/api/resources/${id}`),
  create: (body: CreateResourceInput) =>
    request<Resource>('/api/resources', { method: 'POST', body: JSON.stringify(body) }),
  update: (id: string, body: UpdateResourceInput) =>
    request<Resource>(`/api/resources/${id}`, { method: 'PATCH', body: JSON.stringify(body) }),
  remove: (id: string) =>
    request<void>(`/api/resources/${id}`, { method: 'DELETE' }),
};
```

```ts
// lib/query-keys.ts
export const queryKeys = {
  resources: {
    all: ['resources'] as const,
    list: (params?: Record<string, string>) => ['resources', 'list', params] as const,
    detail: (id: string) => ['resources', 'detail', id] as const,
  },
};
```

```ts
// features/resources/hooks/use-resources.ts
'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { resourcesApi } from '../api';
import { queryKeys } from '@/lib/query-keys';
import type { CreateResourceInput, UpdateResourceInput } from '@/lib/validations/resource';

export function useResources(params?: Record<string, string>) {
  return useQuery({
    queryKey: queryKeys.resources.list(params),
    queryFn: () => resourcesApi.getAll(params),
  });
}

export function useResource(id: string) {
  return useQuery({
    queryKey: queryKeys.resources.detail(id),
    queryFn: () => resourcesApi.getOne(id),
    enabled: !!id,
  });
}

export function useCreateResource() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: CreateResourceInput) => resourcesApi.create(body),
    onSuccess: () => qc.invalidateQueries({ queryKey: queryKeys.resources.all }),
  });
}

export function useUpdateResource(id: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: UpdateResourceInput) => resourcesApi.update(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.resources.all });
      qc.invalidateQueries({ queryKey: queryKeys.resources.detail(id) });
    },
  });
}

export function useDeleteResource() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => resourcesApi.remove(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: queryKeys.resources.all }),
  });
}
```

---

## 6. Paginated List Component

```tsx
// features/resources/components/resource-list.tsx
'use client';

import { useState } from 'react';
import { useResources } from '../hooks/use-resources';
import { ResourceCard } from './resource-card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';

export function ResourceList() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');

  const { data, isLoading, isError } = useResources({
    page: String(page),
    limit: '20',
    ...(search && { search }),
  });

  if (isLoading) return <div className="animate-pulse">불러오는 중...</div>;
  if (isError) return <div className="text-destructive">오류가 발생했습니다.</div>;

  return (
    <div className="space-y-4">
      <Input
        placeholder="검색..."
        value={search}
        onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        className="max-w-sm"
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {data?.items.map((item) => (
          <ResourceCard key={item.id} resource={item} />
        ))}
      </div>

      {data && data.totalPages > 1 && (
        <div className="flex items-center gap-2">
          <Button variant="outline" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            이전
          </Button>
          <span className="text-sm text-muted-foreground">
            {page} / {data.totalPages}
          </span>
          <Button variant="outline" disabled={page >= data.totalPages} onClick={() => setPage((p) => p + 1)}>
            다음
          </Button>
        </div>
      )}
    </div>
  );
}
```

---

## 7. TanStack Query Provider Setup

```tsx
// app/providers.tsx
'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { useState } from 'react';

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 60 * 1000,
            retry: 1,
          },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      {children}
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  );
}
```

```tsx
// app/layout.tsx
import { Providers } from './providers';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
```

---

## 8. Vitest + Testing Library Component Test

```tsx
// features/resources/components/resource-card.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ResourceCard } from './resource-card';

const mockResource = {
  id: '1',
  title: '테스트 리소스',
  description: '설명입니다',
  status: 'active' as const,
  createdAt: new Date().toISOString(),
};

describe('ResourceCard', () => {
  it('제목을 렌더링한다', () => {
    render(<ResourceCard resource={mockResource} />);
    expect(screen.getByText('테스트 리소스')).toBeInTheDocument();
  });

  it('설명을 렌더링한다', () => {
    render(<ResourceCard resource={mockResource} />);
    expect(screen.getByText('설명입니다')).toBeInTheDocument();
  });

  it('active 상태 배지를 표시한다', () => {
    render(<ResourceCard resource={mockResource} />);
    expect(screen.getByText('active')).toBeInTheDocument();
  });
});
```

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
    globals: true,
  },
});
```

```ts
// vitest.setup.ts
import '@testing-library/jest-dom';
```
