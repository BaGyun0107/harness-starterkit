# E 옵션 — 기존 레포 통합 (Import)

기존에 별도 레포로 운영 중인 front 또는 back 소스를 모노레포로 흡수하는 절차. `git subtree add`를 사용하여 **커밋 히스토리를 보존**한다.

**이 파일을 언제 읽는가:** Step 2에서 E 옵션이 선택되었거나, 사용자가 "기존 back 레포를 dev-my-app에 합치고 싶다"고 요청할 때.

**핵심 유스케이스:** `dev-{project}`는 이미 존재하고 `apps/front/`만 있는 상태에서, 별도 `back-{project}` 레포를 `apps/back/`으로 통합하는 것. 반대 방향(front 통합)도 동일한 구조.

---

## E 옵션 플로우 (E-1 ~ E-5)

### E-1. Import 대상 자동 판단

Step 0(환경 감지)과 Step 1(상태 감지)의 결과를 보고 **어느 쪽을 import할지 코드가 결정**한다. 사용자에게 "front인가 back인가" 같은 질문을 다시 하지 않는다.

| front 존재 | back 존재 | import 대상 |
|-----------|----------|------------|
| O | X | back만 import |
| X | O | front만 import |
| X | X | 둘 다 import |

판단 결과를 사용자에게 **확인**받는다:

```yaml
# back만 import하는 경우
question: |
  apps/front/는 이미 존재합니다. back 레포만 import합니다.

  import할 back 레포의 GitHub URL을 입력해주세요.
header: "기존 레포 통합"
options:
  - label: "직접 입력"
    description: "GitHub 레포 URL을 입력하세요 (예: https://github.com/org/back-my-app)"
```

### E-2. 브랜치 자동 감지

레포의 기본 브랜치를 `gh repo view`로 조회한다. `main`이 아닐 수 있으므로 **절대 가정하지 마라.**

```bash
IMPORT_BRANCH=$(gh repo view <repo-url> --json defaultBranchRef --jq '.defaultBranchRef.name')
echo "감지된 기본 브랜치: $IMPORT_BRANCH"
```

감지 결과를 사용자에게 확인받되, 기본값을 Recommended로 먼저 제시한다:

```yaml
question: "import할 브랜치를 확인해주세요."
header: "Import 브랜치"
options:
  - label: "{감지된 브랜치} (Recommended)"
    description: "레포의 기본 브랜치입니다"
  - label: "직접 입력"
    description: "다른 브랜치를 사용하려면 이 옵션을 선택하세요"
```

### E-3. 사전 체크 (중요)

`git subtree add`는 **멱등하지 않다.** 대상 경로에 이미 내용이 있으면 실패한다. 따라서 반드시 사전에 비어있는지 확인한다.

```bash
if [ -d "apps/back" ] && [ -n "$(ls -A apps/back 2>/dev/null)" ]; then
  error "apps/back/ 가 비어있지 않습니다. import를 실행하려면 먼저 비워주세요."
  # 사용자에게 안내 후 중단 — 자동으로 지우지 않는다
fi
```

**왜 자동으로 지우지 않는가:** 사용자가 `apps/back/`에 이미 작업 중인 내용이 있을 수 있다. 그걸 자동 삭제하면 되돌릴 수 없는 데이터 손실이 발생한다. 반드시 사용자가 수동으로 정리하게 한다.

### E-4. git subtree add 실행

```bash
# back 레포 import 예시
git remote add import-back <back-repo-url>
git fetch import-back
git subtree add --prefix=apps/back import-back/<branch>
git remote remove import-back

# front 레포 import 예시 (해당되는 경우)
git remote add import-front <front-repo-url>
git fetch import-front
git subtree add --prefix=apps/front import-front/<branch>
git remote remove import-front
```

**왜 remote를 임시로 추가했다가 삭제하는가:** `git subtree add`는 fetch된 ref가 필요하지만, 그 remote를 영구적으로 유지할 이유는 없다. origin 하나만 남겨두는 것이 깔끔하다.

### E-5. Infisical 연결은 Step 5에서

Import한 앱은 아직 `.infisical.json`이 없거나 **다른 프로젝트를 가리킬 수 있다.** 별도 조치를 하지 않고 그대로 Step 4 → Step 5로 진행한다. Step 5에서 새 Infisical Project ID로 workspaceId가 자동 치환된다.

**주의:** `.infisical.json`이 존재하지만 원본 레포의 Project ID를 가리키고 있는 경우, Step 5의 sed 치환이 이를 덮어쓴다. 만약 원본 레포의 Infisical 설정을 유지하고 싶은 경우(거의 없는 케이스)라면 Step 4에서 사용자에게 명시적으로 물어봐야 한다.

---

## 통합 후 확인 사항

### 커밋 히스토리 검증

`git subtree add`가 제대로 동작했다면 다음 명령으로 원본 레포의 히스토리를 확인할 수 있다:

```bash
# apps/back/ 경로의 히스토리만 필터링
git log --oneline -- apps/back/ | head -20

# blame도 원본 커밋 기준으로 동작해야 함
git blame apps/back/src/server.ts | head
```

### 경로 충돌 확인

원본 레포의 루트 구조가 모노레포의 `apps/back/` 구조와 충돌하지 않는지 확인한다. 예를 들어:

- 원본 레포 루트에 `.github/workflows/deploy.yml`이 있었다면 → import 후 `apps/back/.github/workflows/deploy.yml`로 들어간다. 모노레포의 `.github/workflows/` 와 경로가 다르므로 **중복 실행은 발생하지 않지만**, 불필요한 파일이므로 삭제 대상이다.
- 원본 레포 루트에 `package.json`이 있었다면 → `apps/back/package.json`으로 들어간다. 이건 정상이다.

### 배포 경로 테스트

통합 후 첫 push 전에:
1. `deploy-backend-pm2.yml`의 `paths` 필터가 `apps/back/**`를 포함하는지 확인
2. `apps/back/package.json`이 루트에 있고 `build`/`start` 스크립트가 정의되어 있는지 확인
3. `ecosystem.config.js`가 `apps/back/`에 있는지 확인 (tar.gz에 포함되어야 함)

---

## 자주 발생하는 문제

### "fatal: 'apps/back' is not a directory that exists"

`git subtree add --prefix=apps/back`은 `apps/back/` 디렉토리가 **존재하지 않아야** 한다. E-3 사전 체크에서 잡혀야 하는 케이스이지만, 부분적으로 생성된 상태(예: `apps/back/.gitkeep` 하나만)에서는 혼란이 생길 수 있다.

해결: `rm -rf apps/back/` 후 재실행. 단 사용자 동의를 먼저 받는다.

### "Working tree has modifications"

`git subtree add`는 작업 트리가 깨끗해야 한다. Step 6에서 커밋하기 전에 E 옵션을 실행하는 경우 이 에러가 발생할 수 있다.

해결: 순서를 지킨다. Step 3(E 옵션) → Step 6(git commit). Step 6에서는 subtree add로 생성된 머지 커밋이 이미 있으므로 새 커밋은 불필요할 수 있다.

### 두 레포의 커밋이 시간순으로 뒤섞임

이건 **버그가 아니라 의도된 동작**이다. `git subtree add`는 원본 레포의 전체 히스토리를 머지 커밋으로 흡수하므로 `git log`에 두 히스토리가 병렬로 보인다. 경로 필터(`git log -- apps/back/`)로 분리 추적할 수 있으므로 실무상 문제는 없다.
