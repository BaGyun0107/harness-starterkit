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
# 리뷰 + CI 통과 후 머지 → 자동 동기화 → 자동 배포
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
  chore: GitHub App 기반 배포 파이프라인 추가
```

**description은 한글로 작성합니다.** type 접두사만 영문, 설명은 한글.

## Local Development

```bash
# Backend
cd apps/back
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

### 전체 흐름

```
dev-{project} push (main/dev)
  │
  ├── sync-repos.yml
  │   ├── GitHub App 토큰 자동 발급
  │   ├── git subtree split --prefix=apps/front → front-{project}
  │   └── git subtree split --prefix=apps/back  → back-{project}
  │
  ├── front-{project} push
  │   └── Vercel 자동 배포 (Git Integration)
  │       ├── main → Production
  │       └── dev  → Preview
  │
  └── back-{project} push
      └── deploy.yml (GitHub Actions)
          ├── Docker 이미지 빌드
          ├── SCP → 배포 서버 전송
          ├── docker compose up
          ├── Health check
          └── Slack 알림
```

### 배포 환경

- `main` push → **production** 배포
- `dev` push → **development** 배포
- `feat/*`, `fix/*` → 배포 없음 (dev-{project} 레포에서만 개발)

## 새 프로젝트 초기화

### 1. 하네스 다운로드 + 앱 초기화

```bash
# harness zip 다운로드 후 압축 해제
mkdir my-project && cd my-project

# Frontend 초기화
npx create-next-app@latest apps/front --typescript --tailwind --eslint --app --src-dir --use-npm
rm -rf apps/front/.git  # create-next-app이 만든 .git 제거

# Backend 초기화
cd apps/back
npm init -y
npm install express@5 prisma @prisma/client
npm install -D typescript @types/node @types/express ts-node
# src/server.ts, tsconfig.json 등 생성
```

### 2. Git 초기화

```bash
cd my-project  # 프로젝트 루트
git init -b main
git add -A
git commit -m "chore: initial commit"
```

### 3. init-project.sh 실행

```bash
./scripts/init-project.sh <project-name> <front-org> <back-org>

# 예시:
./scripts/init-project.sh my-app your-front-org your-back-org
```

스크립트가 자동으로:
- GitHub 레포 3개 생성 (dev-/front-/back-)
- sync-repos.yml 플레이스홀더 치환
- GitHub App 시크릿(APP_ID, APP_PRIVATE_KEY) 자동 등록
- Git remote + main/dev 브랜치 설정 및 push
- 첫 push로 sync-repos.yml 트리거 → 배포 레포에 코드 동기화

### 4. 수동 설정

| 작업 | 대상 레포 | 설명 |
|------|----------|------|
| SLACK_WEBHOOK_URL | dev-{project} | Slack 동기화 알림 |
| SSH_PRIVATE_KEY | back-{project} | 배포 서버 SSH 키 |
| SLACK_WEBHOOK_URL | back-{project} | Slack 배포 알림 |
| 서버 환경 시크릿 | back-{project} | DEV/PRD_SERVER_HOST, USER, DEPLOY_DIR 등 |
| SERVER_ENV_FILE | back-{project} | 백엔드 .env 파일 내용 |
| Vercel 연결 | front-{project} | Vercel 대시보드 → New Project → 레포 연결 |

### 5. 개발 시작

```bash
# 코드 수정 후 push하면 자동으로:
# 1. sync-repos.yml → front-/back- 레포에 동기화
# 2. Vercel → 프론트 자동 배포
# 3. back-{project}/deploy.yml → 백엔드 자동 배포
git push origin main
```

## GitHub App (repo-sync)

cross-org push를 위해 GitHub App을 사용합니다. PAT와 달리 만료가 없고 매 실행마다 토큰을 자동 발급합니다.

| 항목 | 값 |
|------|-----|
| App 이름 | repo-sync |
| 권한 | Contents: Read and write |
| 설치된 Org | your-front-org, your-back-org |

`.pem` 파일이 필요합니다:
- 기본 경로: `~/Downloads/repo-sync.private-key.pem`
- 또는: `GITHUB_APP_PEM=/path/to/key.pem ./scripts/init-project.sh ...`

## GitHub Secrets 정리

### dev-{project} 레포 (자동 등록)

| Secret | 등록 방식 | 설명 |
|--------|----------|------|
| `APP_ID` | init-project.sh 자동 | GitHub App ID |
| `APP_PRIVATE_KEY` | init-project.sh 자동 | GitHub App private key |

### dev-{project} 레포 (수동 등록)

| Secret | 설명 |
|--------|------|
| `SLACK_WEBHOOK_URL` | Slack 동기화 알림 (선택) |

### back-{project} 레포 (수동 등록)

| Secret | 설명 |
|--------|------|
| `SSH_PRIVATE_KEY` | 배포 서버 SSH 접근 키 |
| `SLACK_WEBHOOK_URL` | Slack 배포 알림 (선택) |

### back-{project} Environment Secrets

GitHub Settings → Environments에서 `development`, `production` 환경 생성 후 설정:

| Secret | 설명 | 예시 |
|--------|------|------|
| `DEV_SERVER_HOST` | 개발 서버 IP | `10.0.10.22` |
| `DEV_SERVER_USER` | 개발 서버 SSH 유저 | `rocky` |
| `DEV_DEPLOY_DIR` | 배포 디렉터리 경로 | `/home/rocky/my-app` |
| `PRD_SERVER_HOST` | 운영 서버 IP | `10.0.10.10` |
| `PRD_SERVER_USER` | 운영 서버 SSH 유저 | `rocky` |
| `PRD_DEPLOY_DIR` | 배포 디렉터리 경로 | `/home/rocky/my-app` |
| `SERVER_ENV_FILE` | 백엔드 `.env` 파일 내용 | `DATABASE_URL=mysql://...` |

## 서버 사전 준비

배포 대상 서버에 Docker가 설치되어 있어야 합니다:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
docker compose version
```

## Docker 운영 명령어

```bash
cd /home/rocky/my-app

# 상태 확인
docker compose ps
docker stats

# 로그
docker logs my-app-back-1 --tail 100
docker logs my-app-back-1 -f

# 재시작
docker compose restart

# 중지 / 시작
docker compose stop
docker compose up -d

# 이미지 정리
docker image prune -f
```

## Directory Structure

```
dev-{project}/
├── apps/
│   ├── front/              # Next.js 15 (→ front-{project}로 동기화)
│   └── back/               # Express 5 + Prisma (→ back-{project}로 동기화)
├── .github/workflows/
│   ├── sync-repos.yml      # subtree split → 배포 레포 push
│   └── deploy.yml          # 로컬 Docker 빌드/배포 (레거시)
├── docker/                 # Docker 설정 (로컬 개발용)
├── scripts/                # 초기화, Git hooks
├── templates/              # 배포 레포 워크플로우 템플릿
├── .agents/                # AI 에이전트 스킬
├── .claude/                # Claude Code 설정
├── docs/                   # 문서
├── .infisical.json         # Infisical 프로젝트 연결 (TODO)
├── CONTRIBUTING.md         # 이 파일
└── README.md
```

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] .pem 파일을 Infisical에 보관
- [ ] SLACK_WEBHOOK_URL을 Infisical에서 관리
- [ ] CI/CD에서 GitHub Secrets → Infisical 전환
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환
