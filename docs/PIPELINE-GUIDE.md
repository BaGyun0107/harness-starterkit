# 멀티레포 배포 파이프라인 가이드

## 전체 구조

```mermaid
graph TB
    subgraph TEMPLATE["harness - 공용 템플릿"]
        T_FRONT[apps/front/]
        T_BACK[apps/back/]
        T_SYNC[sync-repos.yml]
        T_DEPLOY_REUSE[deploy-backend.yml<br/>Reusable Workflow]
        T_INIT[init-project.sh]
    end

    TEMPLATE -->|"zip 다운로드 후 init-project.sh 실행"| DEV

    subgraph DEV["dev-project - 모노레포"]
        D_FRONT[apps/front/]
        D_BACK[apps/back/<br/>Dockerfile + docker-compose.yml]
        D_SYNC[sync-repos.yml<br/>선택적 동기화]
    end

    DEV -->|"main/dev push"| SYNC

    subgraph SYNC["sync-repos.yml - GitHub Actions"]
        S_DETECT["dorny/paths-filter<br/>변경 감지"]
        S_TOKEN["GitHub App 토큰 자동 발급"]
        S_SPLIT_F["apps/front 변경 시만<br/>subtree split & push"]
        S_SPLIT_B["apps/back 변경 시만<br/>subtree split & push"]
    end

    SYNC -->|"front 변경 시"| FRONT_REPO
    SYNC -->|"back 변경 시"| BACK_REPO

    subgraph FRONT_REPO["front-project"]
        F_CODE[Next.js 소스]
    end

    subgraph BACK_REPO["back-project"]
        B_CODE[Express 소스 + Dockerfile]
        B_CALLER["deploy.yml<br/>(5줄 caller)"]
    end

    FRONT_REPO -->|"Git Integration"| VERCEL["Vercel 배포"]
    B_CALLER -->|"Reusable Workflow 호출"| T_DEPLOY_REUSE
    T_DEPLOY_REUSE -->|"Docker build + SCP"| SERVER["Instance 서버"]

    
```

> **핵심 변경:** sync-repos.yml이 `dorny/paths-filter`로 변경된 파일만 감지하여 해당 레포만 동기화.
> back-* 레포의 deploy.yml은 5줄짜리 caller로, 실제 배포 로직은 하네스의 deploy-backend.yml (Reusable Workflow)에 집중.

## 새 프로젝트 시작 흐름

```mermaid
sequenceDiagram
    participant TM as 팀원
    participant SC as init-project.sh
    participant GH as GitHub
    participant AC as GitHub Actions
    participant VC as Vercel

    Note over TM: Step 1. 하네스 다운로드
    TM->>TM: harness zip 다운로드 + 압축 해제

    Note over TM: Step 2. 앱 초기화
    TM->>TM: npx create-next-app apps/front
    TM->>TM: npm init + Express 설치 (apps/back)

    Note over TM: Step 3. Git 초기화
    TM->>TM: git init -b main && git add -A && git commit

    Note over TM,GH: Step 4. 프로젝트 초기화 스크립트
    TM->>SC: ./scripts/init-project.sh my-app front-org back-org

    SC->>GH: dev-{project} 레포 생성
    SC->>GH: front-{project} 레포 생성
    SC->>GH: back-{project} 레포 생성
    SC->>SC: 워크플로우 플레이스홀더 치환
    SC->>GH: APP_ID + APP_PRIVATE_KEY 시크릿 자동 등록
    SC->>GH: main/dev 브랜치 push

    GH->>AC: push 이벤트로 sync-repos.yml 트리거
    AC->>GH: front-{project}에 소스 동기화
    AC->>GH: back-{project}에 소스 동기화

    Note over TM: Step 5. 수동 설정
    TM->>GH: Slack Webhook, SSH 키, 서버 정보 시크릿 등록
    TM->>VC: front-{project} 레포 연결
```

## 배포 흐름 (일상 개발)

```mermaid
sequenceDiagram
    participant DEV as 개발자
    participant DR as dev-{project}
    participant SY as sync-repos.yml
    participant FR as front-{project}
    participant BR as back-{project}
    participant VC as Vercel
    participant SV as 배포 서버

    DEV->>DR: git push origin main (apps/back/ 수정)

    Note over SY: dorny/paths-filter로 변경 감지
    DR->>SY: push 이벤트 트리거

    alt apps/front/** 변경됨
        SY->>FR: subtree split apps/front push
        FR->>VC: Git Integration으로 자동 배포
        Note over VC: main = Production / dev = Preview
    end

    alt apps/back/** 변경됨
        SY->>BR: subtree split apps/back push
        BR->>BR: deploy.yml (caller) 트리거
        Note over BR: Reusable Workflow 호출<br/>→ dev-{project}/deploy-backend.yml
        BR->>SV: Docker build, SCP, docker compose up
        SV-->>BR: Health check 확인 (10회, 포트 설정 가능)
    end

    Note over SY: 변경 없는 쪽은 스킵
    SY-->>DEV: Slack 알림 (동기화 결과)
    BR-->>DEV: Slack 알림 (배포 결과)
```

## 브랜치 전략

```mermaid
gitGraph
    commit id: "init"
    branch dev
    checkout dev
    commit id: "feat: 초기 세팅"

    branch feat/login
    checkout feat/login
    commit id: "feat: 로그인 페이지"
    commit id: "feat: JWT 인증 추가"

    checkout dev
    merge feat/login id: "PR merge"
    commit id: "dev 자동 배포"

    checkout main
    merge dev id: "릴리스 PR merge"
    commit id: "main 자동 배포" tag: "v1.0.0"

    checkout dev
    commit id: "계속 개발..."

    checkout main
    branch hotfix/bug
    commit id: "fix: 긴급 수정"
    checkout main
    merge hotfix/bug id: "핫픽스 merge"
    commit id: "main 긴급 배포"
    checkout dev
    merge main id: "dev에 싱크"
```

| 브랜치 | 용도 | 배포 | 보호 |
|--------|------|------|------|
| `main` | 운영 릴리스 | Production | PR 필수 |
| `dev` | 통합 테스트 | Development | CI 통과 |
| `feat/*` | 기능 개발 | 없음 | - |
| `fix/*` | 버그 수정 | 없음 | - |
| `hotfix/*` | 긴급 수정 | 없음 | - |

## GitHub App 인증 흐름

```mermaid
flowchart LR
    subgraph A["초기 설정 - 1회"]
        A1[GitHub App 생성] --> A2[Org에 설치]
        A2 --> A3[.pem 파일 보관]
    end

    subgraph B["프로젝트 생성마다"]
        B1[init-project.sh] -->|".pem 읽기"| B2["APP_ID + APP_PRIVATE_KEY\n시크릿 자동 등록"]
    end

    subgraph C["매 push마다 - 자동"]
        C1[sync-repos.yml] --> C2["actions/create-github-app-token"]
        C2 -->|"1시간 토큰 발급"| C3[cross-org push]
    end

    A --> B --> C

    
```

PAT 방식과의 비교:

| | PAT 방식 | GitHub App 방식 (현재) |
|---|---|---|
| 토큰 생성 | 수동 | 자동 (매 실행마다) |
| 만료 | 최대 1년, 수동 갱신 | 없음 (자동 갱신) |
| 새 프로젝트 | 토큰 수동 등록 | init-project.sh가 자동 등록 |
| Org 승인 | Fine-grained PAT은 Org 승인 필요 | 불필요 (App이 이미 설치됨) |

## 레포별 시크릿 정리

### Phase 1: GitHub Secrets 기반 (현재, Infisical 준비 전)

```mermaid
flowchart TB
    subgraph D["dev-{project} 시크릿"]
        direction TB
        DA["자동 등록 - init-project.sh"]
        DA --> DA1[APP_ID]
        DA --> DA2[APP_PRIVATE_KEY]

        DM["수동 등록"]
        DM --> DM1[SLACK_WEBHOOK_URL]
    end

    subgraph BK["back-{project} 시크릿"]
        direction TB
        BM["수동 등록 - Repository Secrets"]
        BM --> BM1[SSH_PRIVATE_KEY]
        BM --> BM2[SLACK_WEBHOOK_URL]

        BE["수동 등록 - Environment Secrets<br/>development / production"]
        BE --> BE1["DEV_SERVER_HOST<br/>DEV_SERVER_USER<br/>DEV_DEPLOY_DIR"]
        BE --> BE2["PRD_SERVER_HOST<br/>PRD_SERVER_USER<br/>PRD_DEPLOY_DIR"]
        BE --> BE3["SERVER_ENV_FILE<br/>(앱 .env 내용 전체)"]
        BE --> BE4["SERVER_PORT<br/>(선택, 기본 8080)"]
    end

    subgraph FR["front-{project}"]
        FR1["시크릿 불필요<br/>Vercel이 자동 관리"]
    end

    
```

### Phase 2: Infisical 연동 후 (목표)

```mermaid
flowchart TB
    subgraph D2["dev-{project} 시크릿"]
        direction TB
        DA2A["자동 등록"]
        DA2A --> DA2A1[APP_ID]
        DA2A --> DA2A2[APP_PRIVATE_KEY]

        DM2["수동 등록"]
        DM2 --> DM2A[SLACK_WEBHOOK_URL]
    end

    subgraph BK2["back-{project} 시크릿"]
        direction TB
        BM2A["GitHub Secrets - 2개만"]
        BM2A --> BM2A1["INFISICAL_TOKEN<br/>(Machine Identity)"]
        BM2A --> BM2A2["SSH_PRIVATE_KEY<br/>(appleboy action용)"]

        INF["Infisical에서 관리"]
        INF --> INF1["/deploy/prod<br/>SERVER_HOST, SERVER_USER,<br/>DEPLOY_DIR, SERVER_PORT,<br/>SLACK_WEBHOOK_URL"]
        INF --> INF2["/deploy/dev<br/>동일 키, 개발 환경 값"]
        INF --> INF3["/app/prod<br/>DATABASE_URL, JWT_SECRET,<br/>앱 런타임 환경변수"]
        INF --> INF4["/app/dev<br/>동일 키, 개발 환경 값"]
    end

    subgraph FR2["front-{project}"]
        FR2A["시크릿 불필요<br/>Vercel이 자동 관리"]
    end

    
```

## 환경변수 관리 가이드

### 환경변수의 두 가지 레이어

| 레이어 | 용도 | 예시 | 사용 시점 |
|--------|------|------|-----------|
| **앱 런타임** | 애플리케이션이 실행 시 필요한 값 | DATABASE_URL, JWT_SECRET, REDIS_URL | 컨테이너 내부에서 앱이 읽음 |
| **배포 인프라** | CI/CD 파이프라인이 배포 시 필요한 값 | DEPLOY_SERVER, SSH_PRIVATE_KEY, SERVER_PORT | GitHub Actions workflow가 읽음 |

### Phase 1: GitHub Secrets 기반 (현재)

back-* 레포에 직접 등록해야 하는 시크릿 목록:

**Repository Secrets (환경 공통):**

| Secret | 설명 | 필수 |
|--------|------|------|
| `SSH_PRIVATE_KEY` | 배포 서버 SSH 개인 키 | 필수 |
| `SLACK_WEBHOOK_URL` | Slack 알림 Webhook URL | 선택 |

**Environment Secrets (development / production 별도):**

| Secret | 설명 | 필수 | 기본값 |
|--------|------|------|--------|
| `DEV_SERVER_HOST` / `PRD_SERVER_HOST` | 배포 서버 IP | 필수 | - |
| `DEV_SERVER_USER` / `PRD_SERVER_USER` | SSH 접속 유저 | 필수 | - |
| `DEV_DEPLOY_DIR` / `PRD_DEPLOY_DIR` | 배포 디렉터리 경로 | 필수 | - |
| `SERVER_ENV_FILE` | 앱 .env 파일 내용 전체 (멀티라인) | 필수 | - |
| `SERVER_PORT` | 앱 서버 포트 | 선택 | 8080 |

**등록 방법:**
1. back-{project} 레포 → Settings → Secrets and variables → Actions
2. Repository secrets에 SSH_PRIVATE_KEY, SLACK_WEBHOOK_URL 등록
3. Environments → "development" 생성 → Environment secrets에 DEV_* 등록
4. Environments → "production" 생성 → Environment secrets에 PRD_* 등록

### Phase 2: Infisical 연동 후 (목표)

Infisical 서버가 준비되면 GitHub Secrets를 최소화하고 Infisical에서 환경변수를 관리합니다.

**GitHub Secrets에 남는 것 (2개만):**

| Secret | 이유 |
|--------|------|
| `INFISICAL_TOKEN` | Infisical Machine Identity 토큰. CI/CD에서 Infisical API 접근용 |
| `SSH_PRIVATE_KEY` | appleboy/ssh-action이 GitHub Secret으로 직접 받아야 함 |

**Infisical 경로 구조:**

```
프로젝트/
├── deploy/           ← 배포 인프라용 환경변수
│   ├── prod/
│   │   ├── SERVER_HOST=10.0.1.5
│   │   ├── SERVER_USER=ubuntu
│   │   ├── DEPLOY_DIR=/opt/app
│   │   ├── SERVER_PORT=8080
│   │   └── SLACK_WEBHOOK_URL=https://hooks.slack.com/...
│   └── dev/
│       ├── SERVER_HOST=10.0.2.10
│       ├── SERVER_USER=ubuntu
│       ├── DEPLOY_DIR=/opt/app-dev
│       ├── SERVER_PORT=8080
│       └── SLACK_WEBHOOK_URL=https://hooks.slack.com/...
│
└── app/              ← 앱 런타임용 환경변수
    ├── prod/
    │   ├── DATABASE_URL=mysql://...
    │   ├── JWT_SECRET=...
    │   └── REDIS_URL=...
    └── dev/
        ├── DATABASE_URL=mysql://...
        ├── JWT_SECRET=...
        └── REDIS_URL=...
```

**deploy-backend.yml에서의 사용:**

```yaml
# Infisical CLI로 배포 인프라 변수 가져오기
- name: Install Infisical CLI
  run: |
    curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
    sudo apt-get install -y infisical

- name: Export deploy config
  run: |
    ENV_NAME=${{ inputs.environment == 'production' && 'prod' || 'dev' }}
    # 배포 인프라 변수 → GITHUB_ENV에 주입
    infisical export --env=$ENV_NAME --path="/deploy" --format=dotenv | \
      while IFS='=' read -r key value; do
        echo "${key}=${value}" >> $GITHUB_ENV
      done
    # 앱 런타임 변수 → .env 파일로 생성
    infisical export --env=$ENV_NAME --path="/app" --format=dotenv > .env
  env:
    INFISICAL_TOKEN: ${{ secrets.INFISICAL_TOKEN }}
```

**전환 절차:**
1. Infisical 서버 구축 + Machine Identity 토큰 발급
2. Infisical에 `/deploy/prod`, `/deploy/dev`, `/app/prod`, `/app/dev` 경로 생성
3. 기존 GitHub Secrets 값을 Infisical에 복사
4. back-* 레포에 `INFISICAL_TOKEN` Secret 등록
5. deploy-backend.yml에서 Infisical CLI 블록 활성화, 기존 GitHub Secrets 참조 제거
6. 검증 후 back-* 레포에서 불필요한 GitHub Secrets 삭제

### Reusable Workflow 구조

배포 로직은 하네스의 `deploy-backend.yml`에 한 번만 정의하고, 각 back-* 레포는 5줄짜리 caller로 호출합니다.

```
하네스 (dev-{project})
└── .github/workflows/deploy-backend.yml     ← 배포 로직 (Reusable Workflow)
    - Docker build + SCP + health check + Slack

back-{project}
└── .github/workflows/deploy.yml             ← 5줄짜리 caller
    - uses: {BACK_ORG}/{DEV_REPO}/.github/workflows/deploy-backend.yml@main
    - secrets: inherit
```

**배포 로직 수정 시:** 하네스의 deploy-backend.yml 1개만 수정하면 모든 back-* 프로젝트에 자동 반영.

## 커밋 컨벤션

```
<type>: <한글 설명>
```

**description은 반드시 한글로 작성합니다.** type 접두사만 영문.

```
feat: 로그인 페이지 구현
fix: 토큰 만료 시 리다이렉트 안 되는 문제 수정
chore: GitHub App 기반 배포 파이프라인 추가
refactor: 사용자 인증 로직 분리
docs: README 멀티레포 파이프라인 설명 추가
```

| Type | 용도 |
|------|------|
| `feat` | 새 기능 |
| `fix` | 버그 수정 |
| `chore` | 빌드, 설정 변경 |
| `refactor` | 리팩터링 |
| `docs` | 문서 |
| `style` | 포맷팅 |
| `test` | 테스트 |
| `perf` | 성능 개선 |

## 로컬 개발 환경

```mermaid
flowchart LR
    subgraph L["로컬 개발"]
        LF["apps/front/\nnpm run dev\n:3000"]
        LB["apps/back/\nnpm run dev\n:8080"]
        LD["MySQL\n:3306"]
    end

    subgraph DK["Docker 전체 실행 - 선택"]
        DF["front :3000"]
        DS["server :8080"]
        DM["mysql :3306"]
    end

    LF -->|API 호출| LB
    LB -->|쿼리| LD

    DF --> DS --> DM

    
```

```bash
# 개별 실행
cd apps/front && npm run dev    # http://localhost:3000
cd apps/back && npm run dev     # http://localhost:8080

# Docker로 전체 실행
cd docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

## 디렉토리 구조

```
dev-{project}/
├── apps/
│   ├── front/                  # front-{project}로 동기화
│   │   ├── src/
│   │   ├── package.json
│   │   └── next.config.ts
│   └── back/                   # back-{project}로 동기화
│       ├── src/
│       ├── prisma/
│       ├── package.json
│       ├── Dockerfile          # back-* 레포 루트 기준 Docker 빌드
│       ├── docker-compose.yml  # EC2 서버에 scp로 전송됨
│       └── .dockerignore       # .env 등 민감파일 제외
├── .github/workflows/
│   ├── sync-repos.yml          # 선택적 동기화 (paths-filter)
│   └── deploy-backend.yml      # Reusable Workflow (중앙 배포 로직)
├── docker/                     # 로컬 개발용 Docker 설정
│   ├── Dockerfile.front
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.prod.yml
├── scripts/
│   └── init-project.sh         # 프로젝트 초기화 (레포 생성 + deploy caller push)
├── templates/
│   └── back-deploy.yml         # back-* 레포용 deploy caller 템플릿 (5줄)
├── .agents/                    # AI 에이전트 스킬
├── .claude/                    # Claude Code 설정
├── CLAUDE.md                   # 프로젝트 규칙 (AI가 읽음)
├── CONTRIBUTING.md             # 개발 가이드 (사람이 읽음)
├── AGENTS.md                   # 에이전트 라우팅 가이드
└── README.md
```

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] Infisical Machine Identity 토큰 발급 + 프로젝트별 경로 구성 (/deploy, /app)
- [ ] `.pem` 파일을 Infisical에 보관 (현재: 프로젝트 루트 `codi-repo-sync.private-key.pem`)
- [ ] deploy-backend.yml에서 Infisical CLI 블록 활성화 (위 "Phase 2: Infisical 연동 후" 참고)
- [ ] 기존 GitHub Secrets → Infisical 마이그레이션
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환
- [ ] 서버 프로비저닝 스크립트 (EC2 초기 Docker + docker-compose 설치)
- [ ] Blue-green deploy 검토
- [ ] 자동 롤백 (현재는 수동 롤백 안내만 제공)
