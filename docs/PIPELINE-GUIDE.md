# 멀티레포 배포 파이프라인 가이드

## 전체 구조

```mermaid
graph TB
    subgraph TEMPLATE["harness - 공용 템플릿"]
        T_FRONT[apps/front/]
        T_BACK[apps/back/]
        T_SYNC[sync-repos.yml]
        T_INIT[init-project.sh]
    end

    TEMPLATE -->|"zip 다운로드 후 init-project.sh 실행"| DEV

    subgraph DEV["dev-project - 모노레포"]
        D_FRONT[apps/front/]
        D_BACK[apps/back/]
        D_SYNC[sync-repos.yml]
    end

    DEV -->|"main/dev push"| SYNC

    subgraph SYNC["sync-repos.yml - GitHub Actions"]
        S_TOKEN["GitHub App 토큰 자동 발급"]
        S_SPLIT_F["git subtree split apps/front"]
        S_SPLIT_B["git subtree split apps/back"]
    end

    SYNC -->|push| FRONT_REPO
    SYNC -->|push| BACK_REPO

    subgraph FRONT_REPO["front-project"]
        F_CODE[Next.js 소스]
    end

    subgraph BACK_REPO["back-project"]
        B_CODE[Express 소스]
        B_DEPLOY[deploy.yml]
    end

    FRONT_REPO -->|"Git Integration"| VERCEL["Vercel 배포"]
    BACK_REPO -->|"Docker + SCP"| SERVER["Instance 서버"]

    
```

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

    DEV->>DR: git push origin main

    Note over SY: GitHub App 토큰 자동 발급
    DR->>SY: push 이벤트 트리거

    par 프론트 동기화
        SY->>FR: subtree split apps/front push
        FR->>VC: Git Integration으로 자동 배포
        Note over VC: main = Production / dev = Preview
    and 백엔드 동기화
        SY->>BR: subtree split apps/back push
        BR->>BR: deploy.yml 트리거
        BR->>SV: Docker build, SCP, docker compose up
        SV-->>BR: Health check 확인
    end

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
        BM["수동 등록"]
        BM --> BM1[SSH_PRIVATE_KEY]
        BM --> BM2[SLACK_WEBHOOK_URL]

        BE["Environment Secrets - dev/prod"]
        BE --> BE1["DEV_SERVER_HOST\nDEV_SERVER_USER\nDEV_DEPLOY_DIR"]
        BE --> BE2["PRD_SERVER_HOST\nPRD_SERVER_USER\nPRD_DEPLOY_DIR"]
        BE --> BE3[SERVER_ENV_FILE]
    end

    subgraph FR["front-{project}"]
        FR1["시크릿 불필요\nVercel이 자동 관리"]
    end

    
```

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
│       └── package.json
├── .github/workflows/
│   ├── sync-repos.yml          # subtree split으로 배포 레포 push
│   └── deploy.yml              # Docker 빌드/배포 (레거시)
├── docker/
│   ├── Dockerfile.front
│   ├── Dockerfile.server
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.prod.yml
├── scripts/
│   └── init-project.sh         # 프로젝트 초기화 자동화
├── templates/
│   └── back-deploy.yml         # back-{project} 배포 워크플로우
├── .agents/                    # AI 에이전트 스킬
├── .claude/                    # Claude Code 설정
├── CLAUDE.md                   # 프로젝트 규칙 (AI가 읽음)
├── CONTRIBUTING.md             # 개발 가이드 (사람이 읽음)
├── AGENTS.md                   # 에이전트 라우팅 가이드
└── README.md
```

## TODO

- [ ] Infisical 셀프호스팅 서버 구축
- [ ] `.pem` 파일을 Infisical에 보관 (현재: 프로젝트 루트 `codi-repo-sync.private-key.pem`)
- [ ] `SLACK_WEBHOOK_URL`을 Infisical에서 관리
- [ ] CI/CD에서 GitHub Secrets를 Infisical로 전환
- [ ] 로컬 개발 `infisical run -- npm run dev` 전환
