# Contributing Guide

## Git Workflow

```
main              ← 운영계 (Production) — GitHub Actions 자동 배포
  └── hotfix/*    ← 긴급 수정 → main + dev 양쪽 머지
dev               ← 개발계 (Development) — GitHub Actions 자동 배포
  └── feat/*      ← 기능 개발 → dev PR
  └── fix/*       ← 버그 수정 → dev PR
```

## Branch Rules

| Branch | 용도 | 배포 대상 | 보호 |
|--------|------|----------|------|
| `main` | 운영 릴리스 | Production | PR 필수, CI 통과 |
| `dev` | 통합 테스트 | Development | CI 통과 |
| `feat/*` | 기능 개발 | - | - |
| `fix/*` | 버그 수정 | - | - |
| `hotfix/*` | 긴급 수정 | - | - |

## 개발 흐름

### 1. 기능 개발

```bash
git checkout dev
git pull origin dev
git checkout -b feat/my-feature

# 작업 후
git add <files>
git commit -m "feat: add my feature"
git push -u origin feat/my-feature

# GitHub에서 dev 브랜치로 PR 생성
```

### 2. 운영 배포

```bash
# dev → main PR 생성 (GitHub)
# 리뷰 + CI 통과 후 머지 → GitHub Actions 자동 배포
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
<type>: <description>

Types:
  feat     — 새 기능
  fix      — 버그 수정
  chore    — 빌드, 설정 변경
  refactor — 리팩터링
  docs     — 문서
  style    — 포맷팅
  test     — 테스트
  perf     — 성능 개선
```

## Local Development

```bash
# Backend
cd apps/server
npm install
npm run dev          # http://localhost:8080

# Frontend
cd apps/front
npm install
npm run dev          # http://localhost:3000

# Docker (전체)
cd docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

## CI/CD Pipeline

GitHub Actions (`.github/workflows/deploy.yml`):

1. **Detect Changes** — `dorny/paths-filter`로 front/server 변경 감지
2. **Build** — 변경된 앱만 Docker 이미지 빌드 (병렬)
3. **Deploy** — Docker image → scp → docker load → docker compose up
4. **Health Check** — 서버 health endpoint 확인
5. **Slack 알림** — 성공/실패 Slack 채널 알림

배포 환경:
- `main` push → **production** 서버 배포
- `dev` push → **development** 서버 배포
- `feat/*`, `fix/*` → 배포 없음

## GitHub Secrets 설정 (필수)

새 프로젝트 생성 시 **Settings → Secrets and variables → Actions**에서 아래 항목을 등록해야 합니다.

### Repository Secrets (전체 환경 공통)

| Secret | 설명 | 예시 |
|--------|------|------|
| `SSH_PRIVATE_KEY` | 배포 서버 SSH 접근 키 | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL | `https://hooks.slack.com/services/T.../B.../...` |

### Environment Secrets (환경별)

GitHub **Settings → Environments**에서 `development`, `production` 환경을 생성 후 각각 설정:

**development 환경:**

| Secret | 설명 | 예시 |
|--------|------|------|
| `DEV_SERVER_HOST` | 개발 서버 IP | `10.0.10.22` |
| `DEV_SERVER_USER` | 개발 서버 SSH 유저 | `rocky` |
| `DEV_DEPLOY_DIR` | 배포 디렉터리 경로 | `/home/rocky/codi-goyo` |
| `SERVER_ENV_FILE` | 백엔드 `.env` 파일 내용 전체 | `DATABASE_URL=mysql://...` |
| `FRONT_ENV_FILE` | 프론트 `.env.local` 파일 내용 전체 | `NEXT_PUBLIC_API_ORIGIN=https://...` |

**production 환경:**

| Secret | 설명 | 예시 |
|--------|------|------|
| `PRD_SERVER_HOST` | 운영 서버 IP | `10.0.10.10` |
| `PRD_SERVER_USER` | 운영 서버 SSH 유저 | `rocky` |
| `PRD_DEPLOY_DIR` | 배포 디렉터리 경로 | `/home/rocky/codi-goyo` |
| `SERVER_ENV_FILE` | 백엔드 `.env` 파일 내용 전체 | `DATABASE_URL=mysql://...` |
| `FRONT_ENV_FILE` | 프론트 `.env.local` 파일 내용 전체 | `NEXT_PUBLIC_API_ORIGIN=https://...` |

### 서버 사전 준비

배포 대상 서버에 Docker가 설치되어 있어야 합니다:

```bash
# Docker 설치
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Docker Compose 확인 (Docker 24+ 에 포함)
docker compose version
```

## Docker 운영 명령어

배포 후 서버에서 사용하는 주요 명령어:

```bash
cd /home/rocky/codi-goyo

# ── 상태 확인 ──
docker compose -f docker/docker-compose.yml ps         # 컨테이너 상태
docker stats                                            # 실시간 CPU/메모리 (pm2 monit 대체)

# ── 로그 ──
docker logs codi-goyo-server-1 --tail 100              # 최근 100줄 (pm2 logs 대체)
docker logs codi-goyo-server-1 -f                      # 실시간 로그 (pm2 logs --follow 대체)
docker logs codi-goyo-front-1 --since 1h               # 최근 1시간 로그

# ── 재시작 ──
docker compose -f docker/docker-compose.yml restart server   # 서버만 재시작 (pm2 restart 대체)
docker compose -f docker/docker-compose.yml restart front    # 프론트만 재시작

# ── 중지 / 시작 ──
docker compose -f docker/docker-compose.yml stop             # 전체 중지 (pm2 stop all 대체)
docker compose -f docker/docker-compose.yml up -d            # 전체 시작 (pm2 start all 대체)

# ── 이미지 정리 ──
docker image prune -f                                        # 미사용 이미지 삭제
```

## Directory Structure

```
codi-goyo/
├── .github/workflows/  # GitHub Actions CI/CD
├── apps/
│   ├── front/          # Next.js 15 (App Router)
│   └── server/         # Express 5 + Prisma
├── docker/
│   ├── Dockerfile.front
│   ├── Dockerfile.server
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.prod.yml
├── .agents/            # AI agent skills & configs
├── docs/               # Documentation
└── CONTRIBUTING.md     # This file
```
