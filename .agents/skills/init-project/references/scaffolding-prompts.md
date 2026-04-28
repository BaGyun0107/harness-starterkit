# 스캐폴딩 서브에이전트 프롬프트

`/init-project` Step 3의 A~C 옵션에서 사용하는 서브에이전트 프롬프트 전문. 서브에이전트 타입은 `frontend-engineer`, `backend-engineer`를 사용한다.

**이 파일을 언제 읽는가:** Step 2에서 A/B/C 옵션이 선택된 직후. E(기존 레포 통합)나 D(건너뛰기)가 선택된 경우에는 이 파일을 로드할 필요가 없다.

**병렬 실행 규칙:** A 옵션(전체 초기화)은 frontend와 backend 서브에이전트를 **단일 메시지에 동시에** 호출하여 병렬 실행한다. B나 C는 해당 쪽 하나만 호출한다.

**왜 스킬 파일을 먼저 읽히게 하는가:** 서브에이전트가 oma-frontend/oma-backend의 아키텍처 규칙을 모르는 상태에서 코드를 생성하면 프로젝트 관례와 어긋나는 결과물이 나온다. 반드시 "스킬 파일을 먼저 읽어라"를 프롬프트 첫 단계에 명시한다.

---

## Frontend 초기화 프롬프트

`frontend-engineer` 서브에이전트에게 아래 프롬프트를 그대로 전달한다. `{PROJECT_ROOT}`는 호출 시 현재 프로젝트 루트 절대경로로 치환한다.

```
프로젝트 루트: {PROJECT_ROOT}

apps/front/ 에 Next.js 프로젝트를 초기화해야 한다.

1. 먼저 다음 스킬 참조 파일들을 읽어라:
   - .agents/skills/oma-frontend/SKILL.md (아키텍처 규칙)
   - .agents/skills/oma-frontend/stack/tech-stack.md (기술 스택 + 프로젝트 레이아웃)
   - .agents/skills/oma-frontend/resources/api-convention.md (API 호출 규칙)
   - .agents/skills/oma-frontend/stack/snippets.md (코드 패턴)

2. npx create-next-app@latest apps/front 를 실행한다:
   --typescript --tailwind --eslint --app --src-dir --use-npm

3. 스킬에 정의된 FSD-lite 구조를 생성한다:
   - src/features/ 디렉토리 구조
   - src/components/common/ 디렉토리
   - src/lib/utils.ts (cn 유틸)
   - src/lib/api-client.ts (공용 fetch 래퍼 — api-convention.md 참조)
   - src/lib/api-hooks.ts (TanStack Query 래퍼)
   - src/lib/query-keys.ts (쿼리 키 팩토리)
   - src/store/ 디렉토리
   - src/types/index.ts

4. 필수 의존성을 설치한다:
   - @tanstack/react-query, jotai (또는 zustand), luxon
   - ahooks, es-toolkit, nuqs
   - @tanstack/react-form, zod

5. shadcn/ui를 초기화한다:
   - npx shadcn@latest init
   - 기본 컴포넌트 설치: button, card, input, form, dialog, sheet, table

6. TanStack Query Provider를 app/layout.tsx에 설정한다.

7. package.json scripts 설정 (dev-runner 기반 — 단일 dev 명령):
   - dev: "node ../../scripts/dev-runner.js frontend next dev"
       → Infisical 로그인 + .infisical.json 있으면 infisical run, 없으면 그대로 next dev
       → Infisical 전환 전/후 모두 동일한 `npm run dev` 로 동작
   - build: "next build"
   - start: "next start"
   - lint:  "eslint ."
   - typecheck: "tsc --noEmit"
   - check: "npm run typecheck && npm run lint"

8. .env.example — 하네스 레포의 apps/front/.env.example 에 Next.js 용 미니멈
   템플릿이 이미 배치되어 있다. 스캐폴딩 시 이 파일이 존재하는지 확인만 하고,
   없으면 하네스 기본 템플릿을 복사한다. 프로젝트 고유 변수(예: 분석 키 등)가
   필요하면 파일 끝에 추가한다.

완료 후 npm run dev 로 정상 기동되는지 확인한다.
(Infisical 미연결 상태에서는 자동으로 로컬 .env 로 fallback 되어 동작)
```

---

## Backend 초기화 프롬프트

`backend-engineer` 서브에이전트에게 아래 프롬프트를 그대로 전달한다.

```
프로젝트 루트: {PROJECT_ROOT}

apps/back/ 에 Express + Prisma 백엔드 프로젝트를 초기화해야 한다.

1. 먼저 다음 스킬 참조 파일들을 읽어라:
   - .agents/skills/oma-backend/SKILL.md (아키텍처 규칙, 유틸리티 레퍼런스)
   - .agents/skills/oma-backend/stack/tech-stack.md (기술 스택 + 프로젝트 레이아웃)
   - .agents/skills/oma-backend/resources/middleware-reference.md (미들웨어 스택 순서)
   - .agents/skills/oma-backend/resources/auth-reference.md (3-토큰 인증 시스템)
   - .agents/skills/oma-backend/resources/config-reference.md (환경 변수 Zod 스키마)
   - .agents/skills/oma-backend/stack/snippets.md (코드 패턴)

2. 프로젝트를 초기화한다:
   cd apps/back && npm init -y

3. 의존성을 설치한다:
   - express@5, @prisma/client, prisma
   - zod, pino, pino-http, pino-pretty, pino-roll
   - helmet, cors, cookie-parser, express-rate-limit, express-slow-down
   - jsonwebtoken, bcryptjs, nanoid
   - typescript, @types/node, @types/express, @types/cors,
     @types/cookie-parser, @types/jsonwebtoken, @types/bcryptjs
   - ts-node, tsx (devDependencies)
   - vitest, supertest, @types/supertest (devDependencies)

4. tsconfig.json을 생성한다 (strict mode, paths alias).

5. 스킬에 정의된 프로젝트 구조를 생성한다:
   src/
     controllers/BaseController.ts  ← handleSuccess, handleError, validateRequest
     services/
     repositories/
     routes/
     config/unifiedConfig.ts        ← Zod 스키마로 환경변수 검증
     common/
       middleware/
         errorBoundary.ts           ← 글로벌 에러 핸들러 (반드시 마지막)
         requireAuth.ts             ← JWT + CSRF Double Submit 검증
       errors/
     utils/
       asyncErrorWrapper.ts         ← async 핸들러 에러 캐치
       logger.ts                    ← Pino 로거 (KST, 로테이션, 민감정보 마스킹)
       prisma.ts                    ← PrismaClient 싱글턴
       bcrypt.ts                    ← BcryptUtil (hash/compare)
       token.ts                     ← JWT 생성/검증, 쿠키 설정/해제
     types/
     app.ts                         ← 미들웨어 스택 (middleware-reference.md 순서대로)
     server.ts                      ← 서버 시작 + graceful shutdown

6. prisma/schema.prisma를 생성한다 (User 모델, CUID, soft delete).

7. ecosystem.config.js를 생성한다 (PM2 cluster 모드).
   → 현재 B방식의 기본 배포 경로는 deploy-backend-pm2.yml 이다.

8. Dockerfile + docker-compose.yml을 생성한다 (추후 Docker 전환 대비).
   → 현재는 deploy-backend-docker.yml이 workflow_dispatch만 활성화되어 있으므로
     사용되지 않지만, 전환 시 즉시 활용 가능하도록 파일을 미리 배치한다.

9. .env.example — 이미 하네스 레포의 apps/back/.env.example 에 미니멈 템플릿이 배포되어 있다.
   스캐폴딩 후 이 파일이 존재하는지 확인만 하고, 없으면 하네스 기본 템플릿을 복사한다.
   프로젝트 고유 변수(예: REDIS_URL, SMTP 설정 등)가 필요하면 파일 끝에 추가한다.

10. package.json scripts 설정 (dev-runner 기반 — 단일 dev 명령):
    - dev: "node ../../scripts/dev-runner.js backend tsx watch src/server.ts"
        → Infisical 로그인 + .infisical.json 있으면 infisical run, 없으면 그대로 tsx watch
        → Infisical 전환 전/후 모두 동일한 `npm run dev` 로 동작
    - build: "tsc"
    - start: "node dist/server.js"
    - test: "vitest run"
    - prisma:migrate: "prisma migrate dev"
    - prisma:generate: "prisma generate"

완료 후 모든 import 경로가 올바른지, TypeScript 에러가 없는지 확인한다.
```

---

## 프롬프트 커스터마이징 가이드

프롬프트를 수정할 때 지켜야 할 원칙:

1. **"스킬 파일을 먼저 읽어라"는 1단계에 고정.** 이 순서를 바꾸면 서브에이전트가 관례를 모르는 상태에서 코드를 쓰기 시작해 일관성이 깨진다.
2. **기술 스택 버전은 하드코딩하지 않는다.** `express@5` 같은 major 버전은 명시해도 괜찮지만 minor/patch는 명시하지 마라. `create-next-app@latest`를 쓰는 이유도 동일하다.
3. **`dev` 는 반드시 `scripts/dev-runner.js` 를 거친다.** dev-runner 가 Infisical 연결 상태를 런타임에 판단하여 자동 분기하므로, 사용자는 `npm run dev` 하나만 알면 된다. 별도 `dev:no-infisical` 스크립트는 추가하지 마라 — 중복 경로가 생기면 초기 세팅 단계에서 혼란을 준다.
4. **Docker 파일은 미리 배치한다.** 현재 PM2 방식이지만 Dockerfile/docker-compose.yml을 미리 만들어두면 전환 시 즉시 활성화 가능하다. 빈 파일도 아니고 실제로 동작 가능한 상태여야 한다.
