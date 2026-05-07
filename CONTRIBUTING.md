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
                     # 내부적으로 infisical run --env=dev --path=/backend -- tsx watch ...

# Frontend
cd apps/front
npm install
npm run dev          # http://localhost:3000
                     # 내부적으로 infisical run --env=dev --path=/frontend -- next dev
```

### Infisical 없이 실행 (긴급 시)

`.env.local` 파일을 수동으로 만들고:

```bash
cd apps/back
npm run dev:no-infisical
```

## CI/CD Pipeline

### 워크플로우 매트릭스

| 워크플로우 파일              | 대상       | 배포 방식    | SSH 사용 (Bastion 경유) |
| ---------------------------- | ---------- | ------------ | ----------------------- |
| `deploy-frontend-vercel.yml` | apps/front | Vercel CLI   | ❌                      |
| `deploy-frontend-pm2.yml`    | apps/front | PM2 (SSH)    | ✅                      |
| `deploy-frontend-docker.yml` | apps/front | Docker (SSH) | ✅                      |
| `deploy-backend-pm2.yml`     | apps/back  | PM2 (SSH)    | ✅                      |
| `deploy-backend-docker.yml`  | apps/back  | Docker (SSH) | ✅                      |

> **활성화 규칙**: Frontend는 vercel/pm2/docker 중 **1개만** `on: push` 활성화, Backend는 pm2/docker 중 **1개만** 활성화. 나머지는 `workflow_dispatch`만 남겨 수동 실행 전용으로 둔다. 같은 paths에 두 개가 동시 트리거되면 같은 커밋이 두 경로로 배포되어 충돌한다.

### 전체 흐름

```
dev-{project} push (main 또는 dev)
  │
  ├── apps/front/** 변경 시 → 활성화된 Frontend 워크플로우 1개 실행
  │   ├── (Vercel)  Infisical에서 VERCEL_TOKEN/ORG_ID/PROJECT_ID 조회
  │   │            → vercel pull → vercel build → vercel deploy
  │   ├── (PM2)     Infisical에서 FRONT_* 조회
  │   │            → tar.gz → SSH(Bastion 경유) → 서버 셸스크립트 (PM2 restart)
  │   └── (Docker)  Infisical에서 FRONT_* 조회
  │                → docker build/save → SSH(Bastion 경유) → docker compose up
  │
  └── apps/back/** 변경 시 → 활성화된 Backend 워크플로우 1개 실행
      ├── (PM2)     Infisical에서 BACK_* + 런타임 .env 조회
      │            → npm ci → prisma generate → build → tar.gz
      │            → SSH(Bastion 경유) → 서버 셸스크립트 (PM2 restart)
      └── (Docker)  Infisical에서 BACK_* + 런타임 .env 조회
                   → docker build/save → SSH(Bastion 경유) → docker compose up

모든 워크플로우 공통:
  - 시작/종료 Slack 알림
  - GitHub Deployment 등록 (status 업데이트)
```

### 배포 환경

- `main` push → **production** 배포
- `dev` push → **development** 배포
- `feat/*`, `fix/*` → 배포 없음 (dev 레포에서만 개발)

### 변경 감지 (독립 배포)

`paths` 필터를 사용해 변경된 앱만 배포합니다:

- `apps/front/**`만 변경 → 활성화된 Frontend 워크플로우만 실행
- `apps/back/**`만 변경 → 활성화된 Backend 워크플로우만 실행
- 둘 다 변경 → 두 워크플로우 동시 실행 (Frontend × 1, Backend × 1)

각 `.github/workflows/deploy-*.yml` 자체가 변경되면 해당 워크플로우만 트리거됩니다.

## SSH 배포 구조 (PM2/Docker 공통)

`deploy-{backend,frontend}-{pm2,docker}.yml` 4개 워크플로우는 모두 **Cloudflare Tunnel + Bastion** 구조를 통해 22포트 전역 개방 없이 SSH로 배포 서버에 접근합니다.

```
GitHub Actions
   ↓ cloudflared access ssh (Service Token)
Cloudflare Edge → Tunnel
   ↓
[Bastion 서버: vpn-1-ga-1.hipasshub.com:9806]   ← deploy 사용자 (셸 차단, ProxyJump 전용)
   ↓ ProxyJump (TCP 포워딩만)
[배포 서버 N대: 133.186.216.12:22 등]            ← rocky 사용자
```

3중 보호:

1. **Cloudflare Access Service Token** — 토큰 없으면 터널 접근 자체 차단
2. **Bastion sshd 키 인증** — 터널 통과해도 bastion `deploy` 사용자 키 없으면 차단
3. **배포 서버 sshd 키 인증** — bastion 통과해도 배포 서버에 키 없으면 차단

### 핵심 설계 원칙

- **Tunnel 1개 + bastion 1대로 다수 배포 서버를 커버** — 새 배포 서버 추가 시 Cloudflare 설정 변경 불필요
- **bastion에는 점프용 키를 두지 않는다** — ProxyJump는 클라이언트 키를 그대로 들고 다음 hop에서 다시 인증
- **bastion `deploy` 사용자는 셸 차단** — `usermod -s /usr/sbin/nologin`으로 SSH 셸을 막고 ProxyJump(TCP 포워딩)만 허용
- **`PermitOpen` 화이트리스트로 점프 대상 제한** — bastion에서 deploy 사용자가 점프 가능한 IP:포트를 명시적으로 한정

자세한 Cloudflare 셋업, bastion 셋업, 새 프로젝트/배포 서버 추가 시나리오는 [`docs/cloudflare-tunnel-ssh-guide.md`](docs/cloudflare-tunnel-ssh-guide.md) 참조.

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

스크립트 완료 후 작업 — 배포 방식에 따라 일부만 수행:

| 작업                                 | 대상                                                          | 조건/설명                                                                    |
| ------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 배포 방식 선택 + 워크플로우 활성화   | `.github/workflows/deploy-*.yml`                              | `on: push` 블록 주석/해제로 워크플로우 1개씩(front/back) 활성화              |
| Infisical 시크릿 입력 (런타임)       | `/backend/`                                                   | 백엔드 .env (DATABASE_URL, JWT_SECRET 등)                                    |
| Infisical 시크릿 입력 (런타임)       | `/frontend/`                                                  | 프론트 .env / Vercel 자동 동기화 값                                          |
| Infisical 시크릿 입력 (배포)         | `/backend/github-actions/`                                    | BACK\_\* 변수 (PM2/Docker 사용 시)                                           |
| Infisical 시크릿 입력 (배포)         | `/frontend/github-actions/`                                   | VERCEL*\* (Vercel) 또는 FRONT*\* (PM2/Docker)                                |
| **Cloudflare Tunnel + Bastion 셋업** | bastion 서버 + Cloudflare 대시보드 + Infisical Shared-Secrets | **PM2/Docker 사용 시**. 가이드 시나리오 A/B/C 따라 키 + 변수 등록            |
| Vercel 연결                          | Vercel 대시보드                                               | Vercel 사용 시. `dev-{project}` import → Settings → Git Disconnect           |
| Infisical → Vercel Integration       | Infisical UI                                                  | Vercel 사용 시 권장. `/frontend/` 자동 동기화                                |
| 배포 서버 사전 준비                  | 배포 서버                                                     | PM2/Docker 사용 시. Node.js + PM2/Docker + bastion IP의 22포트 인바운드 허용 |

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

나머지 모든 시크릿(SSH 키, Cloudflare 토큰, Slack, 서버 정보, 런타임 .env 등)은 **Infisical에서 관리**합니다.

## Infisical 시크릿 경로 구조

```
프로젝트 {project}
├── dev 환경
│   ├── /backend/                          런타임 .env
│   │   ├── DATABASE_URL
│   │   ├── JWT_SECRET
│   │   └── ...
│   ├── /backend/github-actions/           배포 변수 (PM2/Docker 사용 시)
│   │   ├── BACK_SSH_TUNNEL_HOST           bastion hostname (= vpn-1-ga-1.hipasshub.com)
│   │   ├── BACK_BASTION_USER              bastion 사용자 (= deploy)
│   │   ├── BACK_BASTION_PORT              bastion sshd 포트 (= 9806)
│   │   ├── BACK_TARGET_HOST               배포 서버 IP
│   │   ├── BACK_TARGET_PORT               배포 서버 sshd 포트 (= 22)
│   │   ├── BACK_SERVER_USER               배포 서버 사용자 (= rocky)
│   │   ├── BACK_SSH_PRIVATE_KEY           프로젝트별 SSH 개인키
│   │   ├── BACK_DEPLOY_DIR                배포 작업 디렉터리
│   │   ├── BACK_APP_NAME                  PM2 앱 이름 (PM2 방식)
│   │   ├── BACK_TAR_FILE                  빌드 산출물 파일명 (PM2 방식)
│   │   └── BACK_APP_TYPE                  pm2 (선택, 기본 pm2)
│   ├── /frontend/                         런타임 / Vercel 자동 동기화 env
│   │   └── NEXT_PUBLIC_* 등
│   └── /frontend/github-actions/          배포 변수
│       ├── (Vercel 사용 시)
│       │   ├── VERCEL_ORG_ID
│       │   └── VERCEL_PROJECT_ID
│       └── (PM2/Docker 사용 시)
│           └── FRONT_* (BACK_* 와 동일 구조, 변수명만 FRONT_)
└── prod 환경 (동일 구조, 운영 값)

Shared-Secrets (여러 프로젝트 공용)
├── /slack/
│   ├── slack_bot_token
│   └── slack_channel
├── /vercel/
│   └── VERCEL_TOKEN
└── /cloudflare/{domain}/{subdomain}/      도메인당 1개. 워크플로우가 자동 조회
    ├── CF_ACCESS_CLIENT_ID
    └── CF_ACCESS_CLIENT_SECRET
        예: /cloudflare/hipasshub-com/vpn-1-ga-1-token/
```

> **Cloudflare Access 토큰은 프로젝트 Infisical에 복사 금지** — 워크플로우가 `Shared-Secrets/cloudflare/{domain}/{subdomain}/`에서 자동 조회한다.

**Machine Identity 권한**: `ci-{project}-deploy` 식별자를 해당 프로젝트와 `Shared-Secrets` 프로젝트 모두에 Read 권한으로 추가.

## 서버 사전 준비

### 1. Bastion 서버 (도메인당 1대, 최초 1회만)

bastion 셋업은 **새 도메인을 도입할 때 1회만** 수행. 이후 모든 프로젝트/배포 서버는 같은 bastion을 공유한다. 자세한 절차는 [`docs/cloudflare-tunnel-ssh-guide.md`](docs/cloudflare-tunnel-ssh-guide.md) 시나리오 C 참조.

요약:

- Cloudflare Tunnel + Public Hostname (`localhost:9806` 가리킴)
- Cloudflare Access Application + Service Auth 정책 + Service Token (Infisical Shared-Secrets에 저장)
- WAF 예외 규칙 (모든 남은 규칙 건너뛰기)
- bastion 서버에 cloudflared 데몬 + sshd
- bastion에 `deploy` 사용자 + `/etc/ssh/sshd_config.d/50-deploy.conf` (`PermitOpen` + 셸 차단)

### 2. 배포 서버 (서버당 1회)

```bash
# Node.js 24 설치 (nvm 또는 nodesource)
curl -fsSL https://rpm.nodesource.com/setup_24.x | sudo bash -
sudo dnf install -y nodejs

# PM2 설치 (PM2 방식 사용 시)
npm install -g pm2

# 또는 Docker 설치 (Docker 방식 사용 시)
# 배포 디렉터리 준비
sudo mkdir -p /home/rocky && sudo chown rocky:rocky /home/rocky

# 방화벽: bastion IP에서 22 포트 인바운드 허용
sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=<BASTION_IP> port port=22 protocol=tcp accept'
sudo firewall-cmd --reload
# 클라우드 콘솔 보안그룹에서도 동일 규칙 추가

# 배포 서버 추가 시 bastion sshd config의 PermitOpen에 IP:포트 한 줄 추가 + reload
# (자세한 내용은 cloudflare-tunnel-ssh-guide.md 시나리오 B)
```

### 3. 프로젝트별 SSH 키 등록 (프로젝트당 1회)

```bash
# 로컬에서 키 페어 생성
ssh-keygen -t ed25519 -f ~/keys/{project}-deploy -C "{project}-deploy"

# 공개키를 bastion authorized_keys에 추가 (주석으로 프로젝트 표시)
# bastion에서:
echo "# project: {project} (added YYYY-MM-DD)" | sudo -u deploy tee -a /home/deploy/.ssh/authorized_keys
echo "<공개키>" | sudo -u deploy tee -a /home/deploy/.ssh/authorized_keys

# 같은 공개키를 배포 서버 authorized_keys에 추가
# 배포 서버에서:
echo "<공개키>" | sudo -u rocky tee -a /home/rocky/.ssh/authorized_keys
sudo -u rocky chmod 600 /home/rocky/.ssh/authorized_keys

# 개인키는 Infisical /backend/github-actions/ 또는 /frontend/github-actions/ 에 저장
# 변수명: BACK_SSH_PRIVATE_KEY 또는 FRONT_SSH_PRIVATE_KEY
```

### 4. 배포 셸스크립트 (서버당 1회, PM2 방식)

서버에 범용 `~/server-deploy.sh` 스크립트가 한 번만 배치되어 있어야 한다. 프로젝트/환경별 값은 워크플로우에서 인자로 전달되므로 서버 스크립트는 수정할 필요 없음.

```bash
ssh ... "sh ~/server-deploy.sh '<DEPLOY_DIR>' '<TAR_FILE>' '<APP_NAME>' '<ENV>' '<APP_TYPE>'"
```

## Directory Structure

```
dev-{project}/
├── apps/
│   ├── front/                       # Next.js 15
│   │   └── .infisical.json
│   └── back/                        # Express 5 + Prisma
│       └── .infisical.json
├── .github/workflows/
│   ├── deploy-frontend-vercel.yml   # apps/front/** → Vercel CLI
│   ├── deploy-frontend-pm2.yml      # apps/front/** → SSH(Bastion)/PM2
│   ├── deploy-frontend-docker.yml   # apps/front/** → SSH(Bastion)/Docker
│   ├── deploy-backend-pm2.yml       # apps/back/**  → SSH(Bastion)/PM2
│   └── deploy-backend-docker.yml    # apps/back/**  → SSH(Bastion)/Docker
├── scripts/
│   └── init-project.sh              # 프로젝트 초기화
├── .agents/                         # AI 에이전트 스킬
├── .claude/                         # Claude Code 설정
├── docs/
│   └── cloudflare-tunnel-ssh-guide.md   # Bastion SSH 배포 상세 가이드
├── CLAUDE.md                        # 프로젝트 규칙 (AI가 읽음)
├── CONTRIBUTING.md                  # 이 파일
└── README.md
```
