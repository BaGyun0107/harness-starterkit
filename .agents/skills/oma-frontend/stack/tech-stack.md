# Frontend Agent — Tech Stack Reference (Next.js 15 / App Router)

## Framework: Next.js 15 (App Router)

- **React**: 19+
- **Router**: App Router (`app/` directory) — Server Components by default
- **Rendering**: RSC (React Server Components) + Client Components (`'use client'`)
- **Data fetching**: `fetch()` in Server Components (캐시 제어), TanStack Query in Client Components
- **Routing conventions**:
  - `app/page.tsx` — 페이지
  - `app/layout.tsx` — 레이아웃
  - `app/loading.tsx` — Suspense fallback
  - `app/error.tsx` — Error boundary
  - `app/api/` — Route Handlers (백엔드 BFF 용도)

```ts
// Server Component (default)
export default async function Page() {
  const data = await fetch('...', { next: { revalidate: 60 } });
  return <div />;
}

// Client Component
'use client';
export default function Counter() { ... }
```

## Styling: Tailwind CSS v4 + shadcn/ui

- **Tailwind v4**: CSS-first 설정 (`@import "tailwindcss"` in `app/globals.css`)
- **shadcn/ui**: `npx shadcn@latest add <component>` 로 컴포넌트 추가
- **컴포넌트 위치**: `components/ui/` (shadcn 자동 생성)
- **커스텀 컴포넌트**: `components/` 또는 FSD-lite 구조 사용
- **cn 유틸**: `lib/utils.ts`의 `cn()` (clsx + tailwind-merge)

```ts
import { cn } from '@/lib/utils';
<div className={cn('base-class', condition && 'conditional-class')} />
```

## State Management: Zustand

- **클라이언트 전역 상태**: Zustand store (`store/` 디렉터리)
- **서버 상태**: TanStack Query (캐싱, 리페칭, 뮤테이션)
- **로컬 상태**: `useState`, `useReducer`

```ts
// store/use-auth-store.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
```

## Server State: TanStack Query v5

- **Provider**: `app/providers.tsx` (Client Component) → `app/layout.tsx`에서 감쌈
- **쿼리**: `useQuery`, `useSuspenseQuery`
- **뮤테이션**: `useMutation` + `queryClient.invalidateQueries()`
- **키 관리**: `lib/query-keys.ts` 에서 중앙 관리

```ts
const { data } = useQuery({
  queryKey: queryKeys.resources.list(params),
  queryFn: () => resourcesApi.getAll(params),
});
```

## Forms: React Hook Form + Zod

- `useForm` + `zodResolver` 조합
- 스키마는 `lib/validations/` 또는 피처 폴더에 정의
- shadcn `Form` 컴포넌트와 연동

## Test: Vitest + Testing Library

- **단위/컴포넌트**: `@testing-library/react` + `vitest`
- **설정**: `vitest.config.ts` (jsdom 환경)
- **규칙**: `*.test.tsx` 파일을 소스 옆에 배치

```bash
npx vitest run
npx vitest          # watch
npx vitest --coverage
```

## Linter / Formatter

```bash
npx eslint src --ext .ts,.tsx
npx prettier --write src
```

## Project Layout (FSD-lite)

```
app/
  (auth)/
    login/page.tsx
  (dashboard)/
    layout.tsx
    page.tsx
  api/
    [...]/route.ts        # Route Handlers (BFF)
  layout.tsx
  globals.css

components/
  ui/                     # shadcn/ui 자동 생성
  common/                 # 앱 공통 컴포넌트 (Header, Sidebar 등)

features/
  resources/
    components/           # 피처 전용 컴포넌트
    hooks/                # useQuery / useMutation 래퍼
    api.ts                # fetch 함수
    types.ts

lib/
  utils.ts                # cn() 등 유틸
  query-keys.ts           # TanStack Query 키 팩토리
  validations/            # Zod 스키마

store/
  use-auth-store.ts       # Zustand 스토어

types/
  index.ts                # 글로벌 타입
```
