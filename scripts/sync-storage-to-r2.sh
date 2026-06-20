#!/bin/bash

# 로컬 스토리지 → Cloudflare R2 동기화 스크립트
#
# 사용법:
#   ./sync-storage-to-r2.sh <service> <env> [--dry-run]
#
# 예시:
#   ./sync-storage-to-r2.sh camppick prod
#   ./sync-storage-to-r2.sh camppick dev
#   ./sync-storage-to-r2.sh openfolio prod
#   ./sync-storage-to-r2.sh openfolio prod --dry-run
#
# R2 버킷 구조 (버킷을 서비스+환경별로 분리):
#   camppick-prod  버킷: image/ab/cd/{uuid}_medium.jpg
#   camppick-dev   버킷: image/ab/cd/{uuid}_medium.jpg
#   openfolio-prod 버킷: uploads/...
#   openfolio-dev  버킷: uploads/...
#
# rclone remote 설정 (서비스별 API 토큰 분리):
#   r2-camppick  → camppick-prod, camppick-dev 버킷 전용 토큰
#   r2-openfolio → openfolio-prod, openfolio-dev 버킷 전용 토큰

set -e

# ── 서비스별 설정 ─────────────────────────────────────────────────────────────
declare -A LOCAL_DIR=(
    [camppick]="/var/lib/docker-data/camppick2/storage"
    [openfolio]="/var/lib/docker-data/openfolio/uploads"
)
declare -A R2_PATH_PREFIX=(
    [camppick]="image"
    [openfolio]="uploads"
)

TRANSFERS=16
CHECKERS=32
LOG_DIR="/var/log/r2-sync"
# ─────────────────────────────────────────────────────────────────────────────

# ── 인자 파싱 ──────────────────────────────────────────────────────────────────
SERVICE="$1"
ENV="$2"
DRY_RUN=false
[[ "$3" == "--dry-run" ]] && DRY_RUN=true

usage() {
    echo "사용법: $0 <service> <env> [--dry-run]"
    echo "  service: camppick | openfolio"
    echo "  env:     prod | dev"
    exit 1
}

[[ -z "$SERVICE" || -z "$ENV" ]] && usage
[[ "$SERVICE" != "camppick" && "$SERVICE" != "openfolio" ]] && { echo "Error: 알 수 없는 서비스 '$SERVICE'"; usage; }
[[ "$ENV" != "prod" && "$ENV" != "dev" ]] && { echo "Error: 알 수 없는 환경 '$ENV'"; usage; }
# ─────────────────────────────────────────────────────────────────────────────

LOCAL="${LOCAL_DIR[$SERVICE]}"
R2_REMOTE="r2-${SERVICE}"
R2_TARGET="${R2_REMOTE}:${SERVICE}-${ENV}"

# ── 사전 확인 ──────────────────────────────────────────────────────────────────
if ! command -v rclone &> /dev/null; then
    echo "Error: rclone이 설치되어 있지 않습니다."
    echo "설치: curl https://rclone.org/install.sh | sudo bash"
    exit 1
fi

if ! rclone listremotes | grep -q "^${R2_REMOTE}:"; then
    echo "Error: rclone remote '${R2_REMOTE}'가 설정되어 있지 않습니다."
    echo "설정: rclone config  (remote 이름: ${R2_REMOTE})"
    exit 1
fi

if [[ ! -d "$LOCAL" ]]; then
    echo "Error: 로컬 디렉토리가 없습니다: $LOCAL"
    exit 1
fi
# ─────────────────────────────────────────────────────────────────────────────

STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$STARTED_AT] 동기화 시작"
echo "  로컬  : $LOCAL"
echo "  R2    : $R2_TARGET"
$DRY_RUN && echo "  [드라이런] 실제 파일은 복사되지 않습니다."
echo ""

RCLONE_ARGS=(
    sync
    "$LOCAL"
    "$R2_TARGET"
    --progress
    --transfers "$TRANSFERS"
    --checkers "$CHECKERS"
    --fast-list
    --stats-one-line
)

if $DRY_RUN; then
    RCLONE_ARGS+=(--dry-run)
else
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${SERVICE}-${ENV}-$(date '+%Y%m%d-%H%M%S').log"
    RCLONE_ARGS+=(--log-file "$LOG_FILE" --log-level INFO)
fi

rclone "${RCLONE_ARGS[@]}"

FINISHED_AT=$(date '+%Y-%m-%d %H:%M:%S')
echo ""
echo "[$FINISHED_AT] 완료"

if ! $DRY_RUN; then
    echo "  로그  : $LOG_FILE"
    echo ""
    echo "── R2 용량 확인 ──"
    rclone size "$R2_TARGET"
fi
