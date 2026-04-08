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

## 도구 역할 분담

### 워크플로우 (gstack)

| 명령어 | 역할 | 언제 사용 |
|--------|------|----------|
| `/office-hours` | 아이디어 검증, 전제 검증 | 새 기능/구조 설계 전 |
| `/autoplan` | 플랜 작성 (CEO→Design→Eng 리뷰) | 구현 시작 전 |
| `/ship` | 커밋 + PR 생성 | 코드 완성 후 |
| `/review` | 코드 리뷰 | PR 전 셀프 리뷰 |
| `/investigate` | 버그 근본 원인 조사 | 버그 발생 시 |
| `/qa` | 브라우저 QA 자동화 | UI 변경 후 |
| `/design-review` | 디자인/UX 리뷰 | UI 컴포넌트 작업 후 |
| `/learn` | 프로젝트 학습 관리 | 세션 간 컨텍스트 유지 |

### 도메인 스킬 (oh-my-agent)

| 스킬 | 담당 영역 | 작업 대상 |
|------|----------|----------|
| `oma-backend` | API, 인증, 미들웨어, 비즈니스 로직 | `apps/back/` |
| `oma-frontend` | React, Next.js, Tailwind, 컴포넌트 | `apps/front/` |
| `oma-db` | 스키마, 마이그레이션, ERD, 쿼리 최적화 | `apps/back/prisma/` |
| `oma-qa` | 보안 감사, 성능 분석, 접근성 검사 | 전체 |
| `oma-translator` | 다국어 번역, 톤/스타일 보존 | UI 문자열 |

## 배포 파이프라인

```
git push origin main
  └── sync-repos.yml
      ├── actions/create-github-app-token → 토큰 자동 발급
      ├── git subtree split --prefix=apps/front → front-{project} (Vercel 자동 배포)
      └── git subtree split --prefix=apps/back  → back-{project} (Docker+SCP 배포)
```

## Project Structure

```
.agents/          ← 도메인 스킬 SSOT
  skills/         ← oma-backend, oma-frontend, oma-db, oma-qa, oma-translator
.claude/          ← Claude Code 설정
  skills/         ← gstack(워크플로우) + oma 심링크
apps/
  front/          ← Next.js 15 → front-{project}로 동기화
  back/           ← Express 5 + Prisma → back-{project}로 동기화
.github/workflows/
  sync-repos.yml  ← subtree split → 배포 레포 push
scripts/
  init-project.sh ← 프로젝트 초기화 (레포 생성 + 시크릿 등록)
templates/
  back-deploy.yml ← back-{project} 배포 워크플로우 템플릿
```

## Boundary Rules

**`.codex/`, `.agents/skills/gstack-*/` 디렉토리의 파일을 읽거나 실행하지 마라.** 이 파일들은 Codex CLI 전용 스킬 정의이며 Claude Code와 무관하다. 이 파일들을 참조하면 잘못된 설정 파일(AGENTS.md 등)을 생성할 수 있다. Claude Code 스킬은 `.claude/skills/` 에서만 읽는다.

## gstack 업그레이드 규칙

`/gstack-upgrade` 실행이 완료되면, 반드시 `./scripts/sync-codex-skills.sh`를 실행하라. 이 스크립트는 Codex CLI용 gstack 스킬을 재생성한다. 이 단계를 빠뜨리면 Codex 사용자가 이전 버전의 스킬을 보게 된다.

## Quick Rules

1. **배포 레포 직접 수정 금지** — dev-{project}에서만 작업, 동기화는 자동
2. **백엔드 레이어 엄격 분리**: Controller → Service → Repository
3. **프론트엔드 경계**: FSD-lite (피처 간 임포트 금지)
4. **oma-backend는 `apps/back/`에서만**, **oma-frontend는 `apps/front/`에서만** 작업
