#!/bin/bash
# ── Infisical 자동 부트스트랩 (Self-hosted: https://env.co-di.com) ──
#
# 목적: Org Admin 권한이 부여된 Machine Identity 1개로 다음을 자동화한다.
#   1) Universal Auth 로그인 → access token 발급
#   2) 프로젝트 생성 (이미 존재하면 재사용)
#   3) Machine Identity를 신규 프로젝트 admin으로 self-add
#   4) dev 환경에 폴더 4개 생성: /backend, /backend/github-actions,
#                                /frontend, /frontend/github-actions
#   5) 폴더별 표준 키를 빈 placeholder로 등록
#
# 사용법: bootstrap_infisical "<project-name>"
#   필수 env: INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET, INFISICAL_IDENTITY_ID
#   선택 env: INFISICAL_API_URL (기본 https://env.co-di.com)
#             INFISICAL_ORG_SLUG (Universal Auth가 여러 조직에 걸쳐 있을 때만)
#
# 출력: 표준출력 마지막 줄에 생성/재사용된 projectId만 출력 (호출자가 캡처)
# 모든 진행 로그는 stderr로 보낸다.

set -euo pipefail

# ── 색상/로거 (호출자 정의가 없으면 자체 정의) ──
if ! declare -F info >/dev/null 2>&1; then
  _IFC_RED='\033[0;31m'; _IFC_GREEN='\033[0;32m'; _IFC_YELLOW='\033[1;33m'; _IFC_NC='\033[0m'
  info()  { echo -e "${_IFC_GREEN}[INFO]${_IFC_NC} $*" >&2; }
  warn()  { echo -e "${_IFC_YELLOW}[WARN]${_IFC_NC} $*" >&2; }
  error() { echo -e "${_IFC_RED}[ERROR]${_IFC_NC} $*" >&2; }
fi

# ── 표준 키 목록 (CLAUDE.md의 Infisical 경로 표 기반) ──
_IFC_KEYS_BACKEND=(DATABASE_URL JWT_SECRET JWT_REFRESH_SECRET NODE_ENV PORT)
_IFC_KEYS_BACKEND_GHA=(BACK_SERVER_HOST BACK_SERVER_USER BACK_DEPLOY_DIR BACK_APP_NAME BACK_TAR_FILE BACK_SSH_PRIVATE_KEY BACK_APP_TYPE)
_IFC_KEYS_FRONTEND=(NEXT_PUBLIC_API_URL)
_IFC_KEYS_FRONTEND_GHA=(VERCEL_ORG_ID VERCEL_PROJECT_ID)

# ── 내부 HTTP 헬퍼 ──
# _ifc_request <method> <path> [json_body]
# 성공 시 응답 본문을 stdout으로, 실패 시 stderr로 에러 후 1 반환
_ifc_request() {
  local method="$1" path="$2" body="${3:-}"
  local url="${INFISICAL_API_URL}${path}"
  local tmp; tmp="$(mktemp)"
  local code
  if [ -n "$body" ]; then
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$url" \
      -H "Authorization: Bearer ${_IFC_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$body")
  else
    code=$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$url" \
      -H "Authorization: Bearer ${_IFC_TOKEN}")
  fi
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    cat "$tmp"; rm -f "$tmp"; return 0
  fi
  # 호출자가 처리할 수 있도록 본문과 코드를 함께 반환 (stderr가 아닌 stdout으로)
  cat "$tmp"
  rm -f "$tmp"
  return "$code"
}

# ── 1) Universal Auth 로그인 ──
_ifc_login() {
  info "Infisical Universal Auth 로그인..."
  local body
  if [ -n "${INFISICAL_ORG_SLUG:-}" ]; then
    body=$(jq -nc \
      --arg cid "$INFISICAL_CLIENT_ID" \
      --arg cs  "$INFISICAL_CLIENT_SECRET" \
      --arg org "$INFISICAL_ORG_SLUG" \
      '{clientId:$cid, clientSecret:$cs, organizationSlug:$org}')
  else
    body=$(jq -nc \
      --arg cid "$INFISICAL_CLIENT_ID" \
      --arg cs  "$INFISICAL_CLIENT_SECRET" \
      '{clientId:$cid, clientSecret:$cs}')
  fi
  local resp
  resp=$(curl -sS -X POST "${INFISICAL_API_URL}/api/v1/auth/universal-auth/login" \
    -H "Content-Type: application/json" \
    --data "$body")
  _IFC_TOKEN=$(echo "$resp" | jq -er '.accessToken' 2>/dev/null) || {
    error "Universal Auth 로그인 실패. 응답: $resp"
    return 1
  }
  info "  로그인 성공"
}

# ── 2) 프로젝트 생성 또는 재사용 ──
# 기존 프로젝트 검색은 GET /api/v2/workspace 사용 (Identity가 멤버인 워크스페이스만 반환)
# 이름이 같은 프로젝트가 있으면 그 ID를 재사용. 없으면 POST로 생성.
_ifc_get_or_create_project() {
  local project_name="$1"
  # 목록 조회는 /api/v1/workspace (v2 GET은 미존재), 생성은 /api/v2/workspace (POST)
  local list_resp
  list_resp=$(curl -sS "${INFISICAL_API_URL}/api/v1/workspace" \
    -H "Authorization: Bearer ${_IFC_TOKEN}")
  local existing_id
  existing_id=$(echo "$list_resp" | jq -er --arg n "$project_name" \
    '.workspaces[]? | select(.name == $n or .slug == $n) | .id' 2>/dev/null | head -1 || true)
  if [ -n "$existing_id" ]; then
    info "  기존 프로젝트 재사용: $project_name (id=$existing_id)"
    _IFC_PROJECT_ID="$existing_id"
    return 0
  fi
  info "  프로젝트 생성: $project_name"
  local body
  body=$(jq -nc --arg n "$project_name" --arg s "$project_name" \
    '{projectName:$n, slug:$s, type:"secret-manager"}')
  local resp
  resp=$(curl -sS -X POST "${INFISICAL_API_URL}/api/v2/workspace" \
    -H "Authorization: Bearer ${_IFC_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$body")
  _IFC_PROJECT_ID=$(echo "$resp" | jq -er '.project.id // .workspace.id // .id' 2>/dev/null) || {
    error "프로젝트 생성 실패. 응답: $resp"
    return 1
  }
  info "    생성 완료 (id=${_IFC_PROJECT_ID})"
}

# ── 3) Machine Identity self-add (admin) ──
# 이미 멤버이면 409/400 가능 — 멱등성을 위해 실패해도 경고만 띄우고 진행
_ifc_add_identity_to_project() {
  info "  Machine Identity를 프로젝트 admin으로 등록..."
  local body
  body=$(jq -nc '{role:"admin"}')
  local resp http_code
  http_code=$(curl -sS -o /tmp/_ifc_addid.json -w "%{http_code}" \
    -X POST "${INFISICAL_API_URL}/api/v1/projects/${_IFC_PROJECT_ID}/identity-memberships/${INFISICAL_IDENTITY_ID}" \
    -H "Authorization: Bearer ${_IFC_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$body")
  resp=$(cat /tmp/_ifc_addid.json); rm -f /tmp/_ifc_addid.json
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    info "    등록 완료"
  elif echo "$resp" | grep -qiE 'already|exists|duplicate'; then
    info "    이미 멤버 — 건너뜀"
  else
    warn "    Identity 등록 실패 (http=${http_code}). 본인 Identity가 이미 멤버일 수 있음. 응답: $resp"
  fi
}

# ── 4) 폴더 생성 (멱등) ──
# 같은 path 내 같은 이름이 있으면 4xx 응답 — "already exists" 메시지면 무시
_ifc_create_folder() {
  local env_slug="$1" path="$2" name="$3"
  local body
  body=$(jq -nc \
    --arg pid "$_IFC_PROJECT_ID" \
    --arg env "$env_slug" \
    --arg p   "$path" \
    --arg n   "$name" \
    '{projectId:$pid, environment:$env, path:$p, name:$n}')
  local resp http_code
  http_code=$(curl -sS -o /tmp/_ifc_folder.json -w "%{http_code}" \
    -X POST "${INFISICAL_API_URL}/api/v2/folders" \
    -H "Authorization: Bearer ${_IFC_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$body")
  resp=$(cat /tmp/_ifc_folder.json); rm -f /tmp/_ifc_folder.json
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    info "    [+] ${path%/}/${name}"
  elif echo "$resp" | grep -qiE 'already|exists|duplicate'; then
    info "    [=] ${path%/}/${name} (이미 존재)"
  else
    warn "    [!] ${path%/}/${name} 생성 실패 (http=${http_code}). 응답: $resp"
  fi
}

# ── 5) 시크릿 placeholder 생성 (멱등) ──
_ifc_create_secret_placeholder() {
  local env_slug="$1" secret_path="$2" key="$3"
  local body
  body=$(jq -nc \
    --arg wid "$_IFC_PROJECT_ID" \
    --arg env "$env_slug" \
    --arg p   "$secret_path" \
    --arg v   "" \
    '{workspaceId:$wid, environment:$env, secretPath:$p, secretValue:$v, type:"shared"}')
  local resp http_code
  http_code=$(curl -sS -o /tmp/_ifc_secret.json -w "%{http_code}" \
    -X POST "${INFISICAL_API_URL}/api/v3/secrets/raw/${key}" \
    -H "Authorization: Bearer ${_IFC_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "$body")
  resp=$(cat /tmp/_ifc_secret.json); rm -f /tmp/_ifc_secret.json
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    info "      [+] ${key}"
  elif echo "$resp" | grep -qiE 'already|exists|duplicate'; then
    info "      [=] ${key} (이미 존재)"
  else
    warn "      [!] ${key} 등록 실패 (http=${http_code}). 응답: $resp"
  fi
}

# ── 메인 진입점 ──
bootstrap_infisical() {
  local project_name="$1"
  : "${INFISICAL_API_URL:=https://env.co-di.com}"
  : "${INFISICAL_CLIENT_ID:?INFISICAL_CLIENT_ID 가 필요합니다}"
  : "${INFISICAL_CLIENT_SECRET:?INFISICAL_CLIENT_SECRET 가 필요합니다}"
  : "${INFISICAL_IDENTITY_ID:?INFISICAL_IDENTITY_ID 가 필요합니다 (Machine Identity의 ID)}"

  if ! command -v jq >/dev/null 2>&1; then
    error "jq가 필요합니다. 설치: brew install jq"
    return 1
  fi

  _ifc_login

  info "Infisical 프로젝트 준비..."
  _ifc_get_or_create_project "$project_name"

  _ifc_add_identity_to_project

  local env_slug="dev"
  info "  폴더 생성 (env=${env_slug})..."
  _ifc_create_folder "$env_slug" "/"         "backend"
  _ifc_create_folder "$env_slug" "/backend"  "github-actions"
  _ifc_create_folder "$env_slug" "/"         "frontend"
  _ifc_create_folder "$env_slug" "/frontend" "github-actions"

  info "  시크릿 placeholder 등록..."
  info "    /backend"
  for k in "${_IFC_KEYS_BACKEND[@]}"; do
    _ifc_create_secret_placeholder "$env_slug" "/backend" "$k"
  done
  info "    /backend/github-actions"
  for k in "${_IFC_KEYS_BACKEND_GHA[@]}"; do
    _ifc_create_secret_placeholder "$env_slug" "/backend/github-actions" "$k"
  done
  info "    /frontend"
  for k in "${_IFC_KEYS_FRONTEND[@]}"; do
    _ifc_create_secret_placeholder "$env_slug" "/frontend" "$k"
  done
  info "    /frontend/github-actions"
  for k in "${_IFC_KEYS_FRONTEND_GHA[@]}"; do
    _ifc_create_secret_placeholder "$env_slug" "/frontend/github-actions" "$k"
  done

  info "Infisical 부트스트랩 완료 (projectId=${_IFC_PROJECT_ID})"
  # 호출자가 캡처할 수 있도록 마지막 줄에 projectId만 stdout으로 출력
  echo "$_IFC_PROJECT_ID"
}
