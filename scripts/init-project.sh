#!/bin/bash
set -euo pipefail

# ── harness 프로젝트 초기화 스크립트 ──
# 사용법: ./scripts/init-project.sh <project-name> --mode <full|front-only|back-only> [--front-org <org>] [--back-org <org>]
# 예시:
#   ./scripts/init-project.sh my-app --mode full --front-org CODIWORKS-Vercel --back-org CODIWORKS-Engineer
#   ./scripts/init-project.sh my-app --mode front-only --front-org CODIWORKS-Vercel --back-org CODIWORKS-Engineer
#   ./scripts/init-project.sh my-app --mode back-only --back-org CODIWORKS-Engineer

# ── GitHub App 설정 ──
# TODO: Infisical 구축 후 .pem 파일을 Infisical에 보관하고 GITHUB_APP_PEM 환경변수로 주입
GITHUB_APP_ID="3241562"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GITHUB_APP_PEM="${GITHUB_APP_PEM:-$PROJECT_ROOT/codi-repo-sync.private-key.pem}"

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
  echo "Usage: $0 <project-name> --mode <full|front-only|back-only> [--front-org <org>] [--back-org <org>]"
  echo ""
  echo "Arguments:"
  echo "  project-name  프로젝트 이름 (예: my-app)"
  echo ""
  echo "Options:"
  echo "  --mode        레포 생성 모드: full, front-only, back-only"
  echo "  --front-org   Front 레포가 위치할 GitHub Organization"
  echo "  --back-org    Back/Dev 레포가 위치할 GitHub Organization"
  echo ""
  echo "Examples:"
  echo "  $0 my-app --mode full --front-org CODIWORKS-Vercel --back-org CODIWORKS-Engineer"
  echo "  $0 my-app --mode front-only --front-org CODIWORKS-Vercel --back-org CODIWORKS-Engineer"
  echo "  $0 my-app --mode back-only --back-org CODIWORKS-Engineer"
  echo ""
  echo "  # 하위 호환: 기존 positional 인자 방식도 지원 (mode=full)"
  echo "  $0 my-app CODIWORKS-Vercel CODIWORKS-Engineer"
  exit 1
fi

PROJECT_NAME="$1"
shift

# 하위 호환: positional 인자 방식 감지 (첫 인자가 --로 시작하지 않으면)
if [ $# -ge 2 ] && [[ "$1" != --* ]]; then
  FRONT_ORG="$1"
  BACK_ORG="$2"
  MODE="full"
else
  MODE=""
  FRONT_ORG=""
  BACK_ORG=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)
        MODE="$2"
        shift 2
        ;;
      --front-org)
        FRONT_ORG="$2"
        shift 2
        ;;
      --back-org)
        BACK_ORG="$2"
        shift 2
        ;;
      *)
        error "알 수 없는 옵션: $1"
        exit 1
        ;;
    esac
  done
fi

# ── 모드 검증 ──
if [ -z "$MODE" ]; then
  error "--mode 옵션이 필요합니다 (full, front-only, back-only)"
  exit 1
fi

case "$MODE" in
  full)
    if [ -z "$FRONT_ORG" ] || [ -z "$BACK_ORG" ]; then
      error "full 모드에서는 --front-org과 --back-org이 모두 필요합니다"
      exit 1
    fi
    CREATE_FRONT=true
    CREATE_BACK=true
    ;;
  front-only)
    if [ -z "$FRONT_ORG" ] || [ -z "$BACK_ORG" ]; then
      error "front-only 모드에서는 --front-org과 --back-org(dev 레포용)이 모두 필요합니다"
      exit 1
    fi
    CREATE_FRONT=true
    CREATE_BACK=false
    ;;
  back-only)
    if [ -z "$BACK_ORG" ]; then
      error "back-only 모드에서는 --back-org이 필요합니다"
      exit 1
    fi
    CREATE_FRONT=false
    CREATE_BACK=true
    ;;
  *)
    error "알 수 없는 모드: $MODE (full, front-only, back-only 중 선택)"
    exit 1
    ;;
esac

info "모드: ${MODE} | 프로젝트: ${PROJECT_NAME}"
[ "$CREATE_FRONT" = true ] && info "  Front Org: ${FRONT_ORG}"
info "  Back/Dev Org: ${BACK_ORG}"

# ── gh CLI 확인 ──
if ! command -v gh &> /dev/null; then
  error "GitHub CLI (gh) 가 설치되어 있지 않습니다."
  echo "  설치: https://cli.github.com/"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  error "GitHub CLI 로그인이 필요합니다."
  echo "  실행: gh auth login"
  exit 1
fi

# ── .pem 파일 확인 ──
if [ ! -f "$GITHUB_APP_PEM" ]; then
  error "GitHub App private key를 찾을 수 없습니다: $GITHUB_APP_PEM"
  echo "  .pem 파일 경로를 확인하거나 GITHUB_APP_PEM 환경변수를 설정하세요."
  echo "  예: GITHUB_APP_PEM=/path/to/key.pem $0 $*"
  exit 1
fi

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

# ── 총 스텝 수 계산 ──
TOTAL_STEPS=7

# ══════════════════════════════════════════════════════════
#  Step 1: 레포 생성
# ══════════════════════════════════════════════════════════
info "Step 1/${TOTAL_STEPS}: GitHub 레포 생성..."

# dev 레포는 항상 생성
info "  dev-${PROJECT_NAME} (개발 모노레포)"
create_repo_if_not_exists "${BACK_ORG}/dev-${PROJECT_NAME}" "Development monorepo for ${PROJECT_NAME}"

# front 레포 (front-only 또는 full 모드)
if [ "$CREATE_FRONT" = true ]; then
  info "  front-${PROJECT_NAME} (Vercel 배포용)"
  create_repo_if_not_exists "${FRONT_ORG}/front-${PROJECT_NAME}" "Frontend deploy repo for ${PROJECT_NAME}"
fi

# back 레포 (back-only 또는 full 모드)
if [ "$CREATE_BACK" = true ]; then
  info "  back-${PROJECT_NAME} (Docker 배포용)"
  create_repo_if_not_exists "${BACK_ORG}/back-${PROJECT_NAME}" "Backend deploy repo for ${PROJECT_NAME}"
fi

# ══════════════════════════════════════════════════════════
#  Step 2: 플레이스홀더 치환
# ══════════════════════════════════════════════════════════
info "Step 2/${TOTAL_STEPS}: 워크플로우 플레이스홀더 치환..."

if [ -f ".github/workflows/sync-repos.yml" ]; then
  replace_in_file "s/__PROJECT__/${PROJECT_NAME}/g" .github/workflows/sync-repos.yml
  if [ "$CREATE_FRONT" = true ] && [ -n "$FRONT_ORG" ]; then
    replace_in_file "s/__FRONT_ORG__/${FRONT_ORG}/g" .github/workflows/sync-repos.yml
  fi
  replace_in_file "s/__BACK_ORG__/${BACK_ORG}/g" .github/workflows/sync-repos.yml
  info "  sync-repos.yml 치환 완료"
fi

if [ -f ".infisical.json.tmpl" ]; then
  cp .infisical.json.tmpl .infisical.json
  replace_in_file "s/__PROJECT__/${PROJECT_NAME}/g" .infisical.json
  info "  .infisical.json 생성 완료"
fi

# ══════════════════════════════════════════════════════════
#  Step 3: GitHub App 토큰 발급 + 시크릿 자동 등록
# ══════════════════════════════════════════════════════════
info "Step 3/${TOTAL_STEPS}: GitHub App 시크릿 자동 등록..."

# dev-{project} 레포에 App ID + Private Key 등록
# sync-repos.yml이 actions/create-github-app-token으로 매 실행마다 토큰을 자동 발급
echo "$GITHUB_APP_ID" | gh secret set APP_ID --repo "${BACK_ORG}/dev-${PROJECT_NAME}"
info "  APP_ID 시크릿 등록 완료"

gh secret set APP_PRIVATE_KEY --repo "${BACK_ORG}/dev-${PROJECT_NAME}" < "$GITHUB_APP_PEM"
info "  APP_PRIVATE_KEY 시크릿 등록 완료"

# ══════════════════════════════════════════════════════════
#  Step 3.5: back-* 레포에 deploy caller + docker-compose push
# ══════════════════════════════════════════════════════════
if [ "$CREATE_BACK" = true ] || gh repo view "${BACK_ORG}/back-${PROJECT_NAME}" &>/dev/null; then
  info "Step 3.5/${TOTAL_STEPS}: back-${PROJECT_NAME} 에 deploy workflow 배포..."

  (
    DEPLOY_TMP=$(mktemp -d)
    trap 'rm -rf "$DEPLOY_TMP"' EXIT
    cd "$DEPLOY_TMP"

    gh repo clone "${BACK_ORG}/back-${PROJECT_NAME}" . -- --depth 1 2>/dev/null || \
      git clone "https://github.com/${BACK_ORG}/back-${PROJECT_NAME}.git" . --depth 1

    # gh 인증 토큰으로 push 가능하도록 remote URL 설정
    git remote set-url origin \
      "https://x-access-token:$(gh auth token)@github.com/${BACK_ORG}/back-${PROJECT_NAME}.git"

    # deploy caller workflow 복사 + 플레이스홀더 치환
    mkdir -p .github/workflows
    cp "${PROJECT_ROOT}/templates/back-deploy.yml" .github/workflows/deploy.yml
    replace_in_file "s/__BACK_ORG__/${BACK_ORG}/g" .github/workflows/deploy.yml
    replace_in_file "s/__DEV_REPO__/dev-${PROJECT_NAME}/g" .github/workflows/deploy.yml

    git add .github/workflows/deploy.yml
    git commit -m "chore: 배포 파이프라인 자동 설정 (Reusable Workflow)" || true
    git push origin main
  ) || warn "deploy workflow push 실패 — 수동 등록 필요"

  info "  deploy workflow push 완료"
fi

# ══════════════════════════════════════════════════════════
#  Step 4: Git remote 설정
# ══════════════════════════════════════════════════════════
info "Step 4/${TOTAL_STEPS}: Git remote 설정..."

if git remote get-url origin &>/dev/null; then
  git remote set-url origin "https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}.git"
else
  git remote add origin "https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}.git"
fi
info "  origin → ${BACK_ORG}/dev-${PROJECT_NAME}"

# ══════════════════════════════════════════════════════════
#  Step 5: 브랜치 설정 및 push
# ══════════════════════════════════════════════════════════
info "Step 5/${TOTAL_STEPS}: 브랜치 설정..."

git add -A
git commit -m "chore: init project ${PROJECT_NAME} from harness" --allow-empty || true
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
#  Step 6: 안내 출력
# ══════════════════════════════════════════════════════════
info "Step 6/${TOTAL_STEPS}: 설정 안내..."

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Project ${PROJECT_NAME} initialized! (mode: ${MODE})${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Repos created:"
echo "    dev:   https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}"
if [ "$CREATE_FRONT" = true ]; then
  echo "    front: https://github.com/${FRONT_ORG}/front-${PROJECT_NAME}"
fi
if [ "$CREATE_BACK" = true ]; then
  echo "    back:  https://github.com/${BACK_ORG}/back-${PROJECT_NAME}"
fi
echo ""
echo "  Auto-configured:"
echo "    ✅ APP_ID           (GitHub App ID)"
echo "    ✅ APP_PRIVATE_KEY  (GitHub App private key)"
echo "    → sync-repos.yml이 매 실행마다 토큰을 자동 발급합니다 (만료 걱정 없음)"
if [ "$CREATE_BACK" = true ]; then
  echo ""
  echo "    ✅ deploy.yml       (Reusable Workflow caller)"
  echo "    → back-${PROJECT_NAME} push 시 자동 배포"
fi
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  수동 설정 필요${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  dev-${PROJECT_NAME} 레포 Settings → Secrets → Actions:"
echo ""
echo "    SLACK_WEBHOOK_URL  Slack Incoming Webhook URL"
echo ""

if [ "$CREATE_BACK" = true ]; then
  echo "  back-${PROJECT_NAME} 레포 Settings → Secrets → Actions:"
  echo ""
  echo "    SSH_PRIVATE_KEY    배포 서버 SSH 키"
  echo "    SLACK_WEBHOOK_URL  Slack Incoming Webhook URL"
  echo ""
  echo "  Environment Secrets (development / production):"
  echo ""
  echo "    DEV_SERVER_HOST    개발 서버 IP"
  echo "    DEV_SERVER_USER    개발 서버 SSH 유저"
  echo "    DEV_DEPLOY_DIR     개발 배포 디렉터리"
  echo "    PRD_SERVER_HOST    운영 서버 IP"
  echo "    PRD_SERVER_USER    운영 서버 SSH 유저"
  echo "    PRD_DEPLOY_DIR     운영 배포 디렉터리"
  echo "    SERVER_ENV_FILE    백엔드 .env 파일 내용 (Infisical 연동 전 임시)"
  echo ""
  echo "  Infisical 연동 (권장):"
  echo "    → Infisical 서버에서 환경변수를 직접 주입하면 SERVER_ENV_FILE 불필요"
  echo "    → deploy-backend.yml에 Infisical CLI 블록 활성화"
  echo ""
fi

if [ "$CREATE_FRONT" = true ]; then
  echo "════════════════════════════════════════════════════════════"
  echo -e "${YELLOW}  Vercel 연결${NC}"
  echo "════════════════════════════════════════════════════════════"
  echo ""
  echo "  1. Vercel 대시보드에서 New Project"
  echo "  2. ${FRONT_ORG}/front-${PROJECT_NAME} 레포 연결"
  echo "  3. Root Directory 설정 불필요 (레포 루트가 Next.js 프로젝트)"
  echo "  4. main → Production, dev → Preview 자동 매핑"
  echo ""
fi

echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Next steps${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. 위 수동 Secrets 등록 (SSH, Slack, 서버 정보)"
if [ "$CREATE_FRONT" = true ]; then
  echo "  2. Vercel 프로젝트 연결"
fi
echo "  3. git push origin main → sync-repos.yml 자동 실행"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  TODO${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  - [ ] Infisical 셀프호스팅 서버 구축"
echo "  - [ ] .pem 파일을 Infisical에 보관 (현재: ${GITHUB_APP_PEM})"
echo "  - [ ] Infisical 연동 후 GitHub Secrets → Infisical 전환"
echo ""
