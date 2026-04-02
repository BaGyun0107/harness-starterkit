---
name: init-project
description: |
  프로젝트 초기화 오케스트레이터. 새 프로젝트의 frontend(Next.js), backend(Express) 환경을
  자동으로 구축하고, GitHub 레포 3개(dev-/front-/back-)를 생성하는 전체 프로세스를 실행한다.
  "프로젝트 초기화", "새 프로젝트 만들기", "init project", "프로젝트 세팅", "프로젝트 셋업",
  "환경 설정", "boilerplate", "스캐폴딩" 등의 맥락에서 이 스킬을 사용한다.
  이미 소스코드가 있는 프로젝트에서도 레포 생성만 수행할 수 있다.
---

# /init-project — 프로젝트 초기화 오케스트레이터

새 프로젝트를 처음부터 끝까지 자동으로 셋업하는 스킬.
팀원이 이 스킬 하나만 실행하면 개발을 바로 시작할 수 있는 상태가 된다.

## 전체 플로우

```
/init-project
  │
  ├── Step 1: 현재 상태 감지 (apps/front, apps/back 존재 여부)
  │
  ├── Step 2: AskUserQuestion (초기화 옵션 선택)
  │   ├── A) 전체 초기화 (front + back)
  │   ├── B) frontend만 설정
  │   ├── C) backend만 설정
  │   └── D) 초기환경 건너뛰기 (이미 소스 있음)
  │
  ├── Step 3: 선택에 따라 스캐폴딩 실행
  │   ├── Frontend → 서브에이전트: oma-frontend 스킬 기반 초기화
  │   ├── Backend  → 서브에이전트: oma-backend 스킬 기반 초기화
  │   └── (A 선택 시 병렬 실행)
  │
  ├── Step 4: AskUserQuestion (프로젝트 정보 수집)
  │   ├── project-name
  │   ├── front-org (front가 있는 경우만)
  │   └── back-org (back이 있는 경우만)
  │
  ├── Step 5: Git 초기화 (필요한 경우)
  │
  └── Step 6: scripts/init-project.sh 실행 (구성에 맞는 레포만 생성)
```

## 레포 생성 모드 결정

Step 1~3의 결과로 **최종적으로 프로젝트에 포함된 앱**을 기준으로 레포 생성 모드를 결정한다:

| apps/front/ 존재 | apps/back/ 존재 | 모드 | 생성되는 레포 |
|---|---|---|---|
| O | O | `full` | dev-{name}, front-{name}, back-{name} |
| O | X | `front-only` | dev-{name}, front-{name} |
| X | O | `back-only` | dev-{name}, back-{name} |

- **dev 레포는 항상 생성된다** (모노레포 역할)
- front가 없으면 front 레포를 생성하지 않고, front-org도 질문하지 않는다
- back이 없으면 back 레포를 생성하지 않고, back-org도 질문하지 않는다

## Step 1: 현재 상태 감지

프로젝트 루트에서 다음을 확인한다:

```bash
# 디렉토리 존재 + package.json 유무로 판단
FRONT_EXISTS=false
BACK_EXISTS=false
[ -f "apps/front/package.json" ] && FRONT_EXISTS=true
[ -f "apps/back/package.json" ] && BACK_EXISTS=true
echo "FRONT: $FRONT_EXISTS, BACK: $BACK_EXISTS"
```

감지 결과에 따라 Step 2의 옵션을 조정한다:
- 둘 다 있음 → D(건너뛰기)를 기본 추천하고, 바로 Step 4로 갈지 물어본다
- 하나만 있음 → 없는 쪽만 설정하도록 추천
- 둘 다 없음 → A(전체)를 기본 추천

## Step 2: 초기화 옵션 선택

AskUserQuestion으로 아래 옵션을 제시한다.
감지 결과를 포함해서 현재 상태를 알려준다.

**중요: AskUserQuestion의 각 option에 반드시 label과 description을 모두 채워야 한다.**
- label: 옵션 이름 (예: "전체 초기화 (front + back)")
- description: 해당 옵션이 무엇을 하는지 구체적으로 설명

```
question: "현재 상태:\n  apps/front/: {있음|없음}\n  apps/back/:  {있음|없음}\n\n프로젝트 초기화 옵션을 선택해주세요."
header: "초기화 옵션"
options:
  - label: "전체 초기화 (front + back)"
    description: "oma-frontend, oma-backend 스킬 기반으로 아키텍처, 유틸, 공용함수까지 포함된 프로덕션 레디 보일러플레이트를 생성합니다"
  - label: "Frontend만 설정"
    description: "Next.js 15 + FSD-lite + shadcn/ui + TanStack Query + api-client 구조를 생성합니다"
  - label: "Backend만 설정"
    description: "Express 5 + Prisma + BaseController + 미들웨어 스택 + 인증 시스템 + 유틸리티를 생성합니다"
  - label: "초기환경 건너뛰기"
    description: "이미 소스코드가 있는 경우. 바로 GitHub 레포 생성 단계로 넘어갑니다"
```

감지 결과에 따라 Recommended 표시:
- 둘 다 있음 → "초기환경 건너뛰기 (Recommended)"
- front만 없음 → "Frontend만 설정 (Recommended)"
- back만 없음 → "Backend만 설정 (Recommended)"
- 둘 다 없음 → "전체 초기화 (Recommended)"

## Step 3: 스캐폴딩 실행

선택에 따라 서브에이전트를 실행한다. A 선택 시 **병렬**로 실행한다.

### Frontend 초기화 (서브에이전트)

서브에이전트에게 다음 프롬프트를 전달한다:

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

7. proxy.ts 파일을 생성한다 (Next.js 16+ 프록시 설정용, 백엔드 API 프록시).

완료 후 npm run dev로 정상 기동되는지 확인한다.
```

### Backend 초기화 (서브에이전트)

서브에이전트에게 다음 프롬프트를 전달한다:

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

6. prisma/schema.prisma를 생성한다:
   - User 모델 (CUID, soft delete)
   - 기본 설정 (mysql, utf8mb4)

7. .env.example을 생성한다 (config-reference.md 기반).

8. package.json scripts를 설정한다:
   - dev: tsx watch src/server.ts
   - build: tsc
   - start: node dist/server.js
   - test: vitest run
   - prisma:migrate: prisma migrate dev
   - prisma:generate: prisma generate

완료 후 모든 import 경로가 올바른지, TypeScript 에러가 없는지 확인한다.
```

## Step 4: 프로젝트 정보 수집

프로젝트 구성(front 존재 여부, back 존재 여부)에 따라 **필요한 정보만** 수집한다.

### 4-1. 프로젝트 이름 (항상 질문)

AskUserQuestion으로 프로젝트 이름을 입력받는다.
현재 디렉토리명을 기본 옵션으로 제시한다.

```
question: "프로젝트 이름을 입력해주세요. (예: my-app → dev-my-app, front-my-app, back-my-app 레포가 생성됩니다)"
header: "프로젝트명"
options:
  - label: "{현재 디렉토리명}"
    description: "현재 디렉토리명 기반으로 레포를 생성합니다"
  - label: "직접 입력"
    description: "Other를 선택하고 프로젝트 이름을 입력하세요 (예: my-app)"
```

### 4-2. Organization 질문 (구성에 따라 다름)

**apps/front/가 있고 apps/back/도 있는 경우 (full 모드):**
AskUserQuestion 1회로 front-org와 back-org를 동시에 질문한다.

```
questions:
  - question: "Front 레포가 생성될 GitHub Organization을 선택해주세요"
    header: "Front Org"
    options:
      - label: "CODIWORKS-Vercel (Recommended)"
        description: "front-{name} 레포가 CODIWORKS-Vercel Org에 생성됩니다"
      - label: "직접 입력"
        description: "Other를 선택하고 Organization 이름을 입력하세요"
  - question: "Back/Dev 레포가 생성될 GitHub Organization을 선택해주세요"
    header: "Back Org"
    options:
      - label: "CODIWORKS-Engineer (Recommended)"
        description: "dev-{name}, back-{name} 레포가 CODIWORKS-Engineer Org에 생성됩니다"
      - label: "직접 입력"
        description: "Other를 선택하고 Organization 이름을 입력하세요"
```

**apps/front/만 있는 경우 (front-only 모드):**
front-org와 dev-org만 질문한다. back-org는 질문하지 않는다.

```
questions:
  - question: "Front 레포가 생성될 GitHub Organization을 선택해주세요"
    header: "Front Org"
    options:
      - label: "CODIWORKS-Vercel (Recommended)"
        description: "front-{name} 레포가 CODIWORKS-Vercel Org에 생성됩니다"
      - label: "직접 입력"
        description: "Other를 선택하고 Organization 이름을 입력하세요"
  - question: "Dev 레포가 생성될 GitHub Organization을 선택해주세요"
    header: "Dev Org"
    options:
      - label: "CODIWORKS-Engineer (Recommended)"
        description: "dev-{name} 레포가 CODIWORKS-Engineer Org에 생성됩니다"
      - label: "직접 입력"
        description: "Other를 선택하고 Organization 이름을 입력하세요"
```

**apps/back/만 있는 경우 (back-only 모드):**
back-org만 질문한다. front-org는 질문하지 않는다. dev 레포도 같은 org에 생성된다.

```
questions:
  - question: "Back/Dev 레포가 생성될 GitHub Organization을 선택해주세요"
    header: "Back Org"
    options:
      - label: "CODIWORKS-Engineer (Recommended)"
        description: "dev-{name}, back-{name} 레포가 CODIWORKS-Engineer Org에 생성됩니다"
      - label: "직접 입력"
        description: "Other를 선택하고 Organization 이름을 입력하세요"
```

사용자가 기본값(Recommended)을 선택하면 해당 Org 이름을 사용한다.
Other를 선택한 경우 입력된 텍스트를 Org 이름으로 사용한다.

## Step 5: Git 초기화

Git이 초기화되어 있지 않으면 초기화한다:

```bash
if [ ! -d ".git" ]; then
  git init -b main
  git add -A
  git commit -m "chore: 프로젝트 초기 설정"
fi
```

이미 Git이 있지만 커밋되지 않은 변경사항이 있으면 커밋한다:

```bash
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "chore: 프로젝트 초기 환경 설정 완료"
fi
```

## Step 6: init-project.sh 실행

수집한 정보와 레포 생성 모드에 따라 스크립트를 실행한다:

```bash
# full 모드 (front + back 모두 존재)
./scripts/init-project.sh {project-name} --mode full --front-org {front-org} --back-org {back-org}

# front-only 모드 (front만 존재)
./scripts/init-project.sh {project-name} --mode front-only --front-org {front-org} --back-org {dev-org}

# back-only 모드 (back만 존재)
./scripts/init-project.sh {project-name} --mode back-only --back-org {back-org}
```

- `--mode`: `full` | `front-only` | `back-only`
- `--front-org`: front 레포가 생성될 Organization (front-only, full 모드에서 필수)
- `--back-org`: back/dev 레포가 생성될 Organization (항상 필수 — dev 레포도 여기에 생성)

실행 전 사전 조건을 확인한다:
1. `gh auth status` — GitHub CLI 로그인 상태
2. `.pem` 파일 존재 (프로젝트 루트 `codi-repo-sync.private-key.pem`)
3. 대상 Organization에 레포 생성 권한

사전 조건이 충족되지 않으면 안내 메시지를 출력하고 중단한다.

## Step 7: 완료 안내

모든 단계가 완료되면 **실제로 생성된 레포만** 출력한다:

```
프로젝트 초기화 완료!

생성된 레포:
  - dev-{name}: https://github.com/{back-org}/dev-{name}
  - front-{name}: https://github.com/{front-org}/front-{name}    ← front가 있는 경우만
  - back-{name}: https://github.com/{back-org}/back-{name}      ← back이 있는 경우만

다음 단계:
  1. 수동 Secrets 등록 (SSH, Slack, 서버 정보)
  2. Vercel에서 front-{name} 레포 연결              ← front가 있는 경우만
  3. 개발 시작: git push origin main → 자동 동기화 → 자동 배포

로컬 개발:
  cd apps/front && npm run dev    # http://localhost:3000   ← front가 있는 경우만
  cd apps/back && npm run dev     # http://localhost:8080   ← back이 있는 경우만
```

## 주의사항

- Step 3의 서브에이전트는 `frontend-engineer`, `backend-engineer` 타입을 사용한다.
- 서브에이전트가 스킬 파일을 **반드시 먼저 읽은 후** 코드를 생성하도록 프롬프트에 명시한다.
- A 옵션(전체 초기화) 선택 시 front/back 서브에이전트를 **병렬로** 실행한다.
- 이미 존재하는 디렉토리를 덮어쓰지 않는다. 존재하면 해당 스캐폴딩을 건너뛴다.
- init-project.sh 실행 전 반드시 모든 파일을 커밋한다.
