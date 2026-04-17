# Contributing Guide

## Git Workflow

```
main              ← 운영계 (Production) — 자동 배포
  └── hotfix/*    ← 긴급 수정 → main + dev 양쪽 머지
dev               ← 개발계 (Development) — 자동 배포
  └── feat/*      ← 기능 개발 → dev PR
  └── fix/*       ← 버그 수정 → dev PR
```

## Branch Rules

| Branch     | 용도        | 배포 대상   | 보호             |
| ---------- | ----------- | ----------- | ---------------- |
| `main`     | 운영 릴리스 | Production  | PR 필수, CI 통과 |
| `dev`      | 통합 테스트 | Development | CI 통과          |
| `feat/*`   | 기능 개발   | -           | -                |
| `fix/*`    | 버그 수정   | -           | -                |
| `hotfix/*` | 긴급 수정   | -           | -                |

## 개발 흐름

### 1. 기능 개발

```bash
git checkout dev
git pull origin dev
git checkout -b feat/my-feature

# 작업 후
git add <files>
git commit -m "feat: 내 기능 추가"
git push -u origin feat/my-feature

# GitHub에서 dev 브랜치로 PR 생성
```

### 2. 운영 배포

```bash
# dev → main PR 생성 (GitHub)
# 리뷰 + CI 통과 후 머지 → 자동 배포
# 릴리스 태그 생성
git tag v1.0.0
git push origin v1.0.0
```

### 3. 핫픽스

```bash
git checkout main
git checkout -b hotfix/critical-bug

# 수정 후
git push -u origin hotfix/critical-bug
# main으로 PR → 머지
# dev에도 머지 (싱크)
git checkout dev
git merge main
git push origin dev
```

## Commit Convention

```
<type>: <한글 설명>

Types:
  feat     — 새 기능
  fix      — 버그 수정
  chore    — 빌드, 설정 변경
  refactor — 리팩터링
  docs     — 문서
  style    — 포맷팅
  test     — 테스트
  perf     — 성능 개선

예시:
  feat: 로그인 페이지 구현
  fix: 토큰 만료 시 리다이렉트 안 되는 문제 수정
  chore: GitHub Actions 배포 파이프라인 추가
```

**description은 한글로 작성합니다.** type 접두사만 영문, 설명은 한글.

## Local Development

### 사전 준비 (최초 1회)

```bash
# Infisical CLI 설치
brew install infisical/get-cli/infisical

# Infisical 로그인 (도메인 필수)
infisical login --domain=https://env.co-di.com
```

### 실행

```bash
# Backend
cd apps/back
npm install
npm run dev          # http://localhost:8080

# Frontend
cd apps/front
npm install
npm run dev          # http://localhost:3000
```

`npm run dev` 하나로 **Infisical 연결 상태에 따라 자동 분기**된다 (`scripts/dev-runner.js`):

| 조건 | 동작 |
|------|------|
| Infisical CLI 설치 + 로그인 + 유효한 `.infisical.json` | `infisical run --path=/{app} -- <command>` 실행 (런타임 시크릿 주입) |
| 하나라도 미충족 | `<command>` 를 그대로 실행 (`.env.development` / `.env.production` 사용) |

즉, **최초에는 `.env.development` 로 개발**하다가 배포 시점에 Infisical 로그인 + `.infisical.json` 을 붙이면 **같은 `npm run dev` 가 자동으로 Infisical 경로로 전환**된다. 별도 `dev:no-infisical` 스크립트는 더 이상 필요하지 않다.

## CI/CD Pipeline

### 전체 흐름

```
dev-{project} push (main 또는 dev)
  │
  ├── apps/front/** 변경 시
  │   └── deploy-frontend.yml
  │        ├── Infisical에서 VERCEL_TOKEN / ORG_ID / PROJECT_ID 조회
  │        ├── vercel pull → build → deploy
  │        └── Slack 알림 (start/end)
  │
  └── apps/back/** 변경 시
      └── deploy-backend.yml
           ├── Infisical에서 BACK_* 조회 (SSH, 서버 정보)
           ├── Infisical에서 런타임 .env 조회 → .env.${env} 생성
           ├── npm ci → prisma generate → build → tar.gz
           ├── SCP → 서버 쉘스크립트 (PM2 restart)
           └── Slack 알림 (start/end)
```

### 배포 환경

- `main` push → **production** 배포
- `dev` push → **development** 배포
- `feat/*`, `fix/*` → 배포 없음 (dev 레포에서만 개발)

### 변경 감지 (독립 배포)

`paths` 필터를 사용해 변경된 앱만 배포합니다:

- `apps/front/**`만 변경 → deploy-frontend.yml만 실행
- `apps/back/**`만 변경 → deploy-backend.yml만 실행
- 둘 다 변경 → 두 워크플로우 동시 실행

`.github/workflows/deploy-*.yml` 자체가 변경되면 해당 워크플로우만 트리거됩니다.

## 새 프로젝트 초기화

### 방법 1: `/init-project` 스킬 사용 (권장)

Claude Code에서 `/init-project`를 실행하면 대화형으로 전체 과정을 안내합니다.

```bash
claude   # Claude Code 실행
# 프롬프트에서 /init-project 입력
```

스킬이 현재 상태(apps/front, apps/back 존재 여부)를 감지하고 5가지 옵션을 제시합니다:

| 옵션                  | 설명                                                            |
| --------------------- | --------------------------------------------------------------- |
| A) 전체 초기화        | front + back 보일러플레이트 병렬 생성                           |
| B) Frontend만         | Next.js 15 + FSD-lite + shadcn/ui                               |
| C) Backend만          | Express 5 + Prisma + BaseController                             |
| D) 건너뛰기           | 이미 소스 있음 → 바로 레포 생성                                 |
| **E) 기존 레포 통합** | **별도 레포를 `git subtree add`로 커밋 히스토리 보존하며 통합** |

선택 후 프로젝트명, Infisical Project ID, Machine Identity 값을 입력하면 `init-project.sh`까지 자동 실행됩니다.

#### 기존 레포 통합 시나리오 (E 옵션)

이미 front/back이 별도 레포로 운영 중인 경우:

```
/init-project
  → E) 기존 레포 통합 선택
  → 기존 레포 URL + 브랜치 입력
  → git subtree add로 apps/front/ 또는 apps/back/에 통합 (히스토리 보존)
  → Infisical 프로젝트 연결
  → dev-{project} 레포 생성 + push
  → GitHub Actions가 변경된 앱 자동 배포
```

- `git log -- apps/back/` 으로 기존 커밋 히스토리 필터링 가능
- `git blame`도 원래 커밋 기준으로 동작

### 방법 2: 수동 실행

#### 1. 하네스 다운로드 + 앱 초기화

```bash
mkdir my-project && cd my-project

# Frontend 초기화
npx create-next-app@latest apps/front --typescript --tailwind --eslint --app --src-dir --use-npm
rm -rf apps/front/.git

# Backend 초기화
cd apps/back
npm init -y
npm install express@5 prisma @prisma/client
npm install -D typescript @types/node @types/express ts-node
```

#### 2. 기존 레포 통합 (해당되는 경우)

```bash
cd my-project
git subtree add --prefix=apps/back https://github.com/org/back-my-app.git main
git subtree add --prefix=apps/front https://github.com/org/front-my-app.git main
```

#### 3. Infisical 프로젝트 연결

```bash
cd apps/back && infisical init
cd ../front && infisical init
cd ..
```

각각 `.infisical.json`이 생성됩니다.

#### 4. Git 초기화

```bash
git init -b main
git add -A
git commit -m "chore: initial commit"
```

#### 5. init-project.sh 실행

```bash
# Machine Identity 값을 미리 export
export INFISICAL_PROJECT_ID="<project-id>"
export INFISICAL_CLIENT_ID="<client-id>"
export INFISICAL_CLIENT_SECRET="<client-secret>"

./scripts/init-project.sh my-app
```

스크립트가 자동으로:

- GitHub 레포 `dev-my-app` 생성
- codi-engineers 팀 admin 권한 부여
- GitHub Secrets `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` 등록
- Git remote + main/dev 브랜치 설정 및 push

### 수동 설정 (공통)

| 작업                           | 대상                        | 설명                                             |
| ------------------------------ | --------------------------- | ------------------------------------------------ |
| Infisical 시크릿 입력          | `/backend/`                 | 백엔드 런타임 .env 값 (템플릿: `apps/back/.env.example`) |
| Infisical 시크릿 입력          | `/backend/github-actions/`  | BACK\_\* 배포 변수                               |
| Infisical 시크릿 입력          | `/frontend/`                | Vercel로 자동 동기화될 값 (템플릿: `apps/front/.env.example`) |
| Infisical 시크릿 입력          | `/frontend/github-actions/` | VERCEL_ORG_ID, VERCEL_PROJECT_ID                 |
| Vercel 연결                    | Vercel 대시보드             | `dev-my-app` 레포 import, Root Directory `./`    |
| Vercel Git Disconnect          | Vercel Settings             | GitHub Actions로 배포하므로 Git Integration 해제 |
| Infisical → Vercel Integration | Infisical UI                | `/frontend/` 경로 자동 동기화 (권장)             |
| 배포 서버 준비                 | 서버                        | Node.js, PM2, SSH authorized_keys 등록, ~/server-deploy.sh 배치 (최초 1회) |

### 개발 시작

```bash
# 코드 수정 후 push하면 paths 필터가 변경된 앱만 자동 배포
git push origin dev   # → development 환경
git push origin main  # → production 환경
```

## GitHub Secrets 정리

**모든 프로젝트에서 동일 — 오직 2개:**

| Secret                    | 설명                                          |
| ------------------------- | --------------------------------------------- |
| `INFISICAL_CLIENT_ID`     | Universal Auth Machine Identity Client ID     |
| `INFISICAL_CLIENT_SECRET` | Universal Auth Machine Identity Client Secret |

나머지 모든 시크릿(SSH 키, Slack, 서버 정보, .env 등)은 **Infisical에서 관리**합니다.

## Infisical 시크릿 경로 구조

```
프로젝트 {project}
├── dev 환경
│   ├── /backend/
│   │   ├── DATABASE_URL
│   │   ├── JWT_SECRET
│   │   └── ...
│   ├── /backend/github-actions/
│   │   ├── BACK_SERVER_HOST
│   │   ├── BACK_SERVER_USER
│   │   ├── BACK_DEPLOY_DIR
│   │   ├── BACK_APP_NAME
│   │   ├── BACK_TAR_FILE
│   │   ├── BACK_SSH_PRIVATE_KEY
│   │   └── BACK_APP_TYPE            # 선택 (pm2|static, 기본: pm2)
│   ├── /frontend/
│   │   └── NEXT_PUBLIC_* 등
│   └── /frontend/github-actions/
│       # Vercel 배포 시
│       ├── VERCEL_ORG_ID
│       ├── VERCEL_PROJECT_ID
│       # PM2/Static 배포 시 (인스턴스 서버)
│       ├── FRONT_SERVER_HOST
│       ├── FRONT_SERVER_USER
│       ├── FRONT_DEPLOY_DIR
│       ├── FRONT_APP_NAME
│       ├── FRONT_TAR_FILE
│       ├── FRONT_SSH_PRIVATE_KEY
│       └── FRONT_APP_TYPE            # pm2 (Next SSR) | static (React SPA)
└── prod 환경 (동일 구조, 운영 값)

Shared-Secrets (여러 프로젝트 공용)
├── /slack/
│   ├── slack_bot_token
│   └── slack_channel
└── /vercel/
    └── VERCEL_TOKEN
```

**Machine Identity 권한**: `ci-{project}-deploy` 식별자를 해당 프로젝트와 `Shared-Secrets` 프로젝트 모두에 Read 권한으로 추가.

## 서버 사전 준비 (배포 대상)

### 공통 (최초 1회만)

```bash
# Node.js 24 설치 (nvm 또는 nodesource)
curl -fsSL https://rpm.nodesource.com/setup_24.x | sudo bash -
sudo dnf install -y nodejs

# PM2 설치
npm install -g pm2

# SSH 공개키 등록
echo "ssh-ed25519 AAAAC3..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 범용 배포 스크립트 배치 (최초 1회만 — 모든 프로젝트가 공유)
scp scripts/server-deploy.sh rocky@<server>:~/server-deploy.sh
ssh rocky@<server> "chmod +x ~/server-deploy.sh"
```

**왜 `~/server-deploy.sh` 하나인가:** 이전에는 프로젝트/환경별로 `deploy-{project}-{env}.sh`를 복사해서 `BASE_PATH`, `TAR_FILE`, `APP_NAME`을 매번 수정해 배치했다. 이제는 워크플로우가 이 값들을 **인자로 전달**하므로 스크립트는 1개만 있으면 된다.

### 프로젝트별 (선택)

프로젝트에 배포 후 추가 처리(예: puppeteer Chrome 설치)가 필요하면 `{BASE_PATH}/post-deploy.sh`를 배치한다. 이 파일이 존재하면 `server-deploy.sh`가 자동으로 실행한다.

```bash
# 예: liveview back-dev 서버에서
cat > /home/rocky/CODI.live-view-back-dev/post-deploy.sh << 'EOF'
#!/bin/bash
# current 디렉토리에서 실행됨
npx puppeteer browsers install chrome
EOF
```

## Directory Structure

```
dev-{project}/
├── apps/
│   ├── front/              # Next.js 15
│   │   └── .infisical.json
│   └── back/               # Express 5 + Prisma
│       └── .infisical.json
├── .github/workflows/
│   ├── deploy-frontend.yml # apps/front/** 변경 시 Vercel CLI 배포
│   └── deploy-backend.yml  # apps/back/** 변경 시 SSH/PM2 배포
├── scripts/
│   └── init-project.sh     # 프로젝트 초기화
├── .agents/                # AI 에이전트 스킬
├── .claude/                # Claude Code 설정
├── docs/                   # 문서
├── CLAUDE.md               # 프로젝트 규칙 (AI가 읽음)
├── CONTRIBUTING.md         # 이 파일
└── README.md
```
