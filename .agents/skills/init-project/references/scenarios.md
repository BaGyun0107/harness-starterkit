# /init-project 시나리오별 플로우

4가지 대표 시나리오에 대한 Step 0~8 상세 플로우. AI가 "사용자 상황이 어느 시나리오에 해당하는지" 판단한 뒤, 해당 경로만 따라가면 된다.

**이 파일을 언제 읽는가:** Step 0/1의 환경 감지를 마친 뒤, "이제 어떤 순서로 가야 하지?"를 판단할 때. SKILL.md의 시나리오 요약표만으로 충분하다면 이 파일은 스킵해도 된다.

---

## 시나리오 1: 완전 신규 프로젝트

**상황:** 사용자가 빈 디렉토리에서 프로젝트를 처음 시작. 레포도 소스도 아직 없음.

```
/init-project
  → Step 0: 기존 레포 없음 (ORIGIN_URL 없음 또는 dev-* 패턴 아님)
  → Step 1: apps/front 없음, apps/back 없음
  → Step 2: A) 전체 초기화 (Recommended)
            - front/back 둘 다 없으므로 A를 최우선으로 제시
  → Step 3: frontend-engineer + backend-engineer 서브에이전트 병렬 실행
            - scaffolding-prompts.md의 프롬프트 전문 사용
            - A 옵션이므로 반드시 단일 메시지에 두 서브에이전트 호출
  → Step 4:
      4-2: 프로젝트 이름 질문 (기본값: 현재 디렉토리명)
      4-3: Org 질문 (기본값: CODIWORKS-Engineer)
      4-4: Infisical Project ID 질문
      4-5: Machine Identity (Client ID/Secret) 질문
  → Step 5: .infisical.json workspaceId 치환
            - 스캐폴딩이 .infisical.json을 생성했다면 치환
            - 없다면 init-project.sh가 경고만 출력
  → Step 6: git init -b main + commit
  → Step 7: ./scripts/init-project.sh {name} --org {org}
            - 환경변수로 INFISICAL_* 전달
  → Step 8: Vercel 연결 / Infisical 시크릿 입력 / 서버 사전 준비 안내
```

**예상 소요 시간:** 스캐폴딩(병렬)이 가장 긴 단계. 5~10분. Infisical 수동 입력까지 포함하면 15~20분.

---

## 시나리오 2: 이미 소스가 있는 신규 프로젝트

**상황:** 사용자가 기존 코드를 가지고 하네스 구조에 맞춰 배치한 뒤 `/init-project` 실행.

```
/init-project
  → Step 0: 기존 레포 없음
  → Step 1: apps/front 있음, apps/back 있음
  → Step 2: D) 건너뛰기 (Recommended)
            - 둘 다 있으므로 스캐폴딩 불필요
  → Step 3: D 후속 질문 — "별도 레포에서 가져올 소스가 있나요?"
        → "아니오" (로컬에 이미 있음) → 건너뜀
        → "예" → E-1~E-5 import 플로우로 자동 전환 (import-mode.md 참조)
  → Step 4: 4-2 ~ 4-5 (프로젝트명, Org, Infisical 정보 수집)
  → Step 5: .infisical.json 치환
  → Step 6: git commit (미커밋 변경사항이 있으면)
  → Step 7: init-project.sh {name}
  → Step 8: 완료 안내
```

**주의:** 기존 코드가 하네스의 관례(FSD-lite, BaseController 등)를 따르지 않을 수 있다. 사용자에게 명시적으로 안내하라.

---

## 시나리오 3: 기존 dev 레포에 별도 back 레포 통합 (핵심 유스케이스)

**상황:** `dev-my-app`이 이미 운영 중이고 `apps/front/`만 있음. 별도 `back-my-app` 레포의 소스를 모노레포로 흡수하고 싶음.

```
dev-my-app (front만 존재) + 별도 back-my-app 레포
  → /init-project
  → Step 0: dev-my-app 감지
           - ORIGIN_URL 파싱 → DETECTED_ORG=CODIWORKS-Engineer, DETECTED_PROJECT=my-app
           - EXISTING_DEV_REPO=true
  → Step 1: front 있음, back 없음
  → Step 2: E) 기존 레포 통합 (Recommended)
           - 추천 로직 테이블: "있음 + O + X" → E 최우선
           - 질문 본문에 "dev 레포: CODIWORKS-Engineer/dev-my-app (감지됨)" 표시
  → Step 3-E (import-mode.md 참조):
      E-1: back만 import (front은 이미 있음) — 자동 판단, 사용자 확인
      E-2: gh repo view로 back-my-app의 기본 브랜치 자동 감지
      E-3: apps/back/가 비어있는지 사전 체크
      E-4: git subtree add --prefix=apps/back <url> <branch>
  → Step 4:
      4-1: 감지된 정보 확인만 (project: my-app, org: CODIWORKS-Engineer)
           - 4-2, 4-3 질문 건너뛰기
      4-4: Infisical Project ID 질문 (기존 프로젝트 재사용 가능)
      4-5: Machine Identity 질문
  → Step 5: apps/back/.infisical.json workspaceId 치환
            - import된 레포에 .infisical.json이 있었다면 덮어쓰기
            - 없다면 init-project.sh가 경고 (수동 생성 필요)
  → Step 6: git commit (subtree add 후 작업 트리가 깨끗하지 않으면)
  → Step 7: init-project.sh my-app --org CODIWORKS-Engineer
            - dev-my-app 레포 이미 존재 → "건너뜀" 로그
            - codi-engineers 팀 권한은 idempotent하게 재적용
            - Secrets만 새로 등록 (기존 값 덮어쓰기)
  → Step 8: 다음 push 시 deploy-backend-pm2.yml 자동 트리거 → 서버 배포
```

**왜 이게 핵심 유스케이스인가:** 하네스 B방식 전환 전에 A방식(멀티레포)으로 운영되던 프로젝트들이 이 경로를 통해 마이그레이션된다. 이 시나리오를 매끄럽게 처리하는 것이 스킬의 가장 큰 가치다.

**검증 포인트:**
- `git log -- apps/back/`로 기존 back 레포의 커밋이 보이는지
- `git blame apps/back/<file>`이 원본 커밋 기준으로 동작하는지
- 첫 push 시 `deploy-backend-pm2.yml`이 트리거되는지
- Infisical `/backend/` 경로에 필요한 시크릿이 이미 있는지 (없으면 배포 실패)

---

## 시나리오 4: 기존 dev 레포에 별도 front 레포 통합

**상황:** 시나리오 3의 거울 케이스. `dev-my-app`에 `apps/back/`만 있고 별도 `front-my-app` 레포를 흡수.

```
/init-project
  → Step 0: dev-my-app 감지
  → Step 1: front 없음, back 있음
  → Step 2: E) 기존 레포 통합 (Recommended)
  → Step 3-E:
      E-1: front만 import
      E-2: 브랜치 감지
      E-3: apps/front/ 사전 체크
      E-4: git subtree add --prefix=apps/front
  → Step 4:
      4-1: 감지된 정보 확인
      4-4, 4-5: Infisical
  → Step 5: apps/front/.infisical.json 치환
  → Step 7: init-project.sh (dev 레포 이미 존재 → 건너뜀)
  → Step 8: 다음 push 시 deploy-frontend.yml 자동 트리거 → Vercel 배포
```

**차이점:** back 통합과 달리 Vercel 연결을 **재확인**해야 한다. 기존 Vercel 프로젝트가 원본 `front-my-app` 레포에 연결되어 있었다면, 이제 `dev-my-app`의 `apps/front/`를 가리키도록 전환해야 한다.

1. Vercel 대시보드 → 기존 front-my-app 프로젝트 → Settings → Git → Disconnect
2. New Project → dev-my-app 레포 선택 → Root Directory: `apps/front`
3. 환경변수 재확인 (Infisical → Vercel Integration이 활성화되어 있으면 자동 동기화)

---

## 시나리오 매칭 빠른 참조

Step 0/1의 감지 결과로 어느 시나리오인지 즉시 판단할 수 있다.

| EXISTING_DEV_REPO | FRONT_EXISTS | BACK_EXISTS | 시나리오 | 추천 옵션 |
|-------------------|--------------|-------------|----------|-----------|
| false | false | false | 1 | A |
| false | true | true | 2 | D |
| **true** | **true** | **false** | **3** | **E** |
| **true** | **false** | **true** | **4** | **E** |
| false | true | false | - | B or C 조합 또는 E |
| false | false | true | - | B or C 조합 또는 E |
| true | false | false | 드뭄 | A (비어있는 기존 레포) |
| true | true | true | 드뭄 | D (완료 상태 재실행) |

**"드뭄" 케이스:** 가능은 하지만 실무에서 자주 발생하지 않는다. 방어적으로 처리하되 특별히 최적화할 필요는 없다.
