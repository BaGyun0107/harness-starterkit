#!/bin/bash
set -euo pipefail

# ── harness 프로젝트 초기화 스크립트 ──
# 사용법: ./scripts/init-project.sh <project-name> <front-org> <back-org>
# 예시:   ./scripts/init-project.sh my-app your-front-org your-back-org

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

# ── 인자 검증 ──
if [ $# -lt 3 ]; then
  echo "Usage: $0 <project-name> <front-org> <back-org>"
  echo ""
  echo "Arguments:"
  echo "  project-name  프로젝트 이름 (예: my-app)"
  echo "  front-org     Front 레포가 위치할 GitHub Organization"
  echo "  back-org      Back/Dev 레포가 위치할 GitHub Organization"
  echo ""
  echo "Example:"
  echo "  $0 my-app your-front-org your-back-org"
  echo ""
  echo "Prerequisites:"
  echo "  - GitHub CLI (gh) 설치 및 로그인"
  echo "  - 대상 Organization에 레포 생성 권한"
  echo "  - GitHub App private key (.pem) 파일"
  echo "    기본 경로: 프로젝트 루트/repo-sync.private-key.pem"
  echo "    또는 GITHUB_APP_PEM 환경변수로 지정"
  exit 1
fi

PROJECT_NAME="$1"
FRONT_ORG="$2"
BACK_ORG="$3"

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

# ══════════════════════════════════════════════════════════
#  Step 1: 레포 생성
# ══════════════════════════════════════════════════════════
info "Step 1/6: GitHub 레포 생성..."

info "  dev-${PROJECT_NAME} (개발 모노레포)"
gh repo create "${BACK_ORG}/dev-${PROJECT_NAME}" --private --description "Development monorepo for ${PROJECT_NAME}"
CREATED_REPOS+=("${BACK_ORG}/dev-${PROJECT_NAME}")

info "  front-${PROJECT_NAME} (Vercel 배포용)"
gh repo create "${FRONT_ORG}/front-${PROJECT_NAME}" --private --description "Frontend deploy repo for ${PROJECT_NAME}"
CREATED_REPOS+=("${FRONT_ORG}/front-${PROJECT_NAME}")

info "  back-${PROJECT_NAME} (Docker 배포용)"
gh repo create "${BACK_ORG}/back-${PROJECT_NAME}" --private --description "Backend deploy repo for ${PROJECT_NAME}"
CREATED_REPOS+=("${BACK_ORG}/back-${PROJECT_NAME}")

# ══════════════════════════════════════════════════════════
#  Step 2: 플레이스홀더 치환
# ══════════════════════════════════════════════════════════
info "Step 2/6: 워크플로우 플레이스홀더 치환..."

if [ -f ".github/workflows/sync-repos.yml" ]; then
  replace_in_file "s/__PROJECT__/${PROJECT_NAME}/g" .github/workflows/sync-repos.yml
  replace_in_file "s/__FRONT_ORG__/${FRONT_ORG}/g" .github/workflows/sync-repos.yml
  replace_in_file "s/__BACK_ORG__/${BACK_ORG}/g" .github/workflows/sync-repos.yml
  info "  sync-repos.yml 치환 완료"
fi

if [ -f ".github/workflows/deploy.yml" ]; then
  replace_in_file "s/__PROJECT__/${PROJECT_NAME}/g" .github/workflows/deploy.yml
  info "  deploy.yml 치환 완료"
fi

if [ -f ".infisical.json.tmpl" ]; then
  cp .infisical.json.tmpl .infisical.json
  replace_in_file "s/__PROJECT__/${PROJECT_NAME}/g" .infisical.json
  info "  .infisical.json 생성 완료"
fi

# ══════════════════════════════════════════════════════════
#  Step 3: GitHub App 토큰 발급 + 시크릿 자동 등록
# ══════════════════════════════════════════════════════════
info "Step 3/6: GitHub App 시크릿 자동 등록..."

# dev-{project} 레포에 App ID + Private Key 등록
# sync-repos.yml이 actions/create-github-app-token으로 매 실행마다 토큰을 자동 발급
echo "$GITHUB_APP_ID" | gh secret set APP_ID --repo "${BACK_ORG}/dev-${PROJECT_NAME}"
info "  APP_ID 시크릿 등록 완료"

gh secret set APP_PRIVATE_KEY --repo "${BACK_ORG}/dev-${PROJECT_NAME}" < "$GITHUB_APP_PEM"
info "  APP_PRIVATE_KEY 시크릿 등록 완료"

# ══════════════════════════════════════════════════════════
#  Step 4: Git remote 설정
# ══════════════════════════════════════════════════════════
info "Step 4/6: Git remote 설정..."

if git remote get-url origin &>/dev/null; then
  git remote set-url origin "https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}.git"
else
  git remote add origin "https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}.git"
fi
info "  origin → ${BACK_ORG}/dev-${PROJECT_NAME}"

# ══════════════════════════════════════════════════════════
#  Step 5: 브랜치 설정 및 push
# ══════════════════════════════════════════════════════════
info "Step 5/6: 브랜치 설정..."

git add -A
git commit -m "chore: init project ${PROJECT_NAME} from harness" --allow-empty || true
git push -u origin main

git checkout -b dev
git push -u origin dev
git checkout main

info "  main, dev 브랜치 생성 완료"

# ══════════════════════════════════════════════════════════
#  Step 6: 안내 출력
# ══════════════════════════════════════════════════════════
info "Step 6/6: 설정 안내..."

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Project ${PROJECT_NAME} initialized!${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Repos created:"
echo "    dev:   https://github.com/${BACK_ORG}/dev-${PROJECT_NAME}"
echo "    front: https://github.com/${FRONT_ORG}/front-${PROJECT_NAME}"
echo "    back:  https://github.com/${BACK_ORG}/back-${PROJECT_NAME}"
echo ""
echo "  Auto-configured:"
echo "    ✅ APP_ID           (GitHub App ID)"
echo "    ✅ APP_PRIVATE_KEY  (GitHub App private key)"
echo "    → sync-repos.yml이 매 실행마다 토큰을 자동 발급합니다 (만료 걱정 없음)"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  수동 설정 필요${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  dev-${PROJECT_NAME} 레포 Settings → Secrets → Actions:"
echo ""
echo "    SLACK_WEBHOOK_URL  Slack Incoming Webhook URL"
echo ""
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
echo "    SERVER_ENV_FILE    백엔드 .env 파일 내용"
echo "    FRONT_ENV_FILE     프론트 .env.local 파일 내용"
echo ""
# TODO: Infisical 구축 후 아래 주석 해제
# echo "  Infisical 설정:"
# echo "    INFISICAL_TOKEN   Infisical Machine Identity 토큰"
# echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  Vercel 연결${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. Vercel 대시보드에서 New Project"
echo "  2. ${FRONT_ORG}/front-${PROJECT_NAME} 레포 연결"
echo "  3. Root Directory 설정 불필요 (레포 루트가 Next.js 프로젝트)"
echo "  4. main → Production, dev → Preview 자동 매핑"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}  Next steps${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  1. 위 수동 Secrets 등록 (SSH, Slack, 서버 정보)"
echo "  2. Vercel 프로젝트 연결"
echo "  3. apps/front/ 에 Next.js 프로젝트 초기화"
echo "  4. apps/back/ 에 Express 프로젝트 초기화"
echo "  5. git push origin main → sync-repos.yml 자동 실행"
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}  TODO${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  - [ ] Infisical 셀프호스팅 서버 구축"
echo "  - [ ] .pem 파일을 Infisical에 보관 (현재: ${GITHUB_APP_PEM})"
echo "  - [ ] Infisical 연동 후 GitHub Secrets → Infisical 전환"
echo ""
