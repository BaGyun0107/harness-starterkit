# dev-liveview

> oh-my-agent(도메인 스킬) + gstack(워크플로우/리뷰/배포)

## Commit Convention

커밋 메시지 형식: `<type>: <한글 설명>`

- **description은 반드시 한글로 작성**
- type 접두사만 영문 사용

```
feat: 로그인 페이지 구현
fix: 토큰 만료 시 리다이렉트 안 되는 문제 수정
chore: GitHub Actions 배포 파이프라인 추가
refactor: 사용자 인증 로직 분리
docs: README 모노레포 배포 설명 추가
```

Types: feat, fix, chore, refactor, docs, style, test, perf

## Language

- 코드 주석: 한글
- 커밋 메시지: 한글 (type 접두사만 영문)
- PR/이슈 제목 및 본문: 한글
- 변수명, 함수명, 파일명: 영문

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md) — 전체 도메인 맵, 레이어 구조, 데이터 흐름

### 기술 스택

- **Backend**: Express 5 + Prisma (레이어: Router → Service → Repository 엄격 분리, 인증: JWT + bcrypt)
- **Frontend**: Next.js 15 (App Router), FSD-lite (피처 간 임포트 금지), Jotai + TanStack Query, shadcn/ui + Tailwind CSS

## 레포 구조 (모노레포 직접 배포)

```
dev-{project}  ← 모노레포 1개 (개발 + 배포)
  │
  ├── apps/front/   → GitHub Actions (Vercel CLI) 직접 배포
  └── apps/back/    → GitHub Actions (SSH/PM2) 직접 배포
```

GitHub Secrets는 `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` 2개만 존재.
나머지 모든 시크릿은 Infisical (https://env.co-di.com) 에서 관리.

## 도구 역할 분담

### 워크플로우 (gstack)

| 명령어           | 역할                            | 언제 사용             |
| ---------------- | ------------------------------- | --------------------- |
| `/office-hours`  | 아이디어 검증, 전제 검증        | 새 기능/구조 설계 전  |
| `/autoplan`      | 플랜 작성 (CEO→Design→Eng 리뷰) | 구현 시작 전          |
| `/ship`          | 커밋 + PR 생성                  | 코드 완성 후          |
| `/review`        | 코드 리뷰                       | PR 전 셀프 리뷰       |
| `/codex`         | 독립적 2차 검토 (Codex)         | 중요한 변경 시        |
| `/investigate`   | 버그 근본 원인 조사             | 버그 발생 시          |
| `/qa`            | 브라우저 QA 자동화              | UI 변경 후            |
| `/design-review` | 디자인/UX 리뷰                  | UI 컴포넌트 작업 후   |
| `/setup-deploy`  | 배포 설정 구성                  | 배포 환경 변경 시     |
| `/learn`         | 프로젝트 학습 관리              | 세션 간 컨텍스트 유지 |

### 도메인 스킬 (oh-my-agent)

| 스킬             | 담당 영역                              | 작업 대상           |
| ---------------- | -------------------------------------- | ------------------- |
| `oma-backend`    | API, 인증, 미들웨어, 비즈니스 로직     | `apps/back/`        |
| `oma-frontend`   | React, Next.js, Tailwind, 컴포넌트     | `apps/front/`       |
| `oma-db`         | 스키마, 마이그레이션, ERD, 쿼리 최적화 | `apps/back/prisma/` |
| `oma-qa`         | 보안 감사, 성능 분석, 접근성 검사      | 전체                |
| `oma-translator` | 다국어 번역, 톤/스타일 보존            | UI 문자열           |

### 인프라/배포 스킬

| 명령어          | 역할                                                        | 언제 사용         |
| --------------- | ----------------------------------------------------------- | ----------------- |
| `/init-project` | 프로젝트 초기화 (스캐폴딩 + dev 레포 생성 + Infisical 연결) | 프로젝트 최초 1회 |
| `/setup`        | 환경 설정                                                   | 개발 환경 구성 시 |
| `/stack-set`    | 기술 스택 구성                                              | 스택 변경 시      |
| `/cso`          | 인프라 보안 감사 (OWASP, STRIDE)                            | 배포 전 보안 점검 |
| `/canary`       | 배포 후 카나리 모니터링                                     | 배포 직후         |

## 프로젝트 초기화 흐름

새 프로젝트를 시작할 때의 전체 흐름:

```
1. 하네스 zip 다운로드 + 압축 해제
2. apps/front/ → Next.js 초기화 (npx create-next-app)
3. apps/back/  → Express 초기화 (npm init + dependencies)
4. Infisical 프로젝트 연결 (cd apps/{front|back} && infisical init)
5. git init -b main && git add -A && git commit
6. export INFISICAL_PROJECT_ID / INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET
7. ./scripts/init-project.sh {name}
   ├── GitHub 레포 dev-{name} 1개 자동 생성
   ├── codi-engineers 팀 admin 권한 부여
   ├── GitHub Secrets INFISICAL_CLIENT_ID/SECRET 자동 등록
   ├── Git remote + main/dev 브랜치 자동 설정
   └── 첫 push → GitHub Actions 자동 배포 감지
8. 수동: Vercel 연결 (dev-{name} 레포 import, Root Directory "./")
9. 수동: Vercel Settings → Git → Disconnect
10. 수동: Infisical → Vercel Integration 활성화 (권장)
11. 수동: Infisical에 시크릿 입력
    - /backend/ (런타임 .env)
    - /backend/github-actions/ (BACK_* 배포 변수)
    - /frontend/ (Vercel 자동 동기화)
    - /frontend/github-actions/ (VERCEL_ORG_ID, VERCEL_PROJECT_ID)
```

필요 조건:

- GitHub CLI (`gh`) 로그인 상태
- Infisical CLI 로그인 (`infisical login --domain=https://env.co-di.com`)
- Infisical Machine Identity 발급 완료 (Universal Auth, Client ID/Secret)
- Vercel 팀 계정 (`ai@co-di.com` 또는 해당 팀의 VERCEL_TOKEN)

## 배포 파이프라인

### 프론트엔드 배포

```
dev-{project} apps/front/** 변경 push
  └── deploy-frontend.yml (GitHub Actions)
       ├── Infisical 로그인 (Universal Auth)
       ├── Vercel credentials 조회 (Shared-Secrets /vercel, {project} /frontend/github-actions)
       ├── Slack 시크릿 조회 (Shared-Secrets /slack)
       ├── npm ci + .next/cache 캐시
       ├── vercel pull → vercel build → vercel deploy
       └── Slack 알림 (start/end, 커밋 작성자 메타 포함)
```

### 백엔드 배포

```
dev-{project} apps/back/** 변경 push
  └── deploy-backend.yml (GitHub Actions)
       ├── Infisical 로그인 (Universal Auth)
       ├── 배포 변수 조회 ({project} /backend/github-actions)
       │   BACK_SERVER_HOST, BACK_SERVER_USER, BACK_DEPLOY_DIR,
       │   BACK_SHELL_FILE, BACK_TAR_FILE, BACK_SSH_PRIVATE_KEY
       ├── 런타임 .env 조회 ({project} /backend) → .env.${env} 생성
       ├── Slack 시크릿 조회 (Shared-Secrets /slack)
       ├── npm ci → prisma generate → build → prune
       ├── tar.gz 압축 → SCP → 서버 쉘스크립트 (PM2 restart)
       └── Slack 알림 (start/end)
```

### 환경 매핑

- `main` 브랜치 push → `prod` 환경 + production 배포
- `dev` 브랜치 push → `dev` 환경 + development 배포

### 변경 감지

`paths` 필터로 독립 배포:

- `apps/front/**`만 변경 → deploy-frontend.yml만 실행
- `apps/back/**`만 변경 → deploy-backend.yml만 실행

## Documentation

- [Design Docs](docs/design-docs/index.md) — 아키텍처 결정과 운영 원칙
- [Execution Plans](docs/exec-plans/) — 활성 및 완료된 실행 플랜
- [Product Specs](docs/product-specs/index.md) — 피처 명세
- [References](docs/references/) — LLM 최적화 외부 라이브러리 문서
- [Migration Guide](docs/MIGRATION-DIRECT-DEPLOY.md) — B방식 전환 이력 및 롤백 가이드

## Domain Guides

- [Frontend](docs/FRONTEND.md) — Next.js 15, React 19, FSD-lite, Jotai+Context (`apps/front/`)
- [Security](docs/SECURITY.md) — JWT+CSRF, 미들웨어 스택, OWASP 체크리스트

## Quality & Planning

- [Quality Score](docs/QUALITY-SCORE.md) — 도메인별 품질 등급
- [Code Review](docs/CODE-REVIEW.md) — 리뷰 기준과 체크리스트
- [Plans](docs/PLANS.md) — 플랜 작성 컨벤션

## Project Structure

```
.agents/          ← SSOT (절대 직접 수정 금지)
  skills/         ← 도메인 스킬 (oma-backend, oma-frontend, oma-db, oma-qa)
  workflows/      ← 유지된 워크플로우
  config/         ← 사용자 설정 (언어, CLI 매핑)
  results/        ← 에이전트 실행 결과
.claude/          ← Claude Code 설정
  agents/         ← 서브에이전트 정의
  hooks/          ← 워크플로우 트리거, HUD
  skills/         ← gstack(30+ 스킬) + oh-my-agent 심링크
apps/
  front/          ← 프론트엔드 (Next.js 15)
    .infisical.json
  back/           ← 백엔드 (Express 5 + Prisma)
    .infisical.json
.github/workflows/
  deploy-frontend.yml   ← apps/front/** 변경 시 Vercel CLI 배포
  deploy-backend.yml    ← apps/back/** 변경 시 SSH/PM2 배포
scripts/
  init-project.sh ← 프로젝트 초기화 (dev 레포 1개 + Infisical)
```

## Boundary Rules

**`.claude/skills/` 디렉토리의 파일을 읽거나 실행하지 마라.** 이 파일들은 Claude Code 전용 스킬 정의이며 Codex CLI와 무관하다. 이 파일들을 참조하면 잘못된 설정 파일(CLAUDE.md 등)을 생성할 수 있다. Codex CLI 스킬은 `.agents/skills/` 에서만 읽는다.

## gstack 업그레이드 규칙

`/gstack-upgrade` 실행이 완료되면, 반드시 `./scripts/sync-codex-skills.sh`를 실행하라. 이 스크립트는 Codex CLI용 gstack 스킬을 재생성한다. 이 단계를 빠뜨리면 Codex 사용자가 이전 버전의 스킬을 보게 된다.

## Quick Rules

1. **`.agents/` 직접 수정 금지** — `stack/` 디렉터리만 예외
2. **Charter Preflight 필수** — 모든 코드 작성 전 CHARTER_CHECK 출력
3. **백엔드 레이어**: Controller → Service → Repository (엄격 분리)
4. **프론트엔드 경계**: FSD-lite (피처 간 임포트 금지), 상태 = Jotai + TanStack Query
5. **보안 감사는 oma-qa** — gstack `/qa`(브라우저 자동화)와 역할이 다름
6. **시크릿 추가/변경은 Infisical에서만** — GitHub Secrets는 `INFISICAL_CLIENT_ID/SECRET` 외 건드리지 않음
7. **로컬 개발 전에 `infisical login --domain=https://env.co-di.com` 실행**

<!-- MANUAL: 수동 노트는 이 줄 아래에 -->
