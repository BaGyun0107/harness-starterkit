/**
 * Component Template — Next.js 15 / App Router / shadcn/ui
 *
 * 피처(feature) 단위 구조 예시:
 *   features/resources/
 *     api.ts                   ← fetch 함수
 *     types.ts                 ← 타입 정의
 *     hooks/use-resources.ts   ← TanStack Query 훅
 *     components/
 *       resource-list.tsx      ← 목록 (Client Component)
 *       resource-card.tsx      ← 카드 (공유 가능)
 *       create-resource-form.tsx
 *       resource-detail.tsx
 */

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/types.ts
// ─────────────────────────────────────────────────────────────────────────────

export interface Resource {
  id: string;
  title: string;
  description?: string;
  status: 'active' | 'archived';
  createdAt: string;
  updatedAt: string;
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/api.ts
// ─────────────────────────────────────────────────────────────────────────────

import { useAuthStore } from '@/store/use-auth-store';
import type { Resource, PaginatedResult } from './types';
import type { CreateResourceInput, UpdateResourceInput } from '@/lib/validations/resource';

const BASE = process.env.NEXT_PUBLIC_API_URL ?? '';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = useAuthStore.getState().accessToken;
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });
  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || `HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
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

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/hooks/use-resources.ts
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/components/resource-card.tsx
// ─────────────────────────────────────────────────────────────────────────────

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import type { Resource } from '../types';

interface ResourceCardProps {
  resource: Resource;
  className?: string;
}

export function ResourceCard({ resource, className }: ResourceCardProps) {
  return (
    <Card className={cn('hover:shadow-md transition-shadow', className)}>
      <CardHeader className="pb-2">
        <div className="flex items-start justify-between gap-2">
          <CardTitle className="text-base line-clamp-2">{resource.title}</CardTitle>
          <Badge variant={resource.status === 'active' ? 'default' : 'secondary'}>
            {resource.status}
          </Badge>
        </div>
      </CardHeader>
      {resource.description && (
        <CardContent>
          <p className="text-sm text-muted-foreground line-clamp-3">{resource.description}</p>
        </CardContent>
      )}
    </Card>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/components/resource-list.tsx
// ─────────────────────────────────────────────────────────────────────────────

'use client';

import { useState } from 'react';
import { useResources } from '../hooks/use-resources';
import { ResourceCard } from './resource-card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Skeleton } from '@/components/ui/skeleton';

export function ResourceList() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');

  const { data, isLoading, isError } = useResources({
    page: String(page),
    limit: '20',
    ...(search && { search }),
  });

  return (
    <div className="space-y-6">
      {/* Search */}
      <Input
        placeholder="검색..."
        value={search}
        onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        className="max-w-sm"
      />

      {/* States */}
      {isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-32 rounded-lg" />
          ))}
        </div>
      )}

      {isError && (
        <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-4 text-sm text-destructive">
          데이터를 불러오는 데 실패했습니다.
        </div>
      )}

      {/* List */}
      {data && (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {data.items.map((item) => (
              <ResourceCard key={item.id} resource={item} />
            ))}
          </div>

          {data.items.length === 0 && (
            <p className="py-12 text-center text-sm text-muted-foreground">
              리소스가 없습니다.
            </p>
          )}

          {/* Pagination */}
          {data.totalPages > 1 && (
            <div className="flex items-center justify-center gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                이전
              </Button>
              <span className="text-sm text-muted-foreground">
                {page} / {data.totalPages}페이지 ({data.total}건)
              </span>
              <Button
                variant="outline"
                size="sm"
                disabled={page >= data.totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                다음
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// features/resources/components/create-resource-form.tsx
// ─────────────────────────────────────────────────────────────────────────────

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
    mutate(values, {
      onSuccess: () => {
        form.reset();
        onSuccess?.();
      },
    });
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
                <Textarea placeholder="설명 (선택)" rows={3} {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={() => form.reset()}>
            초기화
          </Button>
          <Button type="submit" disabled={isPending}>
            {isPending ? '저장 중...' : '저장'}
          </Button>
        </div>
      </form>
    </Form>
  );
}
