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

| 도구                    | 설치                                |
| ----------------------- | ----------------------------------- |
| Node.js 24+             | `mise install` (`.mise.toml` 포함)  |
| GitHub CLI              | https://cli.github.com/             |
| Docker & Docker Compose | https://docs.docker.com/get-docker/ |
| Claude Code CLI         | AI 기반 초기화 스킬 사용 시 필요    |
| bun                     | gstack 빌드용 (선택)                |

### 방법 1: `/init-project` 스킬 사용 (권장)

Claude Code에서 `/init-project`를 실행하면 대화형으로 전체 과정을 안내합니다.

```bash
# 1. 하네스 다운로드 후 디렉토리 이동
mkdir my-project && cd my-project
# zip 내용물을 여기에 복사

# 2. Claude Code 또는 Codex 실행
claude || codex

# 3. 프롬프트에서 /init-project 입력
```

스킬이 자동으로 수행하는 것:

1. **현재 상태 감지** — `apps/front/`, `apps/back/` 존재 여부 확인
2. **초기화 옵션 선택** — 5가지 중 상태에 맞는 옵션 추천
3. **스캐폴딩** — oma-frontend/oma-backend 스킬 기반 프로덕션 레디 보일러플레이트 생성
4. **프로젝트 정보 수집** — project-name, front-org, back-org
5. **레포 생성 + 시크릿 등록 + 배포 파이프라인 설정** — `init-project.sh` 자동 실행
6. **완료 안내** — 수동 설정 필요 항목 출력

#### 초기화 옵션

| 옵션                  | 설명                                                          |
| --------------------- | ------------------------------------------------------------- |
| A) 전체 초기화        | front + back 보일러플레이트 생성 (병렬)                       |
| B) Frontend만         | Next.js 15 + FSD-lite + shadcn/ui                             |
| C) Backend만          | Express 5 + Prisma + BaseController                           |
| D) 건너뛰기           | 이미 소스 있음 → 바로 레포 생성 단계로                        |
| **E) 기존 레포 통합** | **별도 레포의 소스를 커밋 히스토리 보존하며 모노레포로 통합** |

#### 기존 레포 통합 (E 옵션)

이미 front/back이 별도 레포로 존재하는 경우:

- `git subtree add`로 커밋 히스토리를 보존하며 `apps/front/` 또는 `apps/back/`으로 통합
- 통합 후 자동으로 레포 생성 → push → `sync-repos.yml` 트리거 → 배포 레포 동기화

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

# 4. Git 초기화
cd my-project
git init -b main
git add -A
git commit -m "chore: initial commit"

# 5. init-project.sh 실행
./scripts/init-project.sh my-app --mode full --front-org <front-org> --back-org <back-org>
```

### 수동 설정 (공통)

스크립트 완료 후 출력되는 안내에 따라:

1. **Slack Webhook** 등록 (dev-{project}, back-{project} 레포에)
2. **배포 서버 정보** 등록 (SSH 키, 서버 IP, 배포 디렉터리)
3. **Vercel 연결**: Vercel 대시보드 → New Project → front-{project} 레포 연결

### 개발 시작

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

| 항목       | 값                            |
| ---------- | ----------------------------- |
| App 이름   | repo-sync                     |
| 권한       | Contents: Read and write      |
| 설치된 Org | your-front-org, your-back-org |
| 토큰 만료  | 없음 (매 실행마다 자동 발급)  |

.pem 파일 위치: 프로젝트 루트 `codi-repo-sync.private-key.pem` (기본값, .gitignore에 포함)
또는 `GITHUB_APP_PEM` 환경변수로 경로 지정.

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] .pem 파일을 Infisical에 보관
- [ ] SLACK_WEBHOOK_URL을 Infisical에서 관리
- [ ] CI/CD에서 GitHub Secrets → Infisical 전환
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환

## 주요 Claude Code 스킬

| 명령어          | 역할                                                    |
| --------------- | ------------------------------------------------------- |
| `/init-project` | 프로젝트 초기화 (스캐폴딩 + 레포 생성 + 기존 레포 통합) |
| `/deepinit`     | 프로젝트 초기화                                         |
| `/setup`        | 환경 설정                                               |
| `/office-hours` | 아이디어 검증                                           |
| `/autoplan`     | 자동 플랜 수립                                          |
| `/ship`         | 커밋 + PR 생성                                          |
| `/qa`           | 브라우저 QA 테스트                                      |
| `/investigate`  | 버그 조사                                               |

## 요구사항

- Node.js 24+
- GitHub CLI (`gh`)
- Docker & Docker Compose (배포용)
- Claude Code CLI
- GitHub App private key (.pem)

## 참고 레포

- [Gstack](https://github.com/garrytan/gstack)
- [oh-my-agent](https://github.com/first-fluke/oh-my-agent)
