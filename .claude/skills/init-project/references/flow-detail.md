# /init-project 상세 플로우

SKILL.md의 전체 플로우를 각 Step 단위로 상세히 설명한다. 각 Step에는 실행할 bash 코드, AskUserQuestion 예시, 분기 로직이 포함된다.

**이 파일을 언제 읽는가:** 스킬을 실제 실행하면서 "Step N에서 뭘 해야 하지?"라는 질문이 생겼을 때. 단순 요약만 필요하면 SKILL.md만으로 충분하다.

## Step 0: 환경 감지 (기존 dev 레포 상태)

**Step 1보다 먼저 실행된다.** 이미 운영 중인 `dev-{project}`에서 스킬이 호출된 경우를 감지한다.

```bash
# 1. git remote 확인
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo "")
# 예: https://github.com/CODIWORKS-Engineer/dev-my-app.git

# 2. remote URL에서 정보 추출 (dev-{name} 패턴)
if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+)/dev-([^/.]+)(\.git)?$ ]]; then
  DETECTED_ORG="${BASH_REMATCH[1]}"     # CODIWORKS-Engineer
  DETECTED_PROJECT="${BASH_REMATCH[2]}" # my-app
  EXISTING_DEV_REPO=true
else
  EXISTING_DEV_REPO=false
fi

echo "기존 dev 레포: $EXISTING_DEV_REPO"
echo "감지된 org: $DETECTED_ORG"
echo "감지된 프로젝트: $DETECTED_PROJECT"
```

**왜 Step 1보다 먼저인가:** Step 2의 옵션 추천과 Step 4의 재질문 생략 로직이 이 감지 결과에 의존한다. 먼저 감지해두면 이후 단계가 훨씬 매끄럽다.

**B방식 주의:** `front-{project}`, `back-{project}` 레포는 생성하지 않는 아키텍처이므로 `dev-*`만 체크한다. A방식 시절처럼 여러 레포를 확인할 필요가 없다.

## Step 1: 현재 상태 감지

프로젝트 루트에서 `apps/` 구조와 Infisical 연결 상태를 확인한다.

```bash
FRONT_EXISTS=false
BACK_EXISTS=false
[ -f "apps/front/package.json" ] && FRONT_EXISTS=true
[ -f "apps/back/package.json" ] && BACK_EXISTS=true

# .infisical.json 존재 여부도 확인 (이미 Infisical 연결되었는지)
FRONT_INFISICAL=false
BACK_INFISICAL=false
[ -f "apps/front/.infisical.json" ] && FRONT_INFISICAL=true
[ -f "apps/back/.infisical.json" ] && BACK_INFISICAL=true

echo "FRONT: $FRONT_EXISTS (infisical: $FRONT_INFISICAL)"
echo "BACK: $BACK_EXISTS (infisical: $BACK_INFISICAL)"
```

## Step 2: 초기화 옵션 선택

AskUserQuestion으로 옵션을 제시한다. **Step 0과 Step 1의 감지 결과를 질문 본문에 함께 표시**해서 사용자가 현재 상태를 한눈에 파악할 수 있게 한다.

**각 option에는 반드시 label과 description 둘 다 채운다.**

### 기존 dev 레포가 있고 한쪽만 존재하는 경우 (핵심 유스케이스)

```yaml
question: |
  현재 상태:
    apps/front/: 있음
    apps/back/:  없음
    dev 레포: CODIWORKS-Engineer/dev-my-app (감지됨)

  프로젝트 초기화 옵션을 선택해주세요.
header: "초기화 옵션"
options:
  - label: "기존 레포 통합 (import) (Recommended)"
    description: "별도 back 레포의 소스를 커밋 히스토리 보존하며 apps/back/으로 통합합니다. 이후 apps/back/** 변경 시 deploy-backend-pm2.yml이 자동 실행됩니다."
  - label: "Backend만 새로 설정"
    description: "Express 5 + Prisma + BaseController + 미들웨어 스택 + 인증 시스템 + 유틸리티를 새로 생성합니다"
  - label: "초기환경 건너뛰기"
    description: "소스코드 변경 없이 Infisical 연결 / Secrets 등록 단계로 넘어갑니다"
```

### 신규 프로젝트 (dev 레포 없음, 소스도 없음)

```yaml
question: |
  현재 상태:
    apps/front/: 없음
    apps/back/:  없음
    dev 레포: 없음 (신규)

  프로젝트 초기화 옵션을 선택해주세요.
header: "초기화 옵션"
options:
  - label: "전체 초기화 (front + back) (Recommended)"
    description: "oma-frontend, oma-backend 스킬 기반으로 아키텍처, 유틸, 공용함수까지 포함된 프로덕션 레디 보일러플레이트를 생성합니다"
  - label: "Frontend만 설정"
    description: "Next.js 15 + FSD-lite + shadcn/ui + TanStack Query + api-client 구조를 생성합니다"
  - label: "Backend만 설정"
    description: "Express 5 + Prisma + BaseController + 미들웨어 스택 + 인증 시스템 + 유틸리티를 생성합니다"
  - label: "초기환경 건너뛰기"
    description: "이미 소스코드가 있는 경우. 바로 Infisical 연결 / 레포 생성 단계로 넘어갑니다"
  - label: "기존 레포 통합 (import)"
    description: "이미 front/back이 별도 레포로 존재하는 경우. git subtree add로 커밋 히스토리를 보존하며 모노레포로 통합합니다"
```

### 추천 로직 테이블 (Step 0 + Step 1 결합)

| 기존 dev 레포 | front 존재 | back 존재 | 추천 |
|---------------|-----------|----------|------|
| 없음 | X | X | A) 전체 초기화 |
| 없음 | O | X | C) Backend만 설정, E) 기존 레포 통합 |
| 없음 | X | O | B) Frontend만 설정, E) 기존 레포 통합 |
| 없음 | O | O | D) 건너뛰기 |
| **있음** | **O** | **X** | **E) 기존 레포 통합 (Recommended)** |
| **있음** | **X** | **O** | **E) 기존 레포 통합 (Recommended)** |
| 있음 | O | O | D) 건너뛰기 |
| 있음 | X | X | A) 전체 초기화 |

**핵심 규칙:** 기존 dev 레포가 있고 `apps/` 중 한쪽만 있으면 E 옵션을 무조건 최우선 추천한다. 이게 가장 자주 일어나는 시나리오다.

## Step 3: 스캐폴딩 또는 Import 실행

선택에 따라 분기한다.

- **A~C 선택:** 서브에이전트로 스캐폴딩. 상세 프롬프트는 `references/scaffolding-prompts.md` 참조
- **E 선택:** git subtree add로 기존 레포 통합. 상세는 `references/import-mode.md` 참조
- **D 선택 (건너뛰기):** 스캐폴딩(코드 생성)은 하지 않지만, **별도 레포에서 소스를 가져올지** 후속 질문을 한다.

**D 옵션 선택 후 후속 질문 (중요):**

사용자가 "코드가 이미 있어"라고 생각해서 D를 선택했더라도, 그 코드가 **별도 레포에 있을 수 있다.** D를 선택한 직후 다음 질문을 한다:

```yaml
question: |
  기존에 별도 레포(GitHub 등)에서 관리하던 front 또는 back 소스를 가져와야 하나요?
  (git subtree add로 커밋 히스토리를 보존하며 통합합니다)
header: "기존 레포 통합 여부"
options:
  - label: "예, 별도 레포에서 가져올 소스가 있어요"
    description: "GitHub 레포 URL을 입력하면 apps/front/ 또는 apps/back/으로 통합합니다 (히스토리 보존)"
  - label: "아니오, 이미 로컬에 다 있어요"
    description: "소스가 이미 apps/front/, apps/back/ 디렉토리에 배치되어 있습니다. 바로 레포 생성으로 넘어갑니다"
```

- **"예" 선택:** → `references/import-mode.md`의 E-1 ~ E-5 플로우로 자동 전환. E 옵션과 동일하게 진행된다.
- **"아니오" 선택:** → Step 4로 바로 이동. 코드 생성도, import도 하지 않는다.

**왜 이 질문이 필요한가:** 사용자 입장에서 "건너뛰기"와 "기존 레포 통합"의 차이가 명확하지 않을 수 있다. "코드는 이미 있어"라는 말이 "로컬에 다 있다"와 "다른 레포에 있다"를 모두 포함할 수 있기 때문에, 명시적으로 물어서 올바른 경로로 유도한다.

**D 옵션 "아니오" 이후의 2가지 케이스:**

1. **기존 dev 레포 있음 + front/back 둘 다 있음 (Step 0에서 감지):**
   이미 운영 중인 프로젝트에서 Infisical 연결이나 Secrets 재등록만 필요한 경우.
   → Step 4-1에서 감지된 정보(project-name, org)를 확인만 받고 4-2, 4-3은 건너뜀
   → Step 7의 `init-project.sh`는 idempotent하게 동작 — 레포 이미 존재하면 "건너뜀"

2. **기존 dev 레포 없음 + front/back 둘 다 있음:**
   사용자가 코드를 먼저 작성하고 레포 생성을 나중에 하는 경우.
   → Step 4-2(프로젝트명), 4-3(Org), 4-4(Infisical), 4-5(Machine Identity) 전부 질문
   → Step 7에서 새 `dev-{project}` 레포 생성

**두 케이스 모두 Step 0의 `EXISTING_DEV_REPO` 값에 따라 Step 4의 질문이 자동으로 조정된다.**

A 옵션(전체 초기화)은 frontend/backend 서브에이전트를 **병렬로** 실행한다. 단일 메시지에 두 서브에이전트 호출을 넣는다.

## Step 4: 프로젝트 정보 수집

### 4-1. 기존 레포에서 추론 (Step 0에서 감지된 경우)

**기존 dev 레포가 감지되면 새로 질문하지 않고 추론된 정보를 확인만 받는다.** 사용자가 이미 알고 있는 정보를 다시 묻는 것은 시간 낭비이자 오류 위험이다.

```yaml
question: |
  기존 레포에서 다음 정보를 감지했습니다. 맞으면 확인, 수정이 필요하면 직접 입력을 선택해주세요.

    프로젝트명: my-app
    Org: CODIWORKS-Engineer
header: "프로젝트 정보 확인"
options:
  - label: "확인 (Recommended)"
    description: "감지된 정보로 진행합니다"
  - label: "직접 입력"
    description: "프로젝트명 또는 Organization을 수정합니다"
```

### 4-2. 프로젝트 이름 (신규 레포인 경우에만)

```yaml
question: "프로젝트 이름을 입력해주세요. (예: my-app → dev-my-app 레포가 생성됩니다)"
header: "프로젝트명"
options:
  - label: "{현재 디렉토리명}"
    description: "현재 디렉토리명 기반으로 레포를 생성합니다"
  - label: "직접 입력"
    description: "Other를 선택하고 프로젝트 이름을 입력하세요 (예: my-app)"
```

### 4-3. Organization (신규 레포인 경우에만)

B방식은 레포 1개만 생성하므로 org도 하나만 묻는다.

```yaml
question: "dev 레포가 생성될 GitHub Organization을 선택해주세요"
header: "GitHub Org"
options:
  - label: "CODIWORKS-Engineer (Recommended)"
    description: "dev-{name} 레포가 CODIWORKS-Engineer Org에 생성됩니다"
  - label: "직접 입력"
    description: "Other를 선택하고 Organization 이름을 입력하세요"
```

### 4-4. Infisical Project ID

```yaml
question: |
  Infisical 프로젝트 ID를 입력해주세요.

  사전 준비:
    1. https://env.co-di.com 에서 프로젝트 생성
    2. Project Settings → Copy Project ID
header: "Infisical Project ID"
options:
  - label: "직접 입력"
    description: "Infisical 대시보드에서 복사한 Project ID를 입력하세요 (UUID 형식)"
```

### 4-5. Machine Identity (Universal Auth)

이 단계는 4개의 하위 안내로 구성된다. **사용자에게 순서대로 안내**하고, 마지막에 Client ID와 Client Secret을 **한 번에** 입력받는다.

**중요:** Machine Identity는 **Organization 레벨**에서 생성하고, 필요한 **프로젝트들에 개별 추가**하는 구조이다. 프로젝트 내부에서 생성하는 것이 아니다.

```
Organization Level:
  └── Machine Identity: ci-{project}-deploy
        ├── Org Role: No Access (Organization 리소스 접근 불필요)
        ├── Projects:
        │     ├── {project}        → Role: Developer
        │     └── Shared-Secrets   → Role: Developer
        └── Authentication:
              └── Universal Auth → Client Secret: ci-{project}-secret-key (TTL: 0)
```

#### 4-5-1. Machine Identity 생성 (Organization 레벨)

```yaml
question: |
  Infisical Machine Identity를 Organization 레벨에서 생성해주세요.

  Organization Settings → Access Control → Machine Identities → Create Machine Identity

  입력 항목:
    - Name: ci-{project}-deploy  (예: ci-myApp-deploy)
    - Org Role: No Access

  ※ Organization 리소스에는 접근할 필요가 없으므로 Org Role은 No Access로 설정합니다.

  생성 완료 후 다음으로 넘어가세요.
header: "Machine Identity 생성"
options:
  - label: "생성 완료"
    description: "Machine Identity를 Organization 레벨에서 생성했습니다."
```

#### 4-5-2. 프로젝트 접근 권한 추가

```yaml
question: |
  생성한 Machine Identity에 프로젝트 접근 권한을 추가해주세요.
  2개 프로젝트에 각각 추가해야 합니다.

  1. {project} 프로젝트 추가:
     - {project} 프로젝트 → Access Control → Machine Identities → Add
     - ci-{project}-deploy 선택 → Role: Developer

  2. Shared-Secrets 프로젝트 추가:
     - Shared-Secrets 프로젝트 → Access Control → Machine Identities → Add
     - ci-{project}-deploy 선택 → Role: Developer

  ※ Shared-Secrets는 VERCEL_TOKEN, Slack 토큰 등 여러 프로젝트가 공유하는 시크릿을 보관합니다.

  2개 프로젝트 모두 추가 완료 후 다음으로 넘어가세요.
header: "프로젝트 접근 권한 추가"
options:
  - label: "추가 완료"
    description: "{project}와 Shared-Secrets 프로젝트에 Machine Identity를 추가했습니다."
```

#### 4-5-3. Client Secret 발급

```yaml
question: |
  생성한 Machine Identity의 상세 페이지에서:

  Authentication 탭 → Universal Auth → Add Client Secret

  입력 항목:
    - Description: ci-{project}-secret-key  (예: ci-myApp-secret-key)
    - TTL: 0  (만료 없음)
    - Max Number of Uses: 0  (무제한)

  ⚠️  생성 직후 표시되는 Client Secret은 이 화면에서만 볼 수 있습니다.
      반드시 Client ID와 Client Secret을 모두 복사해두세요!

  복사 완료 후 다음으로 넘어가세요.
header: "Client Secret 발급"
options:
  - label: "복사 완료"
    description: "Client ID와 Client Secret을 모두 복사했습니다."
```

#### 4-5-4. Client ID / Client Secret 입력

```yaml
question: |
  복사한 Client ID와 Client Secret을 입력해주세요.
  (GitHub Secrets에 INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET으로 등록됩니다)
header: "Infisical Credentials 입력"
options:
  - label: "직접 입력"
    description: "Client ID와 Client Secret을 입력하세요"
```

**구현 안내:** AskUserQuestion을 2회 호출한다.
1. 첫 번째: Client ID 입력 ("Client ID를 입력해주세요")
2. 두 번째: Client Secret 입력 ("Client Secret을 입력해주세요")

수집한 값은 환경변수로 export해서 `init-project.sh`에 전달한다:

```bash
export INFISICAL_PROJECT_ID="<project-id>"
export INFISICAL_CLIENT_ID="<client-id>"
export INFISICAL_CLIENT_SECRET="<client-secret>"
```

### 4-6. Frontend 배포 방식 선택

`apps/front/`이 최종적으로 프로젝트에 포함되는 경우에만 질문한다. back만 있는 프로젝트에서는 건너뛴다.

프론트엔드는 **4가지** 선택지가 있다. React SPA와 Next.js SSR은 같은 `deploy-frontend-pm2.yml` 워크플로우를 쓰지만 **서버 재시작 방식이 다르므로** 구분해서 묻는다.

```yaml
question: |
  Frontend 배포 방식을 선택해주세요.

  - Vercel       : SaaS, 가장 간편. Vercel 계정/프로젝트 필요
  - SSR (PM2)    : Next.js 등 SSR 앱. 빌드 → tar.gz → SCP → PM2 재시작
  - SPA (Static) : React SPA (CRA/Vite) 등 정적 파일. tar.gz → SCP → current/ 교체
                   Nginx가 current/ 를 자동 서빙 (재시작 불필요)
  - Docker       : Docker 이미지 빌드 → SCP → docker compose up
header: "Frontend 배포 방식"
options:
  - label: "Vercel (Recommended)"
    description: "Vercel CLI로 배포. 가장 간편하고 CDN/Edge 자동 적용. deploy-frontend-vercel.yml 활성화"
  - label: "SSR - PM2 (Next.js 등)"
    description: "Next.js SSR 앱용. deploy-frontend-pm2.yml 활성화 + FRONT_APP_TYPE=pm2"
  - label: "SPA - Static (React 등)"
    description: "React SPA 등 정적 파일. deploy-frontend-pm2.yml 활성화 + FRONT_APP_TYPE=static (PM2 단계 건너뜀)"
  - label: "Docker"
    description: "Docker 이미지 빌드 → 인스턴스 서버 전송 → docker compose 재시작. deploy-frontend-docker.yml 활성화"
```

선택 결과에 따라 **해당 워크플로우 파일의 `on: push` 블록만 활성화**하고, Infisical에 `FRONT_APP_TYPE`을 등록한다.

| 선택 | 활성화 파일 | FRONT_APP_TYPE (Infisical) |
|------|------------|----------------------------|
| Vercel | `deploy-frontend-vercel.yml` | — (사용 안 함) |
| SSR (PM2) | `deploy-frontend-pm2.yml` | `pm2` |
| SPA (Static) | `deploy-frontend-pm2.yml` | `static` |
| Docker | `deploy-frontend-docker.yml` | — (사용 안 함) |

**왜 SPA에서 Nginx 설정을 여기서 묻지 않는가:** Nginx root 경로 설정은 **서버 프로비저닝 시 1회만** 진행하면 되는 작업이다. 한 번 `{BASE_PATH}/current/` 또는 그 하위 빌드 디렉토리를 가리키도록 설정해두면, 이후 배포는 `current/`만 교체하면 자동 반영된다. 배포 파이프라인이 매번 Nginx를 건드릴 이유가 없다. 상세는 `references/deploy-methods.md`의 "React SPA 프로젝트 세팅 체크리스트" 참조.

### 4-7. Backend 배포 방식 선택

`apps/back/`이 최종적으로 프로젝트에 포함되는 경우에만 질문한다. front만 있는 프로젝트에서는 건너뛴다.

```yaml
question: |
  Backend 배포 방식을 선택해주세요.

  - PM2    : 레거시 Jenkins 방식. 빌드 → tar.gz → SCP → Shell (PM2 restart)
  - Docker : Docker 이미지 빌드 → SCP → docker compose up
header: "Backend 배포 방식"
options:
  - label: "PM2 (Recommended)"
    description: "빌드 → tar.gz 압축 → 인스턴스 서버 SCP → PM2 restart. deploy-backend-pm2.yml 활성화"
  - label: "Docker"
    description: "Docker 이미지 빌드 → 인스턴스 서버 전송 → docker compose 재시작. deploy-backend-docker.yml 활성화"
```

| 선택 | 활성화 파일 | 비활성 파일 |
|------|------------|------------|
| PM2 | `deploy-backend-pm2.yml` | docker (dispatch만) |
| Docker | `deploy-backend-docker.yml` | pm2 (dispatch만) |

### 배포 방식 적용 (Step 7 이후)

사용자의 선택에 따라 **워크플로우 파일의 `on:` 블록을 수정**해야 한다. 이 작업은 `init-project.sh`가 끝난 후 **수동으로 진행하거나**, 스킬이 직접 sed/Edit으로 처리한다.

**활성화 방법:** 선택된 파일의 주석 처리된 `push:` 블록을 해제하고, 나머지 파일의 `push:` 블록을 주석 처리한다.

```bash
# 예: front=PM2, back=Docker 선택 시
# deploy-frontend-pm2.yml    → push: 블록 주석 해제
# deploy-frontend-vercel.yml → push: 블록 주석 처리
# deploy-frontend-docker.yml → 그대로 (이미 주석)
# deploy-backend-docker.yml  → push: 블록 주석 해제
# deploy-backend-pm2.yml     → push: 블록 주석 처리
```

**왜 `init-project.sh`에 넣지 않는가:** 배포 방식 선택은 워크플로우 YAML 파일의 주석 토글이라 bash sed로 안정적으로 처리하기 어렵다. 스킬이 Edit 도구로 직접 수정하는 것이 더 안전하다.

## Step 5: Infisical 프로젝트 연결

`apps/front/.infisical.json`, `apps/back/.infisical.json`을 올바른 구조로 생성하거나 덮어쓴다.

**올바른 `.infisical.json` 구조:**

```json
{
  "workspaceId": "<INFISICAL_PROJECT_ID>",
  "defaultEnvironment": "local-dev",
  "gitBranchToEnvironmentMapping": {
    "main": "prod",
    "dev": "dev"
  }
}
```

`infisical init`으로 생성하면 `defaultEnvironment: "dev"`, `gitBranchToEnvironmentMapping: null`로 생성되는데, 이 기본값은 **프로젝트 관례와 다르다.** 반드시 위 구조로 덮어쓴다.

- `defaultEnvironment: "local-dev"` — 로컬 개발 시 사용할 환경. `infisical run`의 기본값
- `gitBranchToEnvironmentMapping` — 브랜치별 환경 매핑. CI/CD에서 자동으로 올바른 환경을 선택

```bash
# apps/front, apps/back 각각에 .infisical.json 생성/덮어쓰기
for app_dir in apps/back apps/front; do
  if [ -d "$app_dir" ]; then
    cat > "$app_dir/.infisical.json" << EOF
{
  "workspaceId": "${INFISICAL_PROJECT_ID}",
  "defaultEnvironment": "local-dev",
  "gitBranchToEnvironmentMapping": {
    "main": "prod",
    "dev": "dev"
  }
}
EOF
  fi
done
```

**파일이 이미 존재하는 경우:** 위 명령이 덮어쓴다. 기존에 `infisical init`으로 생성된 파일이든, import된 레포에서 가져온 파일이든 **프로젝트 관례에 맞게 통일**한다.

**`apps/` 디렉토리가 없는 경우:** 해당 앱이 프로젝트에 포함되지 않으므로 건너뛴다.

## Step 6: Git 초기화

Git이 초기화되어 있지 않으면 초기화한다.

```bash
if [ ! -d ".git" ]; then
  git init -b main
  git add -A
  git commit -m "chore: 프로젝트 초기 설정"
fi
```

이미 Git이 있지만 커밋되지 않은 변경사항이 있으면 커밋한다.

```bash
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "chore: 프로젝트 초기 환경 설정 완료"
fi
```

## Step 7: init-project.sh 실행

B방식의 `init-project.sh`는 **단순**하다. `--mode`, `--front-org`, `--back-org`, `--deploy-method` 같은 A방식 옵션은 **전부 없다.**

```bash
./scripts/init-project.sh {project-name} [--org {org}]
```

- 인자 1개(필수): 프로젝트 이름
- `--org` 옵션: GitHub Organization (기본값: `CODIWORKS-Engineer`)
- 환경변수(권장): `INFISICAL_PROJECT_ID`, `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`

사전 조건 체크:
1. `gh auth status` — GitHub CLI 로그인 상태
2. `infisical` CLI 설치 여부 (없으면 warn만, CI는 영향 없음)
3. 대상 Organization에 레포 생성 권한

**`init-project.sh`가 수행하는 것:**
1. `dev-{project}` 레포 생성 (이미 존재하면 건너뜀 — 안전)
2. `codi-engineers` 팀 admin 권한 부여
3. `.infisical.json` workspaceId 치환 (환경변수가 있는 경우)
4. GitHub Secrets 등록: `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`
5. Git remote → `dev-{project}` 설정
6. `main`, `dev` 브랜치 생성 + push

## Step 8: 완료 안내

사용자에게 출력할 완료 메시지는 다음 구조를 따른다.

```
════════════════════════════════════════════════════════════
  Project {name} initialized! (B방식 + Infisical)
════════════════════════════════════════════════════════════

  Repo: https://github.com/{org}/dev-{name}

  GitHub Secrets:
    ✅ INFISICAL_CLIENT_ID
    ✅ INFISICAL_CLIENT_SECRET
    → 나머지 모든 시크릿은 Infisical에서 런타임 조회

  GitHub Actions 워크플로우:
    ✅ deploy-frontend.yml        (Vercel CLI 자동 배포)
    ✅ deploy-backend-pm2.yml     (PM2 자동 배포 — 기본 활성)
    ⏸  deploy-backend-docker.yml  (workflow_dispatch만 활성 — 전환 대기)

════════════════════════════════════════════════════════════
  수동 설정 필요
════════════════════════════════════════════════════════════

  1. Vercel 연결
     - ai@co-di.com 계정으로 Vercel 로그인
     - New Project → dev-{name} 레포 선택
     - Root Directory: apps/front
     - 최초 배포 후 Settings → Git → Disconnect

  2. Infisical 시크릿 입력 (https://env.co-di.com)
     ⚡ 템플릿: apps/back/.env.example, apps/front/.env.example 에 최소 필요 변수가
        정의되어 있다. 이 파일을 열어 key 목록을 참고하면서 Infisical 에 등록한다.
     - /backend/                   런타임 .env (apps/back/.env.example 참고)
     - /backend/github-actions/    BACK_SERVER_HOST, BACK_SERVER_USER,
                                   BACK_DEPLOY_DIR, BACK_APP_NAME,
                                   BACK_TAR_FILE, BACK_SSH_PRIVATE_KEY,
                                   BACK_APP_TYPE (선택, 기본 pm2)
     - /frontend/                  NEXT_PUBLIC_* (apps/front/.env.example 참고)
     - /frontend/github-actions/   (Vercel 배포 시)   VERCEL_ORG_ID, VERCEL_PROJECT_ID
                                   (PM2/Static 배포 시) FRONT_SERVER_HOST, FRONT_SERVER_USER,
                                                      FRONT_DEPLOY_DIR, FRONT_APP_NAME,
                                                      FRONT_TAR_FILE, FRONT_SSH_PRIVATE_KEY,
                                                      FRONT_APP_TYPE (pm2 | static)
     - (Shared) /slack/            slack_bot_token, slack_channel
     - (Shared) /vercel/           VERCEL_TOKEN

  3. Infisical → Vercel Integration (권장)

  4. 배포 서버 사전 준비
     - Node.js, PM2 설치 (PM2 방식)
     - SSH authorized_keys 에 공개키 등록
     - scripts/server-deploy.sh 를 ~/server-deploy.sh 로 배치 (최초 1회, 모든 프로젝트 공유)
         scp scripts/server-deploy.sh rocky@<server>:~/server-deploy.sh
         ssh rocky@<server> "chmod +x ~/server-deploy.sh"
     - 프로젝트별 후처리가 필요하면 {BASE_PATH}/post-deploy.sh 배치
       (예: puppeteer chrome 설치)

════════════════════════════════════════════════════════════
  개발 시작
════════════════════════════════════════════════════════════

  # 최초에는 .env 로 개발 가능 (cp .env.example .env.development)
  cd apps/front && npm run dev    # http://localhost:3000
  cd apps/back && npm run dev     # http://localhost:8080

  # Infisical 사용 준비되면 1회만 로그인. 이후 같은 npm run dev 가 자동 전환
  # infisical login --domain=https://env.co-di.com

  git push origin dev   # → development 환경
  git push origin main  # → production 환경
```

**dev-runner 자동 분기:** `npm run dev` 는 `scripts/dev-runner.js` 를 거쳐 Infisical 연결 여부를 런타임에 감지한다. CLI 설치 + 로그인 + `.infisical.json` 유효성을 모두 만족하면 `infisical run` 으로, 하나라도 부족하면 로컬 `.env` 로 자동 fallback 한다. 사용자는 `dev:no-infisical` 같은 별도 명령을 외울 필요가 없다.
