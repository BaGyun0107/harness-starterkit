#!/bin/bash
set -euo pipefail

# ── harness 프로젝트 초기화 스크립트 (B방식 + Infisical) ──
# 사용법: ./scripts/init-project.sh <project-name> [--org <org>]
# 예시:
#   ./scripts/init-project.sh my-app
#   ./scripts/init-project.sh my-app --org CODIWORKS-Engineer
#
# B방식 설명:
# - 모노레포 1개(dev-<project>)에서 apps/front(Vercel CLI), apps/back(SSH/PM2) 직접 배포
# - front-<project>, back-<project> 배포 레포 생성하지 않음
# - 모든 시크릿은 Infisical에서 조회 (GitHub Secrets는 INFISICAL_CLIENT_ID/SECRET 2개만)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 기본 설정 ──
DEFAULT_ORG="CODIWORKS-Engineer"
INFISICAL_API_URL="${INFISICAL_API_URL:-https://env.co-di.com}"

# ── 색상 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── 인자 파싱 ──
if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-name> [--org <org>]"
  echo ""
  echo "Arguments:"
  echo "  project-name  프로젝트 이름 (예: my-app)"
  echo ""
  echo "Options:"
  echo "  --org         GitHub Organization (기본값: ${DEFAULT_ORG})"
  echo ""
  echo "Example:"
  echo "  $0 my-app"
  echo "  $0 my-app --org ${DEFAULT_ORG}"
  exit 1
fi

PROJECT_NAME="$1"
shift

ORG="${DEFAULT_ORG}"

while [ $# -gt 0 ]; do
  case "$1" in
    --org)
      ORG="$2"
      shift 2
      ;;
    *)
      error "알 수 없는 옵션: $1"
      exit 1
      ;;
  esac
done

info "프로젝트: ${PROJECT_NAME}"
info "Org: ${ORG}"

# ── macOS 호환 sed 함수 ──
replace_in_file() {
  local pattern="$1"
  local file="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

# ══════════════════════════════════════════════════════════
#  사전 체크
# ══════════════════════════════════════════════════════════
info "사전 체크..."

# gh CLI
if ! command -v gh &> /dev/null; then
  error "GitHub CLI (gh) 가 설치되어 있지 않습니다."
  echo "  설치: brew install gh"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  error "GitHub CLI 로그인이 필요합니다."
  echo "  실행: gh auth login"
  exit 1
fi
info "  gh: 로그인됨"

# Infisical CLI
if ! command -v infisical &> /dev/null; then
  warn "infisical CLI가 설치되어 있지 않습니다."
  echo "  설치: brew install infisical/get-cli/infisical"
  echo "  로컬 개발 시 필요합니다 (CI는 영향 없음)"
else
  info "  infisical: $(infisical --version 2>&1 | head -1)"
fi

# Infisical 로그인 상태 (선택)
if command -v infisical &> /dev/null; then
  if infisical user 2>&1 | grep -q "Logged in"; then
    info "  infisical: 로그인됨"
  else
    warn "  infisical: 로그인되지 않음 — 로컬 개발 전 'infisical login' 실행 필요"
  fi
fi

# ── 실패 시 정리 ──
CREATED_REPOS=()
cleanup() {
  if [ ${#CREATED_REPOS[@]} -gt 0 ]; then
    error "오류 발생. 생성된 레포를 정리합니다..."
    for repo in "${CREATED_REPOS[@]}"; do
      warn "삭제: $repo"
      gh repo delete "$repo" --yes 2>/dev/null || true
    done
  fi
}
trap cleanup ERR

# ── 레포 존재 여부 체크 후 생성 ──
create_repo_if_not_exists() {
  local repo="$1"
  local desc="$2"
  if gh repo view "$repo" &>/dev/null; then
    info "  $repo (이미 존재 — 건너뜀)"
  else
    gh repo create "$repo" --private --description "$desc"
    CREATED_REPOS+=("$repo")
    info "  $repo (생성 완료)"
  fi
}

TOTAL_STEPS=6

# ══════════════════════════════════════════════════════════
#  Step 1: dev 레포 생성
# ══════════════════════════════════════════════════════════
info "Step 1/${TOTAL_STEPS}: GitHub 레포 생성..."

info "  dev-${PROJECT_NAME} (모노레포)"
create_repo_if_not_exists "${ORG}/dev-${PROJECT_NAME}" "Monorepo for ${PROJECT_NAME}"

# ══════════════════════════════════════════════════════════
#  Step 2: 팀 권한 추가
# ══════════════════════════════════════════════════════════
TEAM_SLUG="codi-engineers"
info "Step 2/${TOTAL_STEPS}: 팀 권한 추가 (${TEAM_SLUG} → admin)..."

gh api -X PUT "orgs/${ORG}/teams/${TEAM_SLUG}/repos/${ORG}/dev-${PROJECT_NAME}" \
  -f permission=admin --silent 2>/dev/null \
  && info "  ${ORG}/dev-${PROJECT_NAME} ← ${TEAM_SLUG} (admin)" \
  || warn "  팀 권한 추가 실패 — 수동 등록 필요"

# ══════════════════════════════════════════════════════════
#  Step 3: Infisical 설정 치환 (.infisical.json + 워크플로우)
# ══════════════════════════════════════════════════════════
info "Step 3/${TOTAL_STEPS}: Infisical 설정 치환..."

INFISICAL_PROJECT_ID="${INFISICAL_PROJECT_ID:-}"

if [ -z "$INFISICAL_PROJECT_ID" ]; then
  warn "INFISICAL_PROJECT_ID 환경변수가 없습니다."
  echo "  Infisical UI(${INFISICAL_API_URL})에서 다음을 미리 준비하세요:"
  echo "    1. 프로젝트 생성: dev-${PROJECT_NAME}"
  echo "    2. dev 환경에 폴더 생성: /backend, /backend/github-actions,"
  echo "                              /frontend, /frontend/github-actions"
  echo "    3. Project Settings → Copy Project ID"
  echo "    4. export INFISICAL_PROJECT_ID=<copied-id> 후 이 스크립트 재실행"
  echo "  또는 .infisical.json/워크플로우의 _PROJECT_ID_ 를 직접 수정해도 됩니다."
else
  for cfg in "apps/back/.infisical.json" "apps/front/.infisical.json"; do
    if [ -f "$cfg" ]; then
      replace_in_file "s|\"workspaceId\": \"[^\"]*\"|\"workspaceId\": \"${INFISICAL_PROJECT_ID}\"|" "$cfg"
      info "  $cfg workspaceId 치환 완료"
    fi
  done

  # 워크플로우 env 블록의 _PROJECT_ID_ placeholder 치환
  WF_REPLACED=0
  for wf in .github/workflows/deploy-frontend-vercel.yml \
            .github/workflows/deploy-frontend-pm2.yml \
            .github/workflows/deploy-frontend-docker.yml \
            .github/workflows/deploy-backend-pm2.yml \
            .github/workflows/deploy-backend-docker.yml; do
    if [ -f "$wf" ] && grep -q "_PROJECT_ID_" "$wf"; then
      replace_in_file "s|_PROJECT_ID_|${INFISICAL_PROJECT_ID}|g" "$wf"
      WF_REPLACED=$((WF_REPLACED + 1))
    fi
  done
  if [ "$WF_REPLACED" -gt 0 ]; then
    info "  워크플로우 ${WF_REPLACED}개 파일의 INFISICAL_PROJECT_ID 치환 완료"
  fi
fi

# ══════════════════════════════════════════════════════════
#  Step 4: GitHub Secrets 등록 (INFISICAL_CLIENT_ID/SECRET)
# ══════════════════════════════════════════════════════════
info "Step 4/${TOTAL_STEPS}: GitHub Secrets 등록..."

if [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ]; then
  echo "$INFISICAL_CLIENT_ID" | gh secret set INFISICAL_CLIENT_ID --repo "${ORG}/dev-${PROJECT_NAME}"
  echo "$INFISICAL_CLIENT_SECRET" | gh secret set INFISICAL_CLIENT_SECRET --repo "${ORG}/dev-${PROJECT_NAME}"
  info "  INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET 등록 완료"
else
  warn "  INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET 환경변수가 없습니다."
  echo "  나중에 수동 등록:"
  echo "    gh secret set INFISICAL_CLIENT_ID     --repo ${ORG}/dev-${PROJECT_NAME}"
  echo "    gh secret set INFISICAL_CLIENT_SECRET --repo ${ORG}/dev-${PROJECT_NAME}"
fi

# ══════════════════════════════════════════════════════════
#  Step 5: Git remote 설정
# ══════════════════════════════════════════════════════════
info "Step 5/${TOTAL_STEPS}: Git remote 설정..."

if git remote get-url origin &>/dev/null; then
  git remote set-url origin "https://github.com/${ORG}/dev-${PROJECT_NAME}.git"
else
  git remote add origin "https://github.com/${ORG}/dev-${PROJECT_NAME}.git"
fi
info "  origin → ${ORG}/dev-${PROJECT_NAME}"

# ══════════════════════════════════════════════════════════
#  Step 6: 브랜치 생성 + push
# ══════════════════════════════════════════════════════════
info "Step 6/${TOTAL_STEPS}: 브랜치 설정..."

git add -A
git commit -m "chore: init project ${PROJECT_NAME}" --allow-empty || true
git push -u origin main

if git show-ref --verify --quiet refs/heads/dev; then
  git checkout dev
else
  git checkout -b dev
fi
git push -u origin dev
git checkout main

info "  main, dev 브랜치 생성 완료"

# ══════════════════════════════════════════════════════════
#  완료 안내
# ══════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Project ${PROJECT_NAME} initialized! (B방식 + Infisical)${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Repo: https://github.com/${ORG}/dev-${PROJECT_NAME}"
echo ""
echo "  GitHub Secrets:"
echo "    ✅ INFISICAL_CLIENT_ID"
echo "    ✅ INFISICAL_CLIENT_SECRET"
echo "    → 나머지 모든 시크릿은 Infisical에서 런타임 조회"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  수동 설정 필요${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. Infisical 프로젝트 준비 (${INFISICAL_API_URL}):"
echo "     - 프로젝트 생성: dev-${PROJECT_NAME}"
echo "     - dev 환경에 폴더 + 시크릿 등록:"
echo "       /backend/                   DATABASE_URL, JWT_SECRET, JWT_REFRESH_SECRET, NODE_ENV, PORT"
echo "       /backend/github-actions/    BACK_SERVER_HOST, BACK_SERVER_USER, BACK_DEPLOY_DIR,"
echo "                                   BACK_APP_NAME, BACK_TAR_FILE, BACK_SSH_PRIVATE_KEY,"
echo "                                   BACK_APP_TYPE (선택: pm2|static, 기본 pm2)"
echo "       /frontend/                  NEXT_PUBLIC_*"
echo "       /frontend/github-actions/   VERCEL_ORG_ID, VERCEL_PROJECT_ID"
if [ -z "$INFISICAL_PROJECT_ID" ]; then
  echo ""
  echo "     - Project Settings → Copy Project ID 후"
  echo "       export INFISICAL_PROJECT_ID=<id> 다음 이 스크립트를 다시 실행하면"
  echo "       .infisical.json / 워크플로우의 _PROJECT_ID_ 가 자동 치환됩니다."
fi
echo ""
echo "  2. 팀원 Join (env.co-di.com → All Projects → dev-${PROJECT_NAME}):"
echo "     - ai@co-di.com 은 admin"
echo "     - dev@co-di.com, su@co-di.com, design@co-di.com 은 member"
echo ""
echo "  3. Machine Identity (CI/CD 런타임용) 생성 또는 재사용:"
echo "     - Organization Access Control > Machine Identities"
echo "     - Auth Method: Universal Auth, TTL: 0"
echo "     - 이 프로젝트에 Read 권한 부여"
echo "     - Client ID/Secret을 GitHub Secrets에 등록 (Step 4에서 자동 처리됨)"
echo ""
echo "  4. 워크플로우 _CF_SHARED_PATH_ 직접 수정:"
echo "     - .github/workflows/deploy-*.yml 5개 파일의 _CF_SHARED_PATH_ 자리에"
echo "       이 프로젝트가 사용할 Cloudflare 시크릿 path 입력 (예: /cloudflare/<env>)"
echo ""
echo "  5. Shared-Secrets 프로젝트 접근 권한 (Slack/Vercel 공용):"
echo "     - /slack/      (slack_bot_token, slack_channel)"
echo "     - /vercel/     (VERCEL_TOKEN)"
echo "     - Machine Identity에 Shared-Secrets 프로젝트 Read 권한 부여"
echo ""
echo "  6. Vercel 프로젝트 연결 (${ORG}/dev-${PROJECT_NAME}):"
echo "     - Vercel 대시보드에서 New Project → 레포 import"
echo "     - Root Directory: apps/front"
echo "     - main → Production, dev → Preview"
echo "     - Settings > Git > Disconnect (GitHub Actions로 배포)"
echo "     - Infisical > Integrations > Vercel 연결 (자동 env 동기화)"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Next steps${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. 로컬 개발: infisical login 후 npm run dev"
echo "  2. 배포: git push origin dev → GitHub Actions 자동 배포"
echo "  3. 프로덕션: main 브랜치 push"
echo ""
