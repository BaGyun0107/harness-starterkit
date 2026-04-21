---
name: init-project
description: |
  새 프로젝트를 이 하네스의 직접 배포 모노레포 구조로 초기화하는 스킬. Use when the user asks to initialize a new project, bootstrap from this harness, run `init-project`, create a `dev-{project}` GitHub repo, connect Infisical, or prepare GitHub/Vercel for a fresh app. This skill is specific to this repository's `apps/front` + `apps/back` direct-deploy flow and should be used instead of ad-hoc manual setup.
---

# Init Project - Direct Deploy Bootstrap

## 목적

이 스킬은 새 프로젝트를 현재 하네스 규칙에 맞게 초기화할 때 사용한다.

완료 상태는 아래를 만족해야 한다.

- GitHub에 `dev-{project}` 모노레포가 생성됨
- `origin`이 새 레포를 가리킴
- `main`, `dev` 브랜치가 push됨
- `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`만 GitHub Secrets에 등록됨
- 사용자가 남은 수동 작업을 정확히 이해함

## 언제 사용할까

- 사용자가 `/init-project`, "프로젝트 초기화", "새 프로젝트 부트스트랩", "하네스 연결", "dev 레포 만들어줘" 같은 요청을 할 때
- 하네스 zip을 풀고 `apps/front`, `apps/back` 스캐폴딩을 끝낸 직후
- Infisical, GitHub, Vercel 연결까지 포함한 초기 셋업이 필요할 때

## 언제 사용하지 말까

- 기존 프로젝트의 배포 설정만 손보고 싶을 때
  - `setup-deploy` 쪽이 더 맞다
- 초기화 스크립트의 버그를 고치려는 작업일 때
  - `investigate` 또는 일반 코드 수정으로 처리한다
- 단순히 `apps/front`, `apps/back` 스캐폴딩만 만들고 싶을 때
  - 이 스킬 없이 각 앱 생성 작업만 수행한다

## 소스 우선순위

지침이 충돌하면 아래 순서로 판단한다.

1. `scripts/init-project.sh`
2. 루트 `AGENTS.md`의 프로젝트 초기화/배포 규칙
3. `docs/MIGRATION-DIRECT-DEPLOY.md`
4. 그 외 문서

`docs/PIPELINE-GUIDE.md`처럼 `front-*`, `back-*` 레포를 전제로 한 문서는 레거시일 수 있다. 새 프로젝트 초기화에는 사용하지 않는다.

## 필수 입력

- `project_name`
  - `dev-` 접두사 없이 받는다. 예: `liveview`
- `org`
  - 기본값은 `CODIWORKS-Engineer`

가능하면 아래 상태도 같이 확인한다.

- `apps/front`, `apps/back` 스캐폴딩 완료 여부
- `apps/front/.infisical.json`, `apps/back/.infisical.json` 존재 여부
- `INFISICAL_PROJECT_ID` 존재 여부
- `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` 존재 여부

## 사전 점검

실행 전에 아래를 확인한다.

1. 루트 `AGENTS.md`와 `scripts/init-project.sh`를 읽어 현재 규칙을 파악한다.
2. `apps/front`, `apps/back`, `scripts/init-project.sh`가 존재하는지 확인한다.
3. `gh`가 설치되어 있고 로그인되어 있는지 확인한다.
4. `git` 저장소인지 확인한다.
5. 현재 `origin`이 이미 설정되어 있다면 새 레포로 바뀐다는 점을 사용자에게 알린다.
6. 작업 트리가 더럽다면, 현재 변경사항이 초기 커밋/초기 push에 포함될 수 있음을 알린다.
7. `infisical` CLI는 선택이지만, 로컬 개발 전에는 로그인 필요하다고 안내한다.

아래 상황이면 그대로 진행하지 말고 먼저 사용자에게 알린다.

- `project_name`이 없음
- `gh auth status` 실패
- 이 저장소가 이미 다른 프로젝트 원격과 연결되어 있고 덮어쓰기가 위험한 경우
- `apps/front` 또는 `apps/back`가 비어 있어 하네스 초기화 단계 자체가 끝나지 않은 경우

## 실행 원칙

1. 가능하면 수동 재구현 대신 `scripts/init-project.sh <project_name> [--org <org>]`를 실행한다.
2. 네트워크 권한, GitHub 쓰기, 보호된 디렉터리 쓰기가 필요하면 승인 절차를 따른다.
3. GitHub Secrets는 `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET` 두 개만 다룬다.
4. 새 프로젝트는 `dev-{project}` 모노레포 하나만 만든다.
5. `front-{project}`, `back-{project}` 레포를 만들지 않는다.
6. `.claude/skills/`를 읽어서 근거로 삼지 않는다.

## 알려진 주의점

### 1. 커밋 메시지 규칙 충돌

현재 `scripts/init-project.sh`는 아래 영문 커밋을 만든다.

```text
chore: init project {project_name}
```

이 저장소의 커밋 메시지 규칙과 충돌한다. 실행 전 이 사실을 사용자에게 알린다.

- 기본 동작: 그대로 둔다
- 사용자가 명시적으로 원할 때만 후속 수정 방안을 제안한다
- 이미 push된 브랜치의 히스토리를 자동으로 다시 쓰지 않는다

### 2. Vercel Root Directory 표기 차이

문서에 `apps/front`와 `./`가 섞여 보일 수 있다. 의미를 아래처럼 해석한다.

- Vercel 프로젝트를 저장소 기준으로 연결할 때의 대상 디렉터리는 `apps/front`
- GitHub Actions에서는 `apps/front` 안에서 `vercel pull`, `vercel build`, `vercel deploy`를 실행하므로 로컬 작업 디렉터리 기준 root는 `./`

둘은 충돌이 아니라 같은 대상을 다른 기준으로 설명한 것이다.

## 권장 실행 순서

### 1. 입력 정리

아래처럼 먼저 실행 인자를 정리한다.

```bash
./scripts/init-project.sh <project_name> --org <org>
```

`--org`가 없으면 기본값은 `CODIWORKS-Engineer`다.

### 2. 실행 전 사용자에게 알려줄 내용

실행 전 아래를 짧게 요약한다.

- GitHub에 `dev-{project}` 레포를 만들 것
- `codi-engineers` 팀에 admin 권한을 시도할 것
- `.infisical.json`의 `workspaceId`를 바꿀 수 있음
- `origin`을 새 레포로 설정할 것
- `main`, `dev` 브랜치를 push할 것
- 모든 시크릿은 Infisical이 SSOT이며 GitHub에는 2개만 넣을 것

### 3. 스크립트 실행

스크립트 실행을 우선한다.

```bash
./scripts/init-project.sh <project_name> --org <org>
```

스크립트가 처리하는 일:

- `dev-{project}` GitHub 레포 생성
- `codi-engineers` 팀 권한 추가 시도
- `INFISICAL_PROJECT_ID`가 있으면 `apps/front/.infisical.json`, `apps/back/.infisical.json`의 `workspaceId` 치환
- `INFISICAL_CLIENT_ID`, `INFISICAL_CLIENT_SECRET`가 있으면 GitHub Secrets 등록
- `origin` 설정
- `main`, `dev` 브랜치 생성 및 push

### 4. 실행 후 검증

최소한 아래를 확인한다.

- `git remote get-url origin`
- `git branch --list main dev`
- `gh repo view {org}/dev-{project}`
- `apps/front/.infisical.json`, `apps/back/.infisical.json`이 기대대로 반영됐는지

검증이 실패하면, 스크립트 stderr와 실패 단계만 좁혀서 설명한다. 이미 있는 자동 cleanup 로직을 무시하고 수동 재시도를 섞지 않는다.

## 수동 후속 작업 체크리스트

실행이 끝나면 아래를 반드시 사용자에게 남긴다.

1. Infisical 프로젝트 생성 또는 기존 프로젝트 연결
2. Machine Identity 생성
   - Universal Auth
   - Client Secret TTL `0`
   - 대상 프로젝트 Read 권한 부여
3. Shared-Secrets 접근 권한 부여
   - `/slack`
   - `/vercel`
4. Vercel에서 `dev-{project}` 레포 연결
   - 앱 대상은 `apps/front`
   - `main` → Production
   - `dev` → Preview/Development
   - 연결 후 Git Integration은 Disconnect
5. Infisical Vercel Integration 활성화
6. Infisical 경로별 시크릿 입력
   - `/backend`
   - `/backend/github-actions`
   - `/frontend`
   - `/frontend/github-actions`
7. 로컬 개발 전 `infisical login --domain=https://env.co-di.com`

## 보고 형식

최종 응답은 아래 순서를 유지한다.

### Preflight

- 확인한 전제
- 누락된 전제
- 위험 요소

### Actions

- 실제 실행한 명령
- 자동으로 처리된 항목
- 변경된 로컬/GitHub 상태

### Manual Next Steps

- 사용자가 직접 해야 할 일만 남긴다

### Risks

- 커밋 메시지 규칙 충돌
- 미입력 시크릿
- 수동 연결이 아직 끝나지 않은 외부 서비스

## 예시 트리거

### 예시 1

입력:

```text
/init-project liveview
```

기대 동작:

- `scripts/init-project.sh liveview` 실행 준비
- `gh`/`git`/`infisical` 사전 점검
- 남은 수동 작업 목록 정리

### 예시 2

입력:

```text
하네스 기반으로 새 프로젝트 하나 열어줘. dev-my-app 레포랑 Infisical 연결까지 갈 거야.
```

기대 동작:

- 이 스킬을 선택
- `project_name=my-app`로 정규화
- 직접 배포 모노레포 초기화 흐름으로 진행
