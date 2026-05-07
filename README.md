# dev-liveview

사내 공용 프로젝트 하네스. AI 에이전트 스킬, CI/CD, Git workflow, 모노레포 직접 배포 파이프라인을 포함합니다.

## 아키텍처

```
dev-{project}  ← 모노레포 1개 (개발 + 배포)
  │
  ├── apps/front/   → 배포 방식 1개 선택 (Vercel | PM2 | Docker)
  └── apps/back/    → 배포 방식 1개 선택 (PM2 | Docker)

GitHub Secrets (오직 2개):
  - INFISICAL_CLIENT_ID
  - INFISICAL_CLIENT_SECRET

Infisical (https://env.co-di.com) ← 나머지 모든 시크릿
  프로젝트별/
    /backend/                    런타임 .env
    /backend/github-actions/     배포 변수 (BACK_*)
    /frontend/                   런타임 / Vercel 자동 동기화 env
    /frontend/github-actions/    배포 변수 (FRONT_* 또는 VERCEL_*)
  Shared-Secrets/
    /slack/                      slack_bot_token, slack_channel
    /vercel/                     VERCEL_TOKEN
    /cloudflare/{domain}/{subdomain}/
                                 CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET
```

## SSH 배포 구조 (PM2/Docker 공통)

서버 SSH가 필요한 모든 배포 워크플로우(`deploy-{backend,frontend}-{pm2,docker}.yml`)는 **Cloudflare Tunnel + Bastion** 구조를 통해 22포트 전역 개방 없이 동작합니다.

```
GitHub Actions
   ↓ cloudflared access ssh (Service Token)
Cloudflare Edge → Tunnel
   ↓
[Bastion 서버: vpn-1-ga-1.hipasshub.com:9806]   ← deploy 사용자 (셸 차단, ProxyJump 전용)
   ↓ ProxyJump (TCP 포워딩만)
[배포 서버 N대: 133.186.216.12:22 등]            ← rocky 사용자
```

- **Tunnel 1개 + bastion 1대로 다수 배포 서버를 커버** — 새 배포 서버 추가 시 Cloudflare 설정 변경 불필요
- 새 프로젝트 추가, 새 배포 서버 추가, 새 도메인 셋업 시나리오는 [`docs/cloudflare-tunnel-ssh-guide.md`](docs/cloudflare-tunnel-ssh-guide.md) 참조

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

1. **배포 방식 선택** — Frontend는 Vercel/PM2/Docker 중 1개, Backend는 PM2/Docker 중 1개 활성화. `.github/workflows/deploy-*.yml`의 `on: push` 블록 주석 처리/해제로 전환
2. **(SSH 배포 시) Cloudflare Tunnel + Bastion 셋업** — 가이드 [`docs/cloudflare-tunnel-ssh-guide.md`](docs/cloudflare-tunnel-ssh-guide.md) 시나리오 A 따라 키 등록 + Infisical 변수 입력
3. **(Vercel 배포 시) Vercel 연결**
   - `ai@co-di.com` 계정으로 Vercel 로그인
   - New Project → `dev-{project}` 레포 선택
   - Root Directory: `./` (빈 값)
   - Framework Preset: Next.js
   - 최초 배포 후 Settings → Git → **Disconnect** (GitHub Actions로 배포하므로)
4. **Infisical 시크릿 입력**
   - `/backend/` → 백엔드 .env (DATABASE_URL, JWT_SECRET 등)
   - `/backend/github-actions/` → 배포 변수 (BACK*BASTION*_, BACK*TARGET*_, BACK_SSH_PRIVATE_KEY 등)
   - `/frontend/` → 런타임 / Vercel로 자동 동기화될 환경변수
   - `/frontend/github-actions/` → 배포 변수 (FRONT*\* 또는 VERCEL*\*)
5. **Infisical → Vercel Integration** (Vercel 사용 시 권장)
   - Infisical 프로젝트 → Integrations → Vercel → Connect
   - `/frontend/` 경로를 Vercel 프로젝트에 자동 동기화

### 개발 시작

```bash
# 로컬 개발 (Infisical 로그인 필요)
infisical login --domain=https://env.co-di.com  # 최초 1회

cd apps/front && npm run dev    # http://localhost:3000
cd apps/back && npm run dev     # http://localhost:8080

# 코드 push → 자동 배포
git push origin dev   # → development 환경 배포
git push origin main  # → production 환경 배포
```

## 레포 구조

```
dev-{project}/
├── apps/
│   ├── front/                       # Next.js 15 (App Router)
│   │   └── .infisical.json          # Infisical 프로젝트 연결
│   └── back/                        # Express 5 + Prisma
│       └── .infisical.json
├── .github/workflows/
│   ├── deploy-frontend-vercel.yml   # apps/front/** → Vercel CLI 배포
│   ├── deploy-frontend-pm2.yml      # apps/front/** → SSH(Bastion)/PM2 배포
│   ├── deploy-frontend-docker.yml   # apps/front/** → SSH(Bastion)/Docker 배포
│   ├── deploy-backend-pm2.yml       # apps/back/**  → SSH(Bastion)/PM2 배포
│   └── deploy-backend-docker.yml    # apps/back/**  → SSH(Bastion)/Docker 배포
├── scripts/
│   └── init-project.sh              # 프로젝트 초기화 (dev 레포 1개 + Infisical)
├── .agents/                         # AI 에이전트 스킬 (oh-my-agent)
├── .claude/                         # Claude Code 설정 + 스킬
├── docs/
│   └── cloudflare-tunnel-ssh-guide.md   # Bastion SSH 배포 상세 가이드
├── CONTRIBUTING.md                  # 개발 가이드
└── README.md                        # 이 파일
```

> **워크플로우 활성화 규칙**: Frontend는 vercel/pm2/docker 중 **1개만** `on: push` 활성화, Backend는 pm2/docker 중 **1개만** 활성화. 나머지는 `workflow_dispatch`만 남겨 수동 실행용으로 둔다. 두 개가 동시 트리거되면 같은 커밋이 두 경로로 배포되어 충돌한다.

## 배포 파이프라인 흐름

```
개발자: git push origin main (또는 dev)
         │
         ▼
GitHub Actions (paths 필터로 변경 감지)
  │
  ├── apps/front/** 변경 시 → 활성화된 Frontend 워크플로우 실행
  │   ├── (Vercel)  Infisical에서 VERCEL_TOKEN/ORG_ID/PROJECT_ID → vercel pull/build/deploy
  │   ├── (PM2)     Infisical에서 FRONT_* → tar.gz → SSH(Bastion 경유) → 서버 셸스크립트
  │   └── (Docker)  Infisical에서 FRONT_* → docker save → SSH(Bastion 경유) → docker compose up
  │
  └── apps/back/** 변경 시 → 활성화된 Backend 워크플로우 실행
      ├── (PM2)     Infisical에서 BACK_* + 런타임 .env → tar.gz → SSH(Bastion 경유) → PM2 restart
      └── (Docker)  Infisical에서 BACK_* + 런타임 .env → docker save → SSH(Bastion 경유) → docker compose up
```

SSH 경유 방식(PM2/Docker)의 자세한 흐름은 [`docs/cloudflare-tunnel-ssh-guide.md`](docs/cloudflare-tunnel-ssh-guide.md) 참조.

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
  │   ├── /backend/                       DATABASE_URL, JWT_SECRET, ...
  │   ├── /backend/github-actions/        (배포 방식에 따라 필요한 키만)
  │   │   ├── BACK_SSH_TUNNEL_HOST        bastion hostname (= vpn-1-ga-1.hipasshub.com)
  │   │   ├── BACK_BASTION_USER           bastion 사용자 (= deploy)
  │   │   ├── BACK_BASTION_PORT           bastion sshd 포트 (= 9806)
  │   │   ├── BACK_TARGET_HOST            배포 서버 IP
  │   │   ├── BACK_TARGET_PORT            배포 서버 sshd 포트 (= 22)
  │   │   ├── BACK_SERVER_USER            배포 서버 사용자 (= rocky)
  │   │   ├── BACK_SSH_PRIVATE_KEY        프로젝트별 SSH 개인키
  │   │   ├── BACK_DEPLOY_DIR             배포 작업 디렉터리
  │   │   ├── BACK_APP_NAME               PM2 앱 이름 (PM2 방식)
  │   │   ├── BACK_TAR_FILE               빌드 산출물 파일명 (PM2 방식)
  │   │   └── BACK_APP_TYPE               pm2 (선택, 기본 pm2)
  │   ├── /frontend/                      NEXT_PUBLIC_*, ...
  │   └── /frontend/github-actions/       (배포 방식에 따라)
  │       ├── (Vercel)  VERCEL_ORG_ID, VERCEL_PROJECT_ID
  │       └── (PM2/Docker)  FRONT_* (BACK_* 와 동일 구조, 변수명만 FRONT_)
  └── prod 환경 (동일 키, 운영 값)

Shared-Secrets 프로젝트 (여러 프로젝트 공용)
  ├── /slack/                                slack_bot_token, slack_channel
  ├── /vercel/                               VERCEL_TOKEN
  └── /cloudflare/{domain}/{subdomain}/      CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET
                                             (예: /cloudflare/hipasshub-com/vpn-1-ga-1-token)
```

> **Cloudflare Access 토큰**은 워크플로우가 `Shared-Secrets/cloudflare/{domain}/{subdomain}/`에서 자동 조회한다. 프로젝트 Infisical에 따로 복사 금지.

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
