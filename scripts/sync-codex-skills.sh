#!/bin/bash
set -euo pipefail

# gstack 업그레이드 후 Codex용 스킬을 자동 재생성하는 스크립트
# 사용법: ./scripts/sync-codex-skills.sh
#
# /gstack-upgrade 실행 후 자동으로 호출된다.
# 1. gen-skill-docs --host codex 로 Codex 포맷 SKILL.md 생성
#    (gstack 내부 .agents/skills/ 에 생성됨)
# 2. 생성된 스킬을 프로젝트 루트 .agents/skills/ 로 이동
# 3. 사이드카 심링크 생성
# 4. 글로벌 ~/.codex/skills/ 정리

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GSTACK_DIR="$PROJECT_ROOT/.claude/skills/gstack"
GSTACK_AGENTS="$GSTACK_DIR/.agents/skills"
AGENTS_SKILLS_DIR="$PROJECT_ROOT/.agents/skills"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [ ! -d "$GSTACK_DIR" ]; then
  error "gstack 디렉토리를 찾을 수 없습니다: $GSTACK_DIR"
  exit 1
fi

# Step 1: Codex 포맷 SKILL.md 생성
info "Step 1: Codex용 gstack 스킬 생성 중..."
cd "$GSTACK_DIR"
bun run scripts/gen-skill-docs.ts --host codex 2>&1 | grep "^GENERATED:" | wc -l | xargs -I{} echo "  {}개 스킬 생성됨"

# Step 2: gstack 내부에서 프로젝트 루트로 이동
info "Step 2: .agents/skills/ 로 이동 중..."
MOVED=0
for skill_dir in "$GSTACK_AGENTS"/gstack-*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  target_dir="$AGENTS_SKILLS_DIR/$skill_name"

  rm -rf "$target_dir"
  mv "$skill_dir" "$target_dir"
  MOVED=$((MOVED + 1))
done

# gstack 런타임 루트도 이동
if [ -d "$GSTACK_AGENTS/gstack" ]; then
  rm -rf "$AGENTS_SKILLS_DIR/gstack"
  mv "$GSTACK_AGENTS/gstack" "$AGENTS_SKILLS_DIR/gstack"
fi

# gstack 내부의 .agents/ 정리
rm -rf "$GSTACK_AGENTS"

# Step 3: 사이드카 심링크 설정 (런타임 에셋 참조용)
info "Step 3: 사이드카 심링크 설정 중..."
SIDECAR_DIR="$AGENTS_SKILLS_DIR/gstack"
mkdir -p "$SIDECAR_DIR"

for target in bin browse review qa ETHOS.md; do
  src="$GSTACK_DIR/$target"
  dest="$SIDECAR_DIR/$target"
  if [ -e "$src" ]; then
    rm -rf "$dest"
    ln -snf "$src" "$dest"
  fi
done

# Step 4: 글로벌 ~/.codex/skills/ 정리 (있으면)
if ls "$HOME/.codex/skills/gstack"* &>/dev/null 2>&1; then
  info "Step 4: 글로벌 ~/.codex/skills/gstack* 정리 중..."
  rm -rf "$HOME/.codex/skills"/gstack*
fi

info "완료: ${MOVED}개 Codex 스킬을 .agents/skills/ 에 동기화"
