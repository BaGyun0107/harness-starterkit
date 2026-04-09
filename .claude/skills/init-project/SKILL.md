---
name: init-project
description: |
  프로젝트 초기화 오케스트레이터. 새 프로젝트의 frontend(Next.js), backend(Express) 환경을
  자동으로 구축하고, GitHub 레포 3개(dev-/front-/back-)를 생성하는 전체 프로세스를 실행한다.
  "프로젝트 초기화", "새 프로젝트 만들기", "init project", "프로젝트 세팅", "프로젝트 셋업",
  "환경 설정", "boilerplate", "스캐폴딩" 등의 맥락에서 이 스킬을 사용한다.
  이미 소스코드가 있는 프로젝트에서도 레포 생성만 수행할 수 있다.
  이미 dev-{project} 레포가 존재하는 상태에서 기존 별도 레포를 통합하는 것도 지원한다.
---

# /init-project — 프로젝트 초기화 오케스트레이터

새 프로젝트를 처음부터 끝까지 자동으로 셋업하는 스킬.
팀원이 이 스킬 하나만 실행하면 개발을 바로 시작할 수 있는 상태가 된다.
이미 운영 중인 레포에 다른 레포를 통합하는 시나리오도 지원한다.

## 전체 플로우

```
/init-project
  │
  ├── Step 0: 환경 감지 (기존 레포 상태 + git remote + GitHub 레포 존재 여부)
  │
  ├── Step 1: 현재 상태 감지 (apps/front, apps/back 존재 여부)
  │
  ├── Step 2: AskUserQuestion (초기화 옵션 선택)
  │   ├── A) 전체 초기화 (front + back)
  │   ├── B) frontend만 설정
  │   ├── C) backend만 설정
  │   ├── D) 초기환경 건너뛰기 (이미 소스 있음)
  │   └── E) 기존 레포 통합 (import)
  │
  ├── Step 3: 선택에 따라 스캐폴딩 또는 import 실행
  │   ├── A~C → 서브에이전트: oma-frontend/oma-backend 스킬 기반 초기화
  │   └── E   → git subtree add로 기존 레포 통합
  │
  ├── Step 4: 프로젝트 정보 수집 (또는 기존 remote에서 추론)
  │   ├── 기존 레포 있음 → remote에서 추론 후 확인만
  │   └── 신규 → project-name, front-org, back-org 질문
  │
  ├── Step 5: Git 초기화 (필요한 경우)
  │
  └── Step 6: scripts/init-project.sh 실행 (구성에 맞는 레포만 생성)
```

## Step 0: 환경 감지 (기존 레포 상태)

**이 단계는 Step 1보다 먼저 실행된다.** 이미 운영 중인 dev-{project}에서 실행되는 경우를 감지한다.

```bash
# 1. git remote 확인
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
# 예: https://github.com/CODIWORKS-Engineer/dev-my-app.git

# 2. remote URL에서 정보 추출
if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+)/dev-([^/.]+)(\.git)?$ ]]; then
  DETECTED_ORG="${BASH_REMATCH[1]}"     # CODIWORKS-Engineer
  DETECTED_PROJECT="${BASH_REMATCH[2]}" # my-app
  EXISTING_DEV_REPO=true
else
  EXISTING_DEV_REPO=false
fi

# 3. GitHub에 배포 레포가 이미 존재하는지 확인
FRONT_REPO_EXISTS=false
BACK_REPO_EXISTS=false
if [ "$EXISTING_DEV_REPO" = true ]; then
  gh repo view "${DETECTED_ORG}/front-${DETECTED_PROJECT}" &>/dev/null && FRONT_REPO_EXISTS=true
  gh repo view "${DETECTED_ORG}/back-${DETECTED_PROJECT}" &>/dev/null && BACK_REPO_EXISTS=true
  # 다른 org도 체크 (front가 다른 org에 있을 수 있음)
  # sync-repos.yml에서 FRONT_ORG를 파싱하여 확인
  if [ -f ".github/workflows/sync-repos.yml" ]; then
    SYNC_FRONT_ORG=$(grep -oP '(?<=/)front-' .github/workflows/sync-repos.yml | head -1 || true)
  fi
fi

echo "기존 dev 레포: $EXISTING_DEV_REPO"
echo "감지된 org: $DETECTED_ORG"
echo "감지된 프로젝트: $DETECTED_PROJECT"
echo "front 배포 레포: $FRONT_REPO_EXISTS"
echo "back 배포 레포: $BACK_REPO_EXISTS"
```

감지 결과는 이후 모든 Step에서 참조된다.

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
- 하나만 있음 → 없는 쪽만 설정하도록 추천 **+ E(기존 레포 통합)도 함께 추천**
- 둘 다 없음 → A(전체)를 기본 추천

## Step 2: 초기화 옵션 선택

AskUserQuestion으로 아래 옵션을 제시한다.
**Step 0과 Step 1의 감지 결과를 모두 포함해서** 현재 상태를 알려준다.

**중요: AskUserQuestion의 각 option에 반드시 label과 description을 모두 채워야 한다.**
- label: 옵션 이름 (예: "전체 초기화 (front + back)")
- description: 해당 옵션이 무엇을 하는지 구체적으로 설명

### 기존 dev 레포가 있고, 한쪽만 존재하는 경우의 질문 예시

```
question: "현재 상태:\n  apps/front/: 있음\n  apps/back/:  없음\n  dev 레포: CODIWORKS-Engineer/dev-my-app (감지됨)\n  back 배포 레포: 없음\n\n프로젝트 초기화 옵션을 선택해주세요."
header: "초기화 옵션"
options:
  - label: "기존 레포 통합 (import) (Recommended)"
    description: "별도 back 레포의 소스를 커밋 히스토리 보존하며 apps/back/으로 통합합니다. 통합 후 back-my-app 배포 레포도 자동 생성됩니다."
  - label: "Backend만 새로 설정"
    description: "Express 5 + Prisma + BaseController + 미들웨어 스택 + 인증 시스템 + 유틸리티를 새로 생성합니다"
  - label: "초기환경 건너뛰기"
    description: "소스코드 변경 없이 GitHub 레포 생성 단계로 넘어갑니다"
```

### 신규 프로젝트의 질문 예시

```
question: "현재 상태:\n  apps/front/: 없음\n  apps/back/:  없음\n  dev 레포: 없음 (신규)\n\n프로젝트 초기화 옵션을 선택해주세요."
header: "초기화 옵션"
options:
  - label: "전체 초기화 (front + back) (Recommended)"
    description: "oma-frontend, oma-backend 스킬 기반으로 아키텍처, 유틸, 공용함수까지 포함된 프로덕션 레디 보일러플레이트를 생성합니다"
  - label: "Frontend만 설정"
    description: "Next.js 15 + FSD-lite + shadcn/ui + TanStack Query + api-client 구조를 생성합니다"
  - label: "Backend만 설정"
    description: "Express 5 + Prisma + BaseController + 미들웨어 스택 + 인증 시스템 + 유틸리티를 생성합니다"
  - label: "초기환경 건너뛰기"
    description: "이미 소스코드가 있는 경우. 바로 GitHub 레포 생성 단계로 넘어갑니다"
  - label: "기존 레포 통합 (import)"
    description: "이미 front/back이 별도 레포로 존재하는 경우. git subtree add로 커밋 히스토리를 보존하며 모노레포로 통합합니다"
```

### 추천 로직 (Step 0 + Step 1 결합)

| 기존 dev 레포 | front 존재 | back 존재 | 추천 |
|---------------|-----------|----------|------|
| 없음 | X | X | A) 전체 초기화 |
| 없음 | O | X | C) Backend만 설정, E) 기존 레포 통합 |
| 없음 | X | O | B) Frontend만 설정, E) 기존 레포 통합 |
| 없음 | O | O | D) 건너뛰기 |
| **있음** | **O** | **X** | **E) 기존 레포 통합 (Recommended)** |
| **있음** | **X** | **O** | **E) 기존 레포 통합 (Recommended)** |
| 있음 | O | O | D) 건너뛰기 |
| 있음 | X | X | A) 전체 초기화 |

**핵심: 기존 dev 레포가 있고 한쪽만 존재하면, E 옵션을 최우선 추천한다.**

## Step 3: 스캐폴딩 또는 Import 실행

선택에 따라 분기한다.

### A~C 선택: 스캐폴딩 (기존과 동일)

A 선택 시 **병렬**로 실행한다.

#### Frontend 초기화 (서브에이전트)

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

#### Backend 초기화 (서브에이전트)

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

### E 선택: 기존 레포 통합 (Import)

#### E-1. Import 대상 확인

Step 0과 Step 1의 결과를 기반으로, **어느 쪽을 import할지 자동 판단**한다.

| front 존재 | back 존재 | import 대상 |
|-----------|----------|------------|
| O | X | back만 import |
| X | O | front만 import |
| X | X | 둘 다 import |

**자동 판단 결과를 사용자에게 확인받는다:**

```
# back만 import하는 경우 예시
question: "apps/front/는 이미 존재합니다. back 레포만 import합니다.\n\nimport할 back 레포의 GitHub URL을 입력해주세요."
header: "기존 레포 통합"
options:
  - label: "직접 입력"
    description: "GitHub 레포 URL을 입력하세요 (예: https://github.com/org/back-my-app)"
```

```
# 둘 다 import하는 경우 예시 — 각각 AskUserQuestion으로 질문
question: "import할 front 레포의 GitHub URL을 입력해주세요. (없으면 '건너뛰기' 선택)"
header: "Front 레포 Import"
options:
  - label: "건너뛰기"
    description: "front는 import하지 않습니다"
  - label: "직접 입력"
    description: "GitHub 레포 URL을 입력하세요 (예: https://github.com/org/front-my-app)"
```

#### E-2. 브랜치 확인

import할 레포의 기본 브랜치를 **자동으로 감지**한다:

```bash
# GitHub API로 기본 브랜치 조회
IMPORT_BRANCH=$(gh repo view <repo-url> --json defaultBranchRef --jq '.defaultBranchRef.name')
echo "감지된 기본 브랜치: $IMPORT_BRANCH"
```

감지된 브랜치를 사용자에게 확인받는다:

```
question: "import할 브랜치를 확인해주세요."
header: "Import 브랜치"
options:
  - label: "{감지된 브랜치} (Recommended)"
    description: "레포의 기본 브랜치입니다"
  - label: "직접 입력"
    description: "다른 브랜치를 입력하세요"
```

#### E-3. 사전 체크

대상 경로가 비어있는지 확인한다:

```bash
if [ -d "apps/back" ] && [ -n "$(ls -A apps/back 2>/dev/null)" ]; then
  error "apps/back/ 가 비어있지 않습니다. import를 실행하려면 먼저 비워주세요."
  # 사용자에게 안내 후 중단
fi
```

#### E-4. git subtree add 실행

```bash
# back 레포 import 예시
git remote add import-back <back-repo-url>
git fetch import-back
git subtree add --prefix=apps/back import-back/<branch>
git remote remove import-back

# front 레포 import 예시 (해당되는 경우)
git remote add import-front <front-repo-url>
git fetch import-front
git subtree add --prefix=apps/front import-front/<branch>
git remote remove import-front
```

#### E-5. import 완료 → Step 4로 진행

import 완료 후 Step 4(프로젝트 정보 수집)로 이어진다.
**기존 dev 레포가 감지된 경우 Step 4에서 추론된 정보를 확인만 받는다.**

## Step 4: 프로젝트 정보 수집

### 4-0. 기존 레포에서 추론 (Step 0에서 감지된 경우)

**기존 dev 레포가 감지되면, 새로 질문하지 않고 추론된 정보를 확인만 받는다.**

```
question: "기존 레포에서 다음 정보를 감지했습니다. 맞으면 확인, 수정이 필요하면 직접 입력을 선택해주세요.\n\n  프로젝트명: my-app\n  Back/Dev Org: CODIWORKS-Engineer\n  Front Org: (sync-repos.yml에서 감지 또는 미감지)"
header: "프로젝트 정보 확인"
options:
  - label: "확인 (Recommended)"
    description: "감지된 정보로 진행합니다"
  - label: "직접 입력"
    description: "프로젝트명 또는 Organization을 수정합니다"
```

사용자가 "확인"을 선택하면 추론된 값을 그대로 사용한다.
"직접 입력"을 선택하면 아래 4-1, 4-2 플로우로 진행한다.

**front-org 추론 방법:**
1. `sync-repos.yml`에서 front push 대상 org 파싱
2. GitHub에서 `front-{project}` 레포 검색 (`gh repo view`)
3. 감지 실패 시 → 질문

**back-org 추론 방법:**
1. Step 0에서 origin URL의 org (= DETECTED_ORG)
2. 이미 확정

### 4-1. 프로젝트 이름 (기존 레포가 없는 경우에만 질문)

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

### 4-2. Organization 질문 (기존 레포가 없는 경우에만 질문)

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

## 레포 생성 모드 결정

Step 1~3의 결과로 **최종적으로 프로젝트에 포함된 앱**을 기준으로 레포 생성 모드를 결정한다:

| apps/front/ 존재 | apps/back/ 존재 | 모드 | 생성되는 레포 |
|---|---|---|---|
| O | O | `full` | dev-{name}, front-{name}, back-{name} |
| O | X | `front-only` | dev-{name}, front-{name} |
| X | O | `back-only` | dev-{name}, back-{name} |

- **dev 레포는 항상 생성된다** (모노레포 역할) — 이미 존재하면 건너뜀
- front가 없으면 front 레포를 생성하지 않고, front-org도 질문하지 않는다
- back이 없으면 back 레포를 생성하지 않고, back-org도 질문하지 않는다

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

**참고:** `init-project.sh`의 `create_repo_if_not_exists`는 이미 존재하는 레포를 건너뛰므로, 기존 dev 레포가 있어도 안전하게 실행된다.

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
  cd apps/back && npm run dev     # http://localhost:8080   ← back가 있는 경우만
```

## 시나리오별 플로우 요약

### 시나리오 1: 완전 신규 프로젝트

```
/init-project
  → Step 0: 기존 레포 없음
  → Step 1: front 없음, back 없음
  → Step 2: A) 전체 초기화 (Recommended)
  → Step 3: front + back 스캐폴딩 (병렬)
  → Step 4: project-name, front-org, back-org 질문
  → Step 5: git init
  → Step 6: init-project.sh --mode full
```

### 시나리오 2: 이미 소스가 있는 신규 프로젝트

```
/init-project
  → Step 0: 기존 레포 없음
  → Step 1: front 있음, back 있음
  → Step 2: D) 건너뛰기 (Recommended)
  → Step 4: project-name, front-org, back-org 질문
  → Step 5: git commit (미커밋 변경사항)
  → Step 6: init-project.sh --mode full
```

### 시나리오 3: 기존 dev 레포에 별도 back 레포 통합

```
/init-project
  → Step 0: dev-my-app 감지 (org: CODIWORKS-Engineer, project: my-app)
  → Step 1: front 있음, back 없음
  → Step 2: E) 기존 레포 통합 (Recommended) — back만 import
  → Step 3-E: back 레포 URL 입력 → 브랜치 확인 → subtree add
  → Step 4: 감지된 정보 확인 (project: my-app, org: CODIWORKS-Engineer)
  → Step 5: git commit (subtree add 이후 추가 변경사항)
  → Step 6: init-project.sh --mode full (dev/front 이미 존재 → 건너뜀, back만 생성)
```

### 시나리오 4: 기존 dev 레포에 별도 front 레포 통합

```
/init-project
  → Step 0: dev-my-app 감지
  → Step 1: front 없음, back 있음
  → Step 2: E) 기존 레포 통합 (Recommended) — front만 import
  → Step 3-E: front 레포 URL 입력 → 브랜치 확인 → subtree add
  → Step 4: 감지된 정보 확인
  → Step 6: init-project.sh --mode full (back 이미 존재 → 건너뜀, front만 생성)
```

## 주의사항

- Step 3의 서브에이전트는 `frontend-engineer`, `backend-engineer` 타입을 사용한다.
- 서브에이전트가 스킬 파일을 **반드시 먼저 읽은 후** 코드를 생성하도록 프롬프트에 명시한다.
- A 옵션(전체 초기화) 선택 시 front/back 서브에이전트를 **병렬로** 실행한다.
- 이미 존재하는 디렉토리를 덮어쓰지 않는다. 존재하면 해당 스캐폴딩을 건너뛴다.
- init-project.sh 실행 전 반드시 모든 파일을 커밋한다.
- git subtree add는 멱등하지 않음 (이미 내용이 있으면 에러) — 사전 체크 필수.
- 두 레포의 커밋이 git log에 시간순으로 뒤섞이지만, 경로 필터로 분리 추적 가능.
- 기존 레포의 기본 브랜치가 main이 아닐 수 있으므로 gh API로 자동 감지.
