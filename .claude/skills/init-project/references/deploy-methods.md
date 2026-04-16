# 배포 방식 전환 가이드

B방식(모노레포 직접 배포)에서 Front/Back 각각의 배포 방식을 전환하는 절차.

**이 파일을 언제 읽는가:** 사용자가 "Vercel에서 PM2로 바꾸고 싶다", "Docker로 전환", "배포 방식 변경" 등을 요청할 때. `/init-project` 초기화 시 배포 방식을 선택하는 것은 `references/flow-detail.md`의 Step 4-6, 4-7에서 다룬다.

---

## 워크플로우 파일 체계

```
.github/workflows/
├── deploy-frontend-vercel.yml   ← Vercel CLI (Front 기본 활성)
├── deploy-frontend-pm2.yml      ← tar.gz + SCP + Shell (Front, workflow_dispatch만)
├── deploy-frontend-docker.yml   ← Docker (Front, workflow_dispatch만)
├── deploy-backend-pm2.yml       ← tar.gz + SCP + Shell + PM2 (Back 기본 활성)
└── deploy-backend-docker.yml    ← Docker (Back, workflow_dispatch만)
```

## 핵심 원칙: 앱당 하나만

Front와 Back 각각에 대해 **배포 방식이 하나만 `on: push` 활성화**되어야 한다. 같은 앱의 두 워크플로우가 동시에 push로 트리거되면 중복 배포가 발생한다.

### 현재 기본 상태

| 앱 | 파일 | 트리거 | 상태 |
|---|------|--------|------|
| Front | `deploy-frontend-vercel.yml` | `push` + `dispatch` | ✅ 기본 활성 |
| Front | `deploy-frontend-pm2.yml` | `dispatch` only | ⏸ 대기 |
| Front | `deploy-frontend-docker.yml` | `dispatch` only | ⏸ 대기 |
| Back | `deploy-backend-pm2.yml` | `push` + `dispatch` | ✅ 기본 활성 |
| Back | `deploy-backend-docker.yml` | `dispatch` only | ⏸ 대기 |

---

## 전환 공통 절차

어느 조합이든 전환 절차는 동일하다.

### 1단계: workflow_dispatch로 사전 테스트

코드를 바꾸기 전에, 전환할 워크플로우를 **수동 실행**으로 먼저 테스트한다.

```
GitHub 레포 → Actions 탭 → 전환할 워크플로우 선택 → Run workflow
→ branch: dev, environment: development → Run
```

이 단계에서 실패하면 코드 수정 없이 롤백 가능하다.

### 2단계: on: push 블록 전환

**비활성화할 파일:** `push:` 블록을 주석 처리

```yaml
on:
  # push:
  #   branches: [main, dev]
  #   paths:
  #     - 'apps/front/**'
  #     - '.github/workflows/deploy-frontend-vercel.yml'
  workflow_dispatch:
    # ... (유지)
```

**활성화할 파일:** 주석 처리된 `push:` 블록을 해제

```yaml
on:
  push:
    branches: [main, dev]
    paths:
      - 'apps/front/**'
      - '.github/workflows/deploy-frontend-pm2.yml'
  workflow_dispatch:
    # ... (유지)
```

### 3단계: 커밋 + 검증

```bash
git add .github/workflows/deploy-*.yml
git commit -m "chore: {front|back} 배포를 {이전}에서 {이후}로 전환"
git push origin dev
```

push 후 GitHub Actions에서:
- ✅ 새 워크플로우가 실행되는지
- ❌ 이전 워크플로우가 **실행되지 않는지**

### 4단계: 서버 사전 준비 (해당 시)

| 전환 대상 | 필요한 서버 준비 |
|----------|----------------|
| PM2 → Docker | Docker + docker-compose 설치 |
| Docker → PM2 | Node.js + PM2 설치, ecosystem.config.js 배치 |
| Vercel → PM2 | 인스턴스 서버 준비, Node.js + PM2 + Nginx |
| Vercel → Docker | 인스턴스 서버 준비, Docker + docker-compose |
| PM2/Docker → Vercel | Vercel 계정/프로젝트 설정, Git Integration Disconnect |

---

## Front 전환 시나리오

### Vercel → PM2

1. `deploy-frontend-vercel.yml`의 `push:` 주석 처리
2. `deploy-frontend-pm2.yml`의 `push:` 주석 해제
3. 서버에 Node.js, PM2, Nginx 설치
4. Infisical `/frontend/github-actions/` 경로에 `FRONT_SERVER_HOST`, `FRONT_SERVER_USER`, `FRONT_DEPLOY_DIR`, `FRONT_APP_NAME`, `FRONT_TAR_FILE`, `FRONT_SSH_PRIVATE_KEY` 등록
5. 서버에 **범용 배포 스크립트**(`~/server-deploy.sh`)를 단 한 번만 배치 — 프로젝트/환경별 스크립트 복사 불필요. 값은 워크플로우가 인자로 전달

### Vercel → Docker

1. `deploy-frontend-vercel.yml`의 `push:` 주석 처리
2. `deploy-frontend-docker.yml`의 `push:` 주석 해제
3. 서버에 Docker + docker-compose 설치
4. `apps/front/Dockerfile`, `apps/front/docker-compose.yml` 준비
5. Infisical에 `FRONT_SERVER_HOST`, `FRONT_SERVER_USER`, `FRONT_DEPLOY_DIR`, `FRONT_SSH_PRIVATE_KEY` 등록

### PM2 → Vercel

1. `deploy-frontend-pm2.yml`의 `push:` 주석 처리
2. `deploy-frontend-vercel.yml`의 `push:` 주석 해제
3. Vercel 대시보드에서 프로젝트 연결 (Root Directory: `apps/front`)
4. Settings → Git → Disconnect (GitHub Actions가 배포 주체)
5. Infisical `/frontend/github-actions/` 경로에 `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` 등록
6. Shared-Secrets `/vercel/` 경로에 `VERCEL_TOKEN` 확인

### PM2 ↔ Docker

PM2 파일의 `push:` 주석 처리 + Docker 파일의 `push:` 주석 해제 (또는 반대). 서버 준비 후 진행.

---

## Back 전환 시나리오

### PM2 → Docker

1. `deploy-backend-pm2.yml`의 `push:` 주석 처리
2. `deploy-backend-docker.yml`의 `push:` 주석 해제
3. 서버에 Docker + docker-compose 설치
4. `apps/back/Dockerfile`, `apps/back/docker-compose.yml` 준비
5. 서버에서 기존 PM2 프로세스 정리: `pm2 delete <app-name>`

### Docker → PM2

역순. Docker 컨테이너 중지 (`docker compose down`) 후 PM2 프로세스 시작 (`pm2 start ecosystem.config.js`).

---

## Infisical 시크릿 경로 차이

배포 방식에 따라 필요한 시크릿이 다르다.

### Vercel 배포 시 필요

```
(프로젝트)    /frontend/github-actions/  VERCEL_ORG_ID, VERCEL_PROJECT_ID
(Shared)      /vercel/                   VERCEL_TOKEN
```

### PM2/Docker 배포 시 필요 (Front)

```
(프로젝트)    /frontend/github-actions/  FRONT_SERVER_HOST, FRONT_SERVER_USER,
                                         FRONT_DEPLOY_DIR, FRONT_APP_NAME (PM2만),
                                         FRONT_TAR_FILE (PM2만), FRONT_SSH_PRIVATE_KEY
```

### PM2/Docker 배포 시 필요 (Back)

```
(프로젝트)    /backend/github-actions/   BACK_SERVER_HOST, BACK_SERVER_USER,
                                         BACK_DEPLOY_DIR, BACK_APP_NAME (PM2만),
                                         BACK_TAR_FILE (PM2만), BACK_SSH_PRIVATE_KEY
```

---

## 롤백

### 전환 직후 배포 실패 시

```bash
git revert HEAD   # 전환 커밋 revert → 이전 방식의 push: 블록이 복원
git push origin dev
```

### 두 워크플로우가 동시에 실행된 경우

1. 즉시 한쪽 파일의 `push:` 블록을 주석 처리하고 push
2. 서버에서 어느 배포가 마지막으로 성공했는지 확인
3. 성공한 쪽만 남기고 나머지 정리

---

## 왜 workflow_call (Reusable Workflow)을 안 쓰는가

B방식은 모노레포 1개만 쓰므로 reusable로 만들 이유가 없다. 직접 배포 구조가 더 단순하고 디버깅하기 쉽다. 파일 간 중복 코드가 있지만(Infisical 인증 블록 등), 전환이 드문 이벤트(프로젝트당 1~2회)이고 단순성 이득이 더 크다.
