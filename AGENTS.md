# harness

> oh-my-agent(도메인 스킬) + gstack(워크플로우/리뷰/배포)

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md) — 전체 도메인 맵, 레이어 구조, 데이터 흐름

## 레포 구조 (멀티레포 파이프라인)

```
harness (공용 템플릿)
  │
  │  zip 다운로드 → init-project.sh 실행
  ▼
dev-{project}  (모노레포: 개발)
  │
  │  main/dev push → sync-repos.yml (GitHub App 토큰 자동 발급)
  │
  ├──→ front-{project}  (Vercel 자동 배포)
  └──→ back-{project}   (Docker+SCP 배포)
```

## 도구 역할 분담

### 워크플로우 (gstack)

| 명령어 | 역할 | 언제 사용 |
|--------|------|----------|
| `/office-hours` | 아이디어 검증, 전제 검증 | 새 기능/구조 설계 전 |
| `/autoplan` | 플랜 작성 (CEO→Design→Eng 리뷰) | 구현 시작 전 |
| `/ship` | 커밋 + PR 생성 | 코드 완성 후 |
| `/review` | 코드 리뷰 | PR 전 셀프 리뷰 |
| `/codex` | 독립적 2차 검토 (Codex) | 중요한 변경 시 |
| `/investigate` | 버그 근본 원인 조사 | 버그 발생 시 |
| `/qa` | 브라우저 QA 자동화 | UI 변경 후 |
| `/design-review` | 디자인/UX 리뷰 | UI 컴포넌트 작업 후 |
| `/setup-deploy` | 배포 설정 구성 | 배포 환경 변경 시 |
| `/learn` | 프로젝트 학습 관리 | 세션 간 컨텍스트 유지 |

### 도메인 스킬 (oh-my-agent)

| 스킬 | 담당 영역 | 작업 대상 |
|------|----------|----------|
| `oma-backend` | API, 인증, 미들웨어, 비즈니스 로직 | `apps/back/` |
| `oma-frontend` | React, Next.js, Tailwind, 컴포넌트 | `apps/front/` |
| `oma-db` | 스키마, 마이그레이션, ERD, 쿼리 최적화 | `apps/back/prisma/` |
| `oma-qa` | 보안 감사, 성능 분석, 접근성 검사 | 전체 |
| `oma-translator` | 다국어 번역, 톤/스타일 보존 | UI 문자열 |

### 인프라/배포 스킬

| 명령어 | 역할 | 언제 사용 |
|--------|------|----------|
| `/deepinit` | 프로젝트 초기화 (스택 선택, 구조 생성) | 프로젝트 최초 1회 |
| `/setup` | 환경 설정 | 개발 환경 구성 시 |
| `/stack-set` | 기술 스택 구성 | 스택 변경 시 |
| `/cso` | 인프라 보안 감사 (OWASP, STRIDE) | 배포 전 보안 점검 |
| `/canary` | 배포 후 카나리 모니터링 | 배포 직후 |

## 프로젝트 초기화 흐름

새 프로젝트를 시작할 때의 전체 흐름:

```
1. harness zip 다운로드 + 압축 해제
2. apps/front/ → Next.js 초기화 (npx create-next-app)
3. apps/back/  → Express 초기화 (npm init + dependencies)
4. git init -b main && git add -A && git commit
5. ./scripts/init-project.sh {name} {front-org} {back-org}
   ├── GitHub 레포 3개 자동 생성
   ├── 워크플로우 플레이스홀더 자동 치환
   ├── GitHub App 시크릿 자동 등록 (APP_ID, APP_PRIVATE_KEY)
   ├── Git remote + main/dev 브랜치 자동 설정
   └── 첫 push → sync-repos.yml → 배포 레포 동기화
6. 수동: Slack Webhook, SSH 키, 서버 정보 등록
7. 수동: Vercel에서 front-{project} 레포 연결
```

필요 조건:
- GitHub CLI (`gh`) 로그인 상태
- GitHub App private key (`.pem` 파일)
  - 기본 경로: 프로젝트 루트 `codi-repo-sync.private-key.pem` (.gitignore에 포함)
  - 또는: `GITHUB_APP_PEM=/path/to/key.pem ./scripts/init-project.sh ...`

## 배포 파이프라인

### 동기화 (dev-{project} → 배포 레포)

```
git push origin main
  └── sync-repos.yml
      ├── actions/create-github-app-token → 토큰 자동 발급 (만료 없음)
      ├── git subtree split --prefix=apps/front → front-{project}
      └── git subtree split --prefix=apps/back  → back-{project}
```

### 프론트엔드 배포

```
front-{project} push → Vercel 자동 배포
  ├── main → Production
  └── dev  → Preview
```

### 백엔드 배포

```
back-{project} push → deploy.yml (GitHub Actions)
  ├── Docker 이미지 빌드
  ├── SCP → 배포 서버 전송
  ├── docker compose up
  ├── Health check (http://localhost:8080/health)
  └── Slack 알림
```

## Documentation

- [Design Docs](docs/design-docs/index.md) — 아키텍처 결정과 운영 원칙
- [Execution Plans](docs/exec-plans/) — 활성 및 완료된 실행 플랜
- [Product Specs](docs/product-specs/index.md) — 피처 명세
- [References](docs/references/) — LLM 최적화 외부 라이브러리 문서

## Domain Guides

- [Frontend](docs/FRONTEND.md) — Next.js 15, React 19, FSD-lite, Jotai+Context (`apps/front/`)
- [Security](docs/SECURITY.md) — JWT+CSRF, 미들웨어 스택, OWASP 체크리스트
- [Reliability](docs/RELIABILITY.md) — 에러 처리 계층, 성능 기준, 테스트 커버리지

## Quality & Planning

- [Quality Score](docs/QUALITY-SCORE.md) — 도메인별 품질 등급
- [Code Review](docs/CODE-REVIEW.md) — 리뷰 기준과 체크리스트
- [Plans](docs/PLANS.md) — 플랜 작성 컨벤션
- [Tech Debt](docs/exec-plans/tech-debt-tracker.md) — 기술 부채 트래커

## Project Structure

```
.agents/          ← SSOT (절대 직접 수정 금지)
  skills/         ← 도메인 스킬 (oma-backend, oma-frontend, oma-db, oma-qa)
  workflows/      ← 유지된 워크플로우 (deepinit, stack-set, setup)
  config/         ← 사용자 설정 (언어, CLI 매핑)
  results/        ← 에이전트 실행 결과
.claude/          ← Claude Code 설정
  agents/         ← 서브에이전트 정의 (7개: backend, frontend, db, qa 등)
  hooks/          ← 워크플로우 트리거, HUD
  skills/         ← gstack(30+ 스킬) + oh-my-agent 심링크
apps/
  front/          ← 프론트엔드 (Next.js 15) → front-{project}로 동기화
  back/           ← 백엔드 (Express 5 + Prisma) → back-{project}로 동기화
.github/workflows/
  sync-repos.yml  ← subtree split → 배포 레포 push (GitHub App 토큰)
  deploy.yml      ← Docker 빌드/배포 (레거시, 로컬 개발용)
scripts/
  init-project.sh ← 프로젝트 초기화 (3개 레포 + 시크릿 자동 등록)
templates/
  back-deploy.yml ← back-{project} 배포 워크플로우 템플릿
```

## Quick Rules

1. **`.agents/` 직접 수정 금지** — `stack/` 디렉터리만 예외
2. **Charter Preflight 필수** — 모든 코드 작성 전 CHARTER_CHECK 출력
3. **백엔드 레이어**: Controller → Service → Repository (엄격 분리)
4. **프론트엔드 경계**: FSD-lite (피처 간 임포트 금지), 상태 = Jotai + TanStack Query
5. **보안 감사는 oma-qa** — gstack `/qa`(브라우저 자동화)와 역할이 다름
6. **배포 레포 직접 수정 금지** — dev-{project}에서만 작업, 동기화는 자동

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] .pem 파일을 Infisical에 보관
- [ ] SLACK_WEBHOOK_URL을 Infisical에서 관리
- [ ] CI/CD에서 GitHub Secrets → Infisical 전환
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환

<!-- MANUAL: 수동 노트는 이 줄 아래에 -->
