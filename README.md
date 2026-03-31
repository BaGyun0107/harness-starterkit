# harness

AI 에이전트 스킬, CI/CD, Docker, Git workflow 설정을 포함합니다.

## 사용법

### 1. 새 프로젝트에 하네스 적용

```bash
# 프로젝트 디렉터리 생성
mkdir my-project && cd my-project
git init -b main

# 하네스 복사
cp -r /path/to/codi-harness/{.agents,.claude,.codex,.gemini,.qwen,.github,docker,scripts} .
cp /path/to/codi-harness/{.gitignore,.dockerignore,.mise.toml,AGENTS.md,CONTRIBUTING.md} .

# mise 신뢰 등록 (최초 1회)
mise trust .mise.toml

# Git hooks 설치
sh scripts/setup-hooks.sh

# gstack 빌드 (최초 1회)
sh scripts/setup-gstack.sh

# dev 브랜치 생성
git branch dev

# 프로젝트 초기화 (Claude Code에서)
/deepinit   # 또는 /setup
```

### 2. 기존 프로젝트에 하네스 추가

```bash
cd existing-project

# 하네스 파일 복사 (기존 파일 덮어쓰기 주의)
cp -rn /path/to/codi-harness/{.agents,.claude,.codex,.gemini,.qwen} .
cp -rn /path/to/codi-harness/{.github,docker,scripts} .

# Git hooks 설치
sh scripts/setup-hooks.sh
```

## 포함 내용

### AI 에이전트 (`oh-my-agent`)

```
.agents/
├── config/          # 사용자 설정 (언어, 타임존)
├── skills/          # 도메인 스킬
│   ├── _shared/     # 공유 코어 (routing, context-loading)
│   ├── oma-backend/  # API, DB, 인증, 미들웨어
│   ├── oma-frontend/ # React, Next.js, Tailwind
│   ├── oma-db/       # 스키마, 마이그레이션, ERD
│   ├── oma-qa/       # 보안, 성능, 접근성 감사
│   └── oma-translator/ # 다국어 번역
├── workflows/       # deepinit, setup, stack-set
└── results/         # 에이전트 실행 결과 (.gitkeep)
```

### Claude 서브에이전트

```
.claude/
├── agents/          # 7개 전문 에이전트 (backend, frontend, db, qa 등)
├── hooks/           # 워크플로우 트리거, HUD
└── skills/
    ├── gstack/      # 플랜/리뷰/배포 워크플로우 (30+ 스킬)
    └── ...          # oh-my-agent 스킬 심링크
```

### CI/CD & 배포

```
.github/workflows/deploy.yml   # GitHub Actions (Docker 기반)
docker/
├── Dockerfile.server           # Express multi-stage build
├── Dockerfile.front            # Next.js standalone build
├── docker-compose.yml          # 공통 서비스 정의
├── docker-compose.dev.yml      # 개발계 오버라이드
└── docker-compose.prod.yml     # 운영계 오버라이드
```

### Git Workflow

```
main    → 운영계 자동 배포 (GitHub Actions)
dev     → 개발계 자동 배포
feat/*  → 기능 개발 (dev로 PR)
fix/*   → 버그 수정 (dev로 PR)
hotfix/* → 긴급 수정 (main + dev)
```

## 주요 스킬 명령어

| 명령어          | 역할               |
| --------------- | ------------------ |
| `/deepinit`     | 프로젝트 초기화    |
| `/setup`        | 환경 설정          |
| `/stack-set`    | 스택 구성          |
| `/office-hours` | 아이디어 검증      |
| `/autoplan`     | 자동 플랜 수립     |
| `/review`       | 코드 리뷰          |
| `/ship`         | 커밋 + PR 생성     |
| `/qa`           | 브라우저 QA 테스트 |
| `/investigate`  | 버그 조사          |

## GitHub Secrets 설정

배포를 위해 GitHub 레포 Settings → Secrets에서 설정 필요.
상세 항목은 `CONTRIBUTING.md`의 "GitHub Secrets 설정" 섹션 참조.

## 요구사항

- Node.js 24+
- bun (gstack 빌드용)
- Docker & Docker Compose (배포용)
- Claude Code CLI

## 참고 레포
Gstack - https://github.com/garrytan/gstack
oh-my-agent - https://github.com/first-fluke/oh-my-agent
