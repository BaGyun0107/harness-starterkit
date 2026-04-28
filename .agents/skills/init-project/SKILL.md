---
name: init-project
description: |
  프로젝트 초기화 오케스트레이터. 모노레포 직접 배포(B방식)로 dev-{project} 레포를
  생성하고, apps/front(Next.js) + apps/back(Express) 스캐폴딩, Infisical 프로젝트 연결,
  GitHub Secrets 등록까지 한 번에 처리한다. 기존 별도 레포(front-*/back-*)를 git subtree
  add로 모노레포에 통합하는 시나리오도 지원한다.
  "프로젝트 초기화", "새 프로젝트 만들기", "init project", "프로젝트 세팅", "프로젝트 셋업",
  "환경 설정", "boilerplate", "스캐폴딩", "기존 레포 합치기", "dev 레포에 통합" 등의 맥락에서
  반드시 이 스킬을 사용한다. 사용자가 단순히 "프로젝트 시작" 같은 말만 해도 이 스킬이
  적합하다면 바로 트리거하라. 이 스킬을 쓰지 않고 직접 init-project.sh를 호출하면 Step 0
  환경 감지와 E 옵션 부분 import 로직을 건너뛰게 되어 품질이 떨어진다.
---

# /init-project — 프로젝트 초기화 오케스트레이터

새 프로젝트를 처음부터 끝까지 자동으로 셋업하거나, 기존 운영 중인 `dev-{project}`에 별도 레포를 통합하는 스킬.

## 아키텍처 (B방식)

이 스킬은 **모노레포 직접 배포** 아키텍처를 전제로 한다. 과거 A방식(subtree split → front-*/back-* 배포 레포)은 폐기됐다.

- **레포 1개:** `dev-{project}` 만 생성. `front-*`, `back-*` 레포는 더 이상 만들지 않는다
- **배포:** GitHub Actions가 `paths` 필터로 변경된 앱만 직접 배포. 프로젝트당 front/back 각각 **하나만** `on: push` 활성화
  - Front: `deploy-frontend-vercel.yml` (Vercel CLI, 기본) / `deploy-frontend-pm2.yml` / `deploy-frontend-docker.yml`
  - Back: `deploy-backend-pm2.yml` (기본) / `deploy-backend-docker.yml`
- **시크릿:** Infisical (https://env.co-di.com) 단일 진실 소스. GitHub Secrets는 `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` **2개만**

## 전체 플로우 (8단계)

```
/init-project
  │
  ├── Step 0: 환경 감지 — git remote에서 dev-{name} 패턴 추론
  ├── Step 1: 현재 상태 감지 — apps/front, apps/back 존재 여부
  ├── Step 2: 초기화 옵션 선택 (A~E)
  │           A) 전체 초기화 / B) Frontend만 / C) Backend만
  │           D) 건너뛰기 / E) 기존 레포 통합 (import)
  ├── Step 3: 스캐폴딩 또는 Import 실행
  ├── Step 4: 프로젝트 정보 수집 — 기존 레포면 추론, 신규면 질문
  │           + Infisical Project ID / Machine Identity 수집
  │           + Front 배포 방식 (Vercel / PM2 / Docker)
  │           + Back 배포 방식 (PM2 / Docker)
  ├── Step 5: Infisical 연결 — .infisical.json workspaceId 치환
  ├── Step 6: Git 초기화 / 커밋
  ├── Step 7: scripts/init-project.sh 실행 — dev 레포 생성 + Secrets 등록
  └── Step 8: 완료 안내 — Vercel 연결, Infisical 시크릿 입력 등 수동 작업
```

## 참조 지도 — 언제 어떤 파일을 읽을지

이 SKILL.md는 진입점이다. 각 Step의 상세 절차, 코드, 프롬프트 전문은 아래 파일들에 분리되어 있다. **필요할 때만** 로드하라 — 모든 파일을 한 번에 읽을 필요는 없다.

| 파일 | 내용 | 언제 읽는가 |
|------|------|------------|
| `references/flow-detail.md` | Step 0~8 각 단계의 상세 bash 코드, AskUserQuestion YAML, 분기 로직 | 스킬을 실제 실행하면서 "이 Step에서 뭘 해야 하지?"라는 질문이 생겼을 때 |
| `references/scaffolding-prompts.md` | Step 3의 frontend-engineer / backend-engineer 서브에이전트 프롬프트 전문 | Step 2에서 A/B/C 옵션이 선택된 직후 (E/D는 불필요) |
| `references/import-mode.md` | Step 3-E 기존 레포 통합의 E-1~E-5 상세 + 트러블슈팅 | Step 2에서 E 옵션이 선택됐거나 사용자가 "기존 레포 합치기" 요청 |
| `references/deploy-methods.md` | PM2 ↔ Docker 배포 방식 전환 절차 | 초기화 시에는 **불필요**. 사용자가 "Docker로 바꾸고 싶다" 요청할 때만 |
| `references/scenarios.md` | 4가지 대표 시나리오의 Step별 전체 플로우 | Step 0/1 감지 후 "어느 시나리오인가" 판단이 필요할 때 |

**읽는 순서 권장:**
1. SKILL.md (이 파일) — 항상 전체
2. `references/flow-detail.md` — Step 실행 직전에 해당 섹션
3. A/B/C면 `scaffolding-prompts.md`, E면 `import-mode.md`
4. 혼란스러울 때 `scenarios.md`로 전체 흐름 재확인

## 시나리오 요약표 (빠른 판단용)

Step 0/1의 감지 결과로 어느 시나리오인지 즉시 판단한다. 상세 플로우는 `references/scenarios.md` 참조.

| 기존 dev 레포 | front | back | 시나리오 | 추천 옵션 |
|---------------|-------|------|----------|-----------|
| 없음 | X | X | 1. 완전 신규 | **A) 전체 초기화** |
| 없음 | O | O | 2. 소스 있는 신규 | **D) 건너뛰기** |
| **있음** | **O** | **X** | **3. back 통합 (핵심 UC)** | **E) 기존 레포 통합** |
| **있음** | **X** | **O** | **4. front 통합** | **E) 기존 레포 통합** |

**핵심 규칙:** 기존 `dev-*` 레포가 있고 `apps/` 중 한쪽만 있으면 **E 옵션을 최우선 추천**한다. 이게 B방식 전환 후 가장 자주 발생하는 패턴이다.

## 필수 사전 조건

스킬 실행 전 다음이 준비되어 있어야 한다. 누락 시 Step 7(`init-project.sh`)에서 실패한다.

1. **GitHub CLI 로그인:** `gh auth status`로 확인
2. **Infisical 프로젝트 생성됨:** https://env.co-di.com 에서 미리 생성, Project ID 확보
3. **Infisical Machine Identity (Universal Auth):** Client ID/Secret 발급 완료
4. **대상 Organization 레포 생성 권한:** 일반적으로 `CODIWORKS-Engineer`
5. **(옵션) Infisical CLI 로컬 설치:** `brew install infisical/get-cli/infisical` — 없어도 CI는 동작하지만 로컬 개발에 필요

## 주의사항

- **서브에이전트는 병렬로.** A 옵션(전체 초기화) 선택 시 frontend-engineer와 backend-engineer를 **단일 메시지에 동시 호출**해서 병렬 실행한다. 순차 호출하면 시간이 두 배로 든다.
- **스킬 파일을 먼저 읽혀라.** 서브에이전트가 `oma-frontend/oma-backend`의 아키텍처 규칙을 모르는 상태에서 코드를 쓰기 시작하면 관례와 어긋나는 결과물이 나온다. 프롬프트 1단계에 "스킬 파일 읽기"를 반드시 명시한다 (상세는 `references/scaffolding-prompts.md`).
- **기존 디렉토리를 덮어쓰지 마라.** 존재하면 해당 스캐폴딩을 건너뛴다.
- **`git subtree add`는 멱등하지 않다.** E 옵션에서 대상 경로가 비어있지 않으면 실패한다. `references/import-mode.md`의 E-3 사전 체크 참조.
- **브랜치 이름을 가정하지 마라.** E-2에서 `gh repo view --json defaultBranchRef`로 자동 감지. `main`이 아닌 레포가 많다.
- **`init-project.sh`는 idempotent하다.** 기존 dev 레포가 있어도 "건너뜀" 로그를 남기고 안전하게 진행한다. Step 7을 두 번 실행해도 문제없다.
- **Client Secret은 복사 즉시 저장.** Infisical UI는 Machine Identity Secret을 한 번만 보여준다. Step 4-5에서 사용자에게 명시적으로 안내하라.
- **B방식 전제를 위반하는 옵션을 쓰지 마라.** `--mode`, `--front-org`, `--back-org`, `--deploy-method` 같은 플래그는 A방식 잔재이고 현재 `init-project.sh`에 **존재하지 않는다.** `./scripts/init-project.sh <name> [--org <org>]` 시그니처만 유효하다.
- **PM2/Docker 동시 활성 금지.** 두 워크플로우가 같은 push에 트리거되면 중복 배포된다. 프로젝트당 하나만 `on: push`를 활성화. 상세는 `references/deploy-methods.md`.
