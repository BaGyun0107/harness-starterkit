# harness

사내 공용 프로젝트 하네스. AI 에이전트 스킬, CI/CD, Docker, Git workflow, 멀티레포 배포 파이프라인을 포함합니다.

## 아키텍처

```
harness (이 레포, 공용 템플릿)
  │
  │  zip 다운로드 후 init-project.sh 실행
  ▼
dev-{project}  ← 모노레포 (개발 + 동기화 트리거)
  │
  │  main/dev push 시 sync-repos.yml 자동 실행
  │
  ├──→ front-{project}  ← Vercel 자동 배포 (Front Org)
  └──→ back-{project}   ← Docker+SCP 배포 (GitHub Actions)
```

## 새 프로젝트 시작하기

### 사전 준비

| 도구 | 설치 |
|------|------|
| Node.js 24+ | `mise install` (`.mise.toml` 포함) |
| GitHub CLI | https://cli.github.com/ |
| Docker & Docker Compose | https://docs.docker.com/get-docker/ |
| bun | gstack 빌드용 (선택) |

### Step 1: 하네스 다운로드

```bash
# harness zip 다운로드 후 압축 해제
mkdir my-project && cd my-project
# zip 내용물을 여기에 복사
```

### Step 2: Front/Back 프로젝트 초기화

```bash
# Frontend (Next.js)
npx create-next-app@latest apps/front --typescript --tailwind --eslint --app --src-dir --use-npm

# Backend (Express + Prisma)
cd apps/back
npm init -y
npm install express@5 prisma @prisma/client
npm install -D typescript @types/node @types/express ts-node
# tsconfig.json, src/server.ts 등 생성
```

### Step 3: Git 초기화

```bash
cd my-project  # 프로젝트 루트로 이동
git init -b main
git add -A
git commit -m "chore: initial commit"
```

### Step 4: 프로젝트 초기화 스크립트 실행

```bash
./scripts/init-project.sh <project-name> <front-org> <back-org>

# 예시:
./scripts/init-project.sh my-app your-front-org your-back-org
```

이 스크립트가 자동으로 수행하는 것:
1. GitHub 레포 3개 생성 (dev-/front-/back-)
2. 워크플로우 플레이스홀더 치환
3. **GitHub App 토큰(APP_ID, APP_PRIVATE_KEY) 시크릿 자동 등록**
4. Git remote 설정 + main/dev 브랜치 생성 및 push

### Step 5: 수동 설정

스크립트 완료 후 출력되는 안내에 따라:

1. **Slack Webhook** 등록 (dev-{project}, back-{project} 레포에)
2. **배포 서버 정보** 등록 (SSH 키, 서버 IP, 배포 디렉터리)
3. **Vercel 연결**: Vercel 대시보드 → New Project → front-{project} 레포 연결

### Step 6: 개발 시작

```bash
# 로컬 개발
cd apps/front && npm run dev    # http://localhost:3000
cd apps/back && npm run dev     # http://localhost:8080

# Docker로 전체 실행
cd docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# 코드 push → 자동 동기화 → 자동 배포
git push origin main
```

## 레포 구조

```
harness/
├── apps/
│   ├── front/                  # Next.js 15 (App Router)
│   └── back/                   # Express 5 + Prisma
├── .github/workflows/
│   ├── deploy.yml              # 로컬 Docker 빌드/배포 (레거시)
│   └── sync-repos.yml          # 모노레포 → 멀티레포 동기화
├── docker/
│   ├── Dockerfile.front        # Next.js standalone 빌드
│   ├── Dockerfile.server       # Express multi-stage 빌드
│   ├── docker-compose.yml      # 공통 서비스 (server, front, mysql)
│   ├── docker-compose.dev.yml  # 개발 오버라이드
│   └── docker-compose.prod.yml # 운영 오버라이드
├── scripts/
│   ├── init-project.sh         # 프로젝트 초기화 (3개 레포 + 시크릿)
│   ├── setup-hooks.sh          # Git hooks 설치
│   └── setup-gstack.sh         # gstack 빌드
├── templates/
│   └── back-deploy.yml         # back-{project} 배포 워크플로우 템플릿
├── .agents/                    # AI 에이전트 스킬 (oh-my-agent)
├── .claude/                    # Claude Code 설정 + 스킬
├── .infisical.json.tmpl        # Infisical 설정 템플릿
├── docs/                       # 문서
├── CONTRIBUTING.md             # 개발 가이드
└── README.md                   # 이 파일
```

## 배포 파이프라인 흐름

```
개발자: git push origin main (dev-{project})
         │
         ▼
sync-repos.yml (GitHub Actions)
  ├── GitHub App 토큰 자동 발급 (actions/create-github-app-token)
  ├── git subtree split --prefix=apps/front → front-{project} push
  └── git subtree split --prefix=apps/back  → back-{project} push
         │                        │
         ▼                        ▼
  Vercel 자동 배포          back-{project}/deploy.yml
  (Git Integration)         ├── Docker build
                            ├── SCP → 서버 전송
                            ├── docker compose up
                            └── Health check + Slack 알림
```

## Git Workflow

```
main    → 운영계 자동 배포
dev     → 개발계 자동 배포
feat/*  → 기능 개발 (dev로 PR)
fix/*   → 버그 수정 (dev로 PR)
hotfix/* → 긴급 수정 (main + dev)
```

상세 브랜치 규칙과 커밋 컨벤션은 [CONTRIBUTING.md](CONTRIBUTING.md) 참조.

## GitHub App (repo-sync)

sync-repos.yml에서 cross-org push를 위해 GitHub App을 사용합니다.
init-project.sh가 APP_ID와 APP_PRIVATE_KEY를 dev-{project} 레포에 자동 등록합니다.

| 항목 | 값 |
|------|-----|
| App 이름 | repo-sync |
| 권한 | Contents: Read and write |
| 설치된 Org | your-front-org, your-back-org |
| 토큰 만료 | 없음 (매 실행마다 자동 발급) |

.pem 파일 위치: `~/Downloads/repo-sync.private-key.pem` (기본값)
또는 `GITHUB_APP_PEM` 환경변수로 경로 지정.

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] .pem 파일을 Infisical에 보관
- [ ] SLACK_WEBHOOK_URL을 Infisical에서 관리
- [ ] CI/CD에서 GitHub Secrets → Infisical 전환
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환

## 주요 Claude Code 스킬

| 명령어 | 역할 |
|--------|------|
| `/deepinit` | 프로젝트 초기화 |
| `/setup` | 환경 설정 |
| `/office-hours` | 아이디어 검증 |
| `/autoplan` | 자동 플랜 수립 |
| `/ship` | 커밋 + PR 생성 |
| `/qa` | 브라우저 QA 테스트 |
| `/investigate` | 버그 조사 |

## 요구사항

- Node.js 24+
- GitHub CLI (`gh`)
- Docker & Docker Compose (배포용)
- Claude Code CLI
- GitHub App private key (.pem)
