# Project Rules

## Commit Convention

커밋 메시지 형식: `<type>: <한글 설명>`

- **description은 반드시 한글로 작성**
- type 접두사만 영문 사용

```
feat: 로그인 페이지 구현
fix: 토큰 만료 시 리다이렉트 안 되는 문제 수정
chore: GitHub App 기반 배포 파이프라인 추가
refactor: 사용자 인증 로직 분리
docs: README 멀티레포 파이프라인 설명 추가
```

Types: feat, fix, chore, refactor, docs, style, test, perf

## Language

- 코드 주석: 한글
- 커밋 메시지: 한글 (type 접두사만 영문)
- PR/이슈 제목 및 본문: 한글
- 변수명, 함수명, 파일명: 영문

## Architecture

- 개발은 `dev-{project}` 모노레포에서 진행
- `apps/front/` → Next.js 15 (App Router)
- `apps/back/` → Express 5 + Prisma
- main/dev push 시 `sync-repos.yml`이 자동으로 배포 레포에 동기화
- **배포 레포(front-/back-)를 직접 수정하지 않는다**

## Backend

- 레이어: Router → Service → Repository (엄격 분리)
- ORM: Prisma
- 인증: JWT + bcrypt

## Frontend

- 구조: FSD-lite (피처 간 임포트 금지)
- 상태: Jotai + TanStack Query
- UI: shadcn/ui + Tailwind CSS
