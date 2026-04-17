# harness

사내 공용 프로젝트 하네스. AI 에이전트 스킬, CI/CD, Git workflow, 모노레포 직접 배포 파이프라인을 포함합니다.

## 아키텍처

```
dev-{project}  ← 모노레포 1개 (개발 + 배포)
  │
  ├── apps/front/   → GitHub Actions (Vercel CLI) 직접 배포
  └── apps/back/    → GitHub Actions (SSH/PM2) 직접 배포

GitHub Secrets (오직 2개):
  - INFISICAL_CLIENT_ID
  - INFISICAL_CLIENT_SECRET

Infisical (https://env.co-di.com) ← 나머지 모든 시크릿
  프로젝트별/
    /backend/                    런타임 .env
    /backend/github-actions/     배포 변수 (BACK_*)
    /frontend/                   Vercel 자동 동기화용 env
    /frontend/github-actions/    VERCEL_ORG_ID, VERCEL_PROJECT_ID
  Shared-Secrets/
    /slack/                      slack_bot_token, slack_channel
    /vercel/                     VERCEL_TOKEN
```

## 새 프로젝트 시작하기

### 사전 준비

| 도구            | 설치                                       |
| --------------- | ------------------------------------------ |
| Node.js 24+     | `mise install` (`.mise.toml` 포함)         |
| GitHub CLI      | https://cli.github.com/                    |
| Infisical CLI   | `brew install infisical/get-cli/infisical` |
| Claude Code CLI | AI 기반 초기화 스킬 사용 시 필요           |
| bun             | gstack 빌드용 (선택)                       |

### 방법 1: `/init-project` 스킬 사용 (권장)

Claude Code에서 `/init-project`를 실행하면 대화형으로 전체 과정을 안내합니다.

```bash
# 1. 하네스 다운로드 후 디렉토리 이동
mkdir my-project && cd my-project
# zip 내용물을 여기에 복사

# 2. Claude Code 실행
claude

# 3. 프롬프트에서 /init-project 입력
```

스킬이 자동으로 수행하는 것:

1. **사전 체크** — gh CLI, Infisical CLI, 로그인 상태 확인
2. **현재 상태 감지** — `apps/front/`, `apps/back/` 존재 여부 확인
3. **초기화 옵션 선택** — 상태에 맞는 옵션 추천
4. **스캐폴딩** — oma-frontend/oma-backend 스킬 기반 프로덕션 레디 보일러플레이트 생성
5. **Infisical 프로젝트 연결** — Project ID 입력 + `.infisical.json` workspaceId 치환
6. **Machine Identity 발급 안내** — Client ID/Secret 발급 후 GitHub Secrets 자동 등록
7. **레포 생성** — `init-project.sh`로 `dev-{project}` 1개 생성
8. **완료 안내** — Vercel 연결, Infisical Integration 등 수동 작업 안내

#### 초기화 옵션

| 옵션                  | 설명                                                          |
| --------------------- | ------------------------------------------------------------- |
| A) 전체 초기화        | front + back 보일러플레이트 생성 (병렬)                       |
| B) Frontend만         | Next.js 15 + FSD-lite + shadcn/ui                             |
| C) Backend만          | Express 5 + Prisma + BaseController                           |
| D) 건너뛰기           | 이미 소스 있음 → 바로 레포 생성 단계로                        |
| **E) 기존 레포 통합** | **별도 레포의 소스를 커밋 히스토리 보존하며 모노레포로 통합** |

### 방법 2: 수동 실행

```bash
# 1. 하네스 다운로드 후 디렉토리 이동
mkdir my-project && cd my-project

# 2. Frontend 초기화
npx create-next-app@latest apps/front --typescript --tailwind --eslint --app --src-dir --use-npm
rm -rf apps/front/.git

# 3. Backend 초기화
cd apps/back
npm init -y
npm install express@5 prisma @prisma/client
npm install -D typescript @types/node @types/express ts-node

# 4. Infisical 프로젝트 연결 (대화형)
cd apps/back && infisical init && cd ../..
cd apps/front && infisical init && cd ../..

# 5. Git 초기화
git init -b main
git add -A
git commit -m "chore: initial commit"

# 6. init-project.sh 실행 (환경변수 사전 export 권장)
export INFISICAL_PROJECT_ID="<project-id>"
export INFISICAL_CLIENT_ID="<client-id>"
export INFISICAL_CLIENT_SECRET="<client-secret>"
./scripts/init-project.sh my-app
```

### 수동 설정 (공통)

스크립트 완료 후:

1. **Vercel 연결**
   - `ai@co-di.com` 계정으로 Vercel 로그인
   - New Project → `dev-{project}` 레포 선택
   - Root Directory: `./` (빈 값)
   - Framework Preset: Next.js
   - 최초 배포 후 Settings → Git → **Disconnect** (GitHub Actions로 배포하므로)

2. **Infisical 시크릿 입력**
   - `/backend/` → 백엔드 .env (DATABASE_URL, JWT_SECRET 등)
   - `/backend/github-actions/` → 배포 변수 (BACK_SERVER_HOST, BACK_SSH_PRIVATE_KEY 등)
   - `/frontend/` → Vercel로 자동 동기화될 환경변수

3. **Infisical → Vercel Integration** (권장)
   - Infisical 프로젝트 → Integrations → Vercel → Connect
   - `/frontend/` 경로를 Vercel 프로젝트에 자동 동기화

### 개발 시작

```bash
# 최초 개발: apps/{back,front}/.env.example 을 복사해서 .env.development 로 사용
cp apps/back/.env.example  apps/back/.env.development
cp apps/front/.env.example apps/front/.env.development

cd apps/front && npm run dev    # http://localhost:3000
cd apps/back && npm run dev     # http://localhost:8080

# Infisical 준비되면 로그인 1회만 하면 자동 전환 (dev-runner.js 가 감지)
# infisical login --domain=https://env.co-di.com

# 코드 push → 자동 배포
git push origin dev   # → development 환경 배포
git push origin main  # → production 환경 배포
```

> `npm run dev` 는 `scripts/dev-runner.js` 를 통해 실행된다. Infisical CLI 설치 + 로그인 +
> `.infisical.json` 유효성을 모두 만족하면 `infisical run` 으로, 하나라도 부족하면 로컬
> `.env` 로 자동 fallback 한다. `dev:no-infisical` 같은 별도 명령은 필요 없다.

## 레포 구조

```
dev-{project}/
├── apps/
│   ├── front/                  # Next.js 15 (App Router)
│   │   └── .infisical.json     # Infisical 프로젝트 연결
│   └── back/                   # Express 5 + Prisma
│       └── .infisical.json
├── .github/workflows/
│   ├── deploy-frontend.yml     # apps/front/** 변경 시 Vercel CLI 배포
│   └── deploy-backend.yml      # apps/back/** 변경 시 SSH/PM2 배포
├── scripts/
│   └── init-project.sh         # 프로젝트 초기화 (dev 레포 1개 + Infisical)
├── .agents/                    # AI 에이전트 스킬 (oh-my-agent)
├── .claude/                    # Claude Code 설정 + 스킬
├── docs/                       # 문서
├── CONTRIBUTING.md             # 개발 가이드
└── README.md                   # 이 파일
```

## 배포 파이프라인 흐름

```
개발자: git push origin main (또는 dev)
         │
         ▼
GitHub Actions (paths 필터로 변경 감지)
  │
  ├── apps/front/** 변경 시
  │   └── deploy-frontend.yml
  │        ├── Infisical에서 VERCEL_TOKEN / ORG_ID / PROJECT_ID 조회
  │        ├── vercel pull → vercel build → vercel deploy
  │        └── Slack 알림 (start/end)
  │
  └── apps/back/** 변경 시
      └── deploy-backend.yml
           ├── Infisical에서 BACK_* + 런타임 .env 조회
           ├── npm ci → prisma generate → build → prune
           ├── tar.gz → SCP → 서버 쉘스크립트 실행 (PM2 restart)
           └── Slack 알림 (start/end)
```

## Git Workflow

```
main    → 운영계 자동 배포 (production)
dev     → 개발계 자동 배포 (development)
feat/*  → 기능 개발 (dev로 PR)
fix/*   → 버그 수정 (dev로 PR)
hotfix/* → 긴급 수정 (main + dev)
```

상세 브랜치 규칙과 커밋 컨벤션은 [CONTRIBUTING.md](CONTRIBUTING.md) 참조.

## 시크릿 관리 (Infisical)

### 왜 Infisical?

- GitHub Secrets는 **Client ID/Secret 2개만**으로 단순화
- 환경변수 변경 시 GitHub Actions 재배포 불필요 (Infisical에서 즉시 반영)
- 팀원 온보딩 시 `.env` 파일 공유 불필요 (`infisical login`으로 자동 주입)
- dev/prod 환경 분리가 Infisical UI에서 가능

### 경로 구조

```
Infisical Project: {project}
  ├── dev 환경
  │   ├── /backend/            DATABASE_URL, JWT_SECRET, ...
  │   ├── /backend/github-actions/
  │   │   ├── BACK_SERVER_HOST
  │   │   ├── BACK_SERVER_USER
  │   │   ├── BACK_DEPLOY_DIR
  │   │   ├── BACK_APP_NAME
  │   │   ├── BACK_TAR_FILE
  │   │   ├── BACK_SSH_PRIVATE_KEY
  │   │   └── BACK_APP_TYPE            ← 선택 (pm2|static, 기본: pm2)
  │   ├── /frontend/            NEXT_PUBLIC_*, ...
  │   └── /frontend/github-actions/
  │       ├── VERCEL_ORG_ID            ← Vercel 배포 시
  │       ├── VERCEL_PROJECT_ID        ← Vercel 배포 시
  │       ├── FRONT_SERVER_HOST        ← PM2/Static 배포 시
  │       ├── FRONT_SERVER_USER        ← PM2/Static 배포 시
  │       ├── FRONT_DEPLOY_DIR         ← PM2/Static 배포 시
  │       ├── FRONT_APP_NAME           ← PM2/Static 배포 시
  │       ├── FRONT_TAR_FILE           ← PM2/Static 배포 시
  │       ├── FRONT_SSH_PRIVATE_KEY    ← PM2/Static 배포 시
  │       └── FRONT_APP_TYPE           ← PM2/Static 배포 시 (pm2: Next SSR, static: React SPA)
  └── prod 환경 (동일 키, 운영 값)

Shared-Secrets 프로젝트 (여러 프로젝트 공용)
  ├── /slack/     slack_bot_token, slack_channel
  └── /vercel/    VERCEL_TOKEN
```

## 주요 Claude Code 스킬

| 명령어          | 역할                                                    |
| --------------- | ------------------------------------------------------- |
| `/init-project` | 프로젝트 초기화 (스캐폴딩 + 레포 생성 + Infisical 연결) |
| `/office-hours` | 아이디어 검증                                           |
| `/autoplan`     | 자동 플랜 수립                                          |
| `/ship`         | 커밋 + PR 생성                                          |
| `/qa`           | 브라우저 QA 테스트                                      |
| `/investigate`  | 버그 조사                                               |

## 요구사항

- Node.js 24+
- GitHub CLI (`gh`)
- Infisical CLI (로컬 개발)
- Claude Code CLI (선택, 초기화 스킬 사용 시)

## 참고 레포

- [Gstack](https://github.com/garrytan/gstack)
- [oh-my-agent](https://github.com/first-fluke/oh-my-agent)
