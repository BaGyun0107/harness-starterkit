#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# 범용 서버 배포 스크립트 (front / back 공용)
# ═══════════════════════════════════════════════════════════════════════
#
# 배포 대상 서버에 이 파일 하나만 배치해두면 모든 프로젝트의 배포를 처리한다.
# 이전에는 프로젝트별로 dev/prd 스크립트를 복사하고 BASE_PATH/TAR_FILE/APP_NAME을
# 매번 수정해야 했는데, 이 스크립트는 인자로 받아 처리하므로 복사 불필요.
#
# 사용법:
#   ./server-deploy.sh <BASE_PATH> <TAR_FILE> <APP_NAME> <ENV>
#
# 예시:
#   ./server-deploy.sh /home/rocky/CODI.live-view-back-dev codi_live_view_back_dev.tar.gz codi-live-view-back-dev development
#   ./server-deploy.sh /home/rocky/CODI.live-view-user-prd codi_live_view_user_prd.tar.gz codi-live-view-user-prd production
#
# 인자:
#   BASE_PATH  — 배포 루트 디렉터리 (releases/, current/ 가 이 아래에 생성됨)
#   TAR_FILE   — 업로드된 tar.gz 파일명 (BASE_PATH 하위에 있어야 함)
#   APP_NAME   — PM2 ecosystem.config.js 의 앱 이름
#   ENV        — development | production  (.env.development / .env.production 치환용)
#
# 롤백:
#   ./server-deploy.sh <BASE_PATH> <TAR_FILE> <APP_NAME> <ENV> rollback
#
# 프로젝트별 후처리 훅 (선택):
#   BASE_PATH/post-deploy.sh 파일이 존재하면 current로 이동 후 실행한다.
#   예: puppeteer 크롬 설치, DB 마이그레이션 등
#
# 설치:
#   이 파일을 배포 대상 서버의 원하는 경로에 복사한 뒤 실행 권한 부여:
#     scp scripts/server-deploy.sh rocky@<server>:~/server-deploy.sh
#     ssh rocky@<server> "chmod +x ~/server-deploy.sh"
# ═══════════════════════════════════════════════════════════════════════

set -e

# ── 인자 파싱 ──
if [ $# -lt 4 ]; then
    echo "Usage: $0 <BASE_PATH> <TAR_FILE> <APP_NAME> <ENV> [rollback]"
    echo ""
    echo "Arguments:"
    echo "  BASE_PATH  배포 루트 디렉터리"
    echo "  TAR_FILE   업로드된 tar.gz 파일명"
    echo "  APP_NAME   PM2 앱 이름"
    echo "  ENV        development | production"
    echo ""
    echo "Example:"
    echo "  $0 /home/rocky/CODI.live-view-back-dev codi_live_view_back_dev.tar.gz codi-live-view-back-dev development"
    exit 1
fi

BASE_PATH="$1"
TAR_FILE="$2"
APP_NAME="$3"
ENV="$4"
MODE="${5:-deploy}"

CURRENT_PATH="$BASE_PATH/current"
RELEASES_PATH="$BASE_PATH/releases"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RELEASE_PATH="$RELEASES_PATH/$TIMESTAMP"
KEEP_RELEASES=5

# ENV 검증 및 .env 파일명 결정
case "$ENV" in
    development) ENV_FILE=".env.development"; ENV_SRC="env.development" ;;
    production)  ENV_FILE=".env.production";  ENV_SRC="env.production"  ;;
    *)
        echo "[ERROR] 알 수 없는 ENV: $ENV (development 또는 production)" >&2
        exit 1
        ;;
esac

# ── 로깅 ──
log()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2; }

# ── 디렉토리 생성 ──
create_directories() {
    log "디렉토리 구조 생성: $BASE_PATH"
    mkdir -p "$RELEASES_PATH"
    mkdir -p "$RELEASE_PATH"
}

# ── 기존 current 아카이빙 ──
archive_current() {
    if [ -d "$CURRENT_PATH" ] && [ "$(ls -A "$CURRENT_PATH" 2>/dev/null)" ]; then
        log "기존 서버 아카이빙: $CURRENT_PATH → $RELEASE_PATH"
        cp -a "$CURRENT_PATH/." "$RELEASE_PATH/"
    else
        log "기존 서버 없음 → 첫 배포"
    fi
}

# ── 오래된 릴리즈 정리 ──
cleanup_old_releases() {
    log "오래된 릴리즈 정리 (최근 $KEEP_RELEASES개 유지)"
    cd "$RELEASES_PATH"
    ls -t | tail -n +$((KEEP_RELEASES + 1)) | while read -r old_release; do
        if [ -d "$old_release" ]; then
            log "삭제: $RELEASES_PATH/$old_release"
            rm -rf "$old_release"
        fi
    done
}

# ── tar 해제 + current 교체 ──
deploy_new_version() {
    cd "$BASE_PATH"

    if [ ! -f "$TAR_FILE" ]; then
        error "압축 파일 없음: $BASE_PATH/$TAR_FILE"
        exit 1
    fi

    local temp_path="$BASE_PATH/temp_$TIMESTAMP"
    mkdir -p "$temp_path"

    log "압축 해제: $TAR_FILE → $temp_path"
    tar -xzf "$TAR_FILE" -C "$temp_path"

    # 환경 파일 이름 정규화 (env.xxx → .env.xxx)
    if [ -f "$temp_path/$ENV_SRC" ]; then
        log "환경 파일 rename: $ENV_SRC → $ENV_FILE"
        mv "$temp_path/$ENV_SRC" "$temp_path/$ENV_FILE"
        chmod 444 "$temp_path/$ENV_FILE"
    fi

    log "current 교체"
    rm -rf "$CURRENT_PATH"
    mv "$temp_path" "$CURRENT_PATH"
    chmod 755 "$CURRENT_PATH"

    rm -f "$TAR_FILE"
    log "배포 완료: $CURRENT_PATH"
}

# ── 프로젝트별 후처리 훅 ──
run_post_deploy_hook() {
    local hook="$BASE_PATH/post-deploy.sh"
    if [ -f "$hook" ]; then
        log "post-deploy 훅 실행: $hook"
        (cd "$CURRENT_PATH" && sh "$hook") || {
            error "post-deploy 훅 실패"
            return 1
        }
    fi
}

# ── PM2 재시작 ──
restart_pm2() {
    log "PM2 상태 저장"
    pm2 save

    cd "$CURRENT_PATH" || { error "디렉토리 이동 실패: $CURRENT_PATH"; exit 1; }

    if ! pm2 list | grep -q "$APP_NAME"; then
        log "[$APP_NAME] 신규 시작"
        pm2 start ecosystem.config.js --only "$APP_NAME"

    elif ! pm2 list | grep "$APP_NAME" | grep -q "online"; then
        log "[$APP_NAME] offline 상태 → start"
        pm2 start ecosystem.config.js --only "$APP_NAME"

    elif pm2 list | grep "$APP_NAME" | grep -q "cluster"; then
        log "[$APP_NAME] cluster 모드 → reload"
        if ! pm2 reload "$APP_NAME" --update-env; then
            log "[$APP_NAME] reload 실패 → restart fallback"
            pm2 restart "$APP_NAME" --update-env
        fi

        log "[$APP_NAME] 안정화 대기 (5초)"
        sleep 5

        if pm2 list | grep "$APP_NAME" | grep -q "online"; then
            log "[$APP_NAME] 정상 실행 확인"
            pm2 reset "$APP_NAME"
        else
            error "[$APP_NAME] 경고: 일부 인스턴스가 online 상태 아님"
            pm2 list | grep "$APP_NAME"
        fi

    else
        log "[$APP_NAME] fork 모드 → restart"
        pm2 restart ecosystem.config.js --only "$APP_NAME" --update-env
        pm2 reset "$APP_NAME"
    fi

    log "PM2 재시작 완료"
}

# ── 롤백 ──
rollback() {
    log "롤백 시작: $APP_NAME"

    local last_release
    last_release=$(ls -t "$RELEASES_PATH" 2>/dev/null | head -n 1)

    if [ -z "$last_release" ]; then
        error "롤백할 이전 버전이 없습니다."
        exit 1
    fi

    log "롤백 대상: $RELEASES_PATH/$last_release"
    rm -rf "$CURRENT_PATH"
    cp -a "$RELEASES_PATH/$last_release" "$CURRENT_PATH"

    log "롤백 완료 → PM2 재시작"
    restart_pm2
}

# ── 메인 ──
main() {
    log "═══════════════════════════════════════════════════"
    log "배포 시작: $APP_NAME ($ENV) @ $TIMESTAMP"
    log "═══════════════════════════════════════════════════"

    create_directories
    archive_current
    deploy_new_version
    run_post_deploy_hook
    cleanup_old_releases
    restart_pm2

    log "═══════════════════════════════════════════════════"
    log "배포 완료: $APP_NAME"
    log "현재 버전: $CURRENT_PATH"
    log "이전 버전: $RELEASE_PATH"
    log "═══════════════════════════════════════════════════"
}

if [ "$MODE" = "rollback" ]; then
    rollback
else
    main
fi
