# harness

> oh-my-agent(도메인 스킬) + gstack(워크플로우/리뷰/배포)

## Architecture

[ARCHITECTURE.md](ARCHITECTURE.md) — 전체 도메인 맵, 레이어 구조, 데이터 흐름

## 도구 역할 분담

| 역할                       | 도구                                   |
| :------------------------- | :------------------------------------- |
| 아이디어 검증 / 전제 검증  | `gstack /office-hours`                 |
| 플랜 작성 (CEO→Design→Eng) | `gstack /autoplan`                     |
| 코드 리뷰 / Codex 2차 검토 | `gstack /review`, `gstack /codex`      |
| 병렬 스프린트 실행         | `gstack Conductor`                     |
| CI/CD, 커밋, PR, 배포      | `gstack /ship`, `gstack /setup-deploy` |
| 버그 조사                  | `gstack /investigate`                  |
| 브라우저 QA 자동화         | `gstack /qa`                           |
| **보안/접근성 감사**       | `oma-qa` (oh-my-agent)                 |
| **백엔드 구현**            | `oma-backend` → `apps/server/`         |
| **프론트엔드 구현**        | `oma-frontend` → `apps/front/`         |
| **DB 스키마/마이그레이션** | `oma-db` → `apps/server/prisma/`       |
| **프로젝트 초기화**        | `/deepinit` (oh-my-agent)              |

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
  agents/         ← 서브에이전트 정의
  hooks/          ← 워크플로우 트리거, HUD
apps/
  front/          ← 프론트엔드 앱 (Next.js 15 + React 19) — oma-frontend
  server/         ← 백엔드 앱 (Express 5 + Prisma + MySQL) — oma-backend
```

## Quick Rules

1. **`.agents/` 직접 수정 금지** — `stack/` 디렉터리만 예외
2. **Charter Preflight 필수** — 모든 코드 작성 전 CHARTER_CHECK 출력
3. **백엔드 레이어**: Controller → Service → Repository (엄격 분리)
4. **프론트엔드 경계**: FSD-lite (피처 간 임포트 금지), 상태 = Jotai + TanStack Query
5. **보안 감사는 oma-qa** — gstack `/qa`(브라우저 자동화)와 역할이 다름

<!-- MANUAL: 수동 노트는 이 줄 아래에 -->
