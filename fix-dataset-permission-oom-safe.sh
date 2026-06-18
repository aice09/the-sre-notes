#!/usr/bin/env bash
# =============================================================================
# fix-dataset-perms-oom-safe.sh
# 
# Safely chown + chmod datasets mounted into pods without OOM issues.
# 
# Strategy:
#   - Processes datasets SERIALLY (one at a time) per pod to avoid memory spikes
#   - Uses `find` with `-exec` instead of `-R` flags (avoids large inode lists)
#   - Logs start time, end time, dataset path per dataset to a log file
#   - Finishes one dataset completely before starting the next
#   - Supports dry-run mode
#
# Usage:
#   ./fix-dataset-perms-oom-safe.sh [OPTIONS]
#
# Options:
#   -d, --datasets-root DIR   Root path where datasets live (default: /datasets)
#   -o, --owner USER:GROUP    Owner to set (default: root:root)
#   -l, --log-dir DIR         Directory to write logs (default: /tmp/perm-fix-logs)
#   -p, --pod-name NAME       Pod name for log file naming (default: hostname)
#   --dry-run                 Print what would happen without making changes
#   -h, --help                Show this help
#
# Example:
#   ./fix-dataset-perms-oom-safe.sh \
#     --datasets-root /datasets \
#     --owner root:root \
#     --log-dir /var/log/perm-fix \
#     --pod-name pod-0
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------- #
# Defaults
# ---------------------------------------------------------------------------- #
DATASETS_ROOT="/datasets"
OWNER="root:root"
LOG_DIR="/tmp/perm-fix-logs"
POD_NAME="${HOSTNAME:-pod}"
DRY_RUN=false

DIR_MODE="775"
FILE_MODE="664"

# ---------------------------------------------------------------------------- #
# Colors
# ---------------------------------------------------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${RESET} $*"; }
ok()      { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✔${RESET} $*"; }
warn()    { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${RESET} $*"; }
err()     { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✘${RESET} $*" >&2; }
dryrun()  { echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; }

# ---------------------------------------------------------------------------- #
# Argument parsing
# ---------------------------------------------------------------------------- #
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,\}//' | head -30
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--datasets-root) DATASETS_ROOT="$2"; shift 2 ;;
    -o|--owner)         OWNER="$2";          shift 2 ;;
    -l|--log-dir)       LOG_DIR="$2";        shift 2 ;;
    -p|--pod-name)      POD_NAME="$2";       shift 2 ;;
    --dry-run)          DRY_RUN=true;        shift ;;
    -h|--help)          usage ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------- #
# Setup log file
# ---------------------------------------------------------------------------- #
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${POD_NAME}-$(date '+%Y%m%d_%H%M%S').log"
SUMMARY_FILE="${LOG_DIR}/${POD_NAME}-summary.csv"

# Tee all output to log file as well
exec > >(tee -a "$LOG_FILE") 2>&1

log "========================================================"
log " fix-dataset-perms-oom-safe.sh"
log " Pod:           $POD_NAME"
log " Datasets root: $DATASETS_ROOT"
log " Owner:         $OWNER"
log " Dir mode:      $DIR_MODE"
log " File mode:     $FILE_MODE"
log " Log file:      $LOG_FILE"
log " Dry run:       $DRY_RUN"
log "========================================================"

# ---------------------------------------------------------------------------- #
# Validate datasets root
# ---------------------------------------------------------------------------- #
if [[ ! -d "$DATASETS_ROOT" ]]; then
  err "Datasets root '$DATASETS_ROOT' does not exist or is not a directory."
  exit 1
fi

# ---------------------------------------------------------------------------- #
# Write CSV header
# ---------------------------------------------------------------------------- #
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "pod,dataset,status,start_time,end_time,duration_seconds" > "$SUMMARY_FILE"
fi

# ---------------------------------------------------------------------------- #
# Discover datasets (top-level subdirectories only)
# ---------------------------------------------------------------------------- #
mapfile -t DATASETS < <(find "$DATASETS_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ ${#DATASETS[@]} -eq 0 ]]; then
  warn "No dataset directories found under '$DATASETS_ROOT'. Exiting."
  exit 0
fi

log "Found ${#DATASETS[@]} dataset(s) to process."
echo ""

# ---------------------------------------------------------------------------- #
# STATS
# ---------------------------------------------------------------------------- #
TOTAL=0
PASSED=0
FAILED=0
declare -a FAILED_DATASETS=()

# ---------------------------------------------------------------------------- #
# Process each dataset SERIALLY (key OOM fix — no parallelism)
# ---------------------------------------------------------------------------- #
for DATASET_PATH in "${DATASETS[@]}"; do
  DATASET_NAME=$(basename "$DATASET_PATH")
  TOTAL=$((TOTAL + 1))
  DATASET_STATUS="SUCCESS"

  echo ""
  log "${BOLD}──────────────────────────────────────────────${RESET}"
  log "${BOLD}Dataset [${TOTAL}/${#DATASETS[@]}]: ${DATASET_NAME}${RESET}"
  log "  Path:  $DATASET_PATH"

  START_TS=$(date +%s)
  START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
  log "  Start: $START_HUMAN"

  # ── chown ────────────────────────────────────────────────────────────────
  log "  → chown $OWNER (directories + files via find)"
  if [[ "$DRY_RUN" == true ]]; then
    dryrun "find '$DATASET_PATH' -exec chown $OWNER {} +"
  else
    # Use find + chown in batches to avoid OOM from building huge arg lists
    # -exec ... + batches args automatically (like xargs but safer)
    if ! find "$DATASET_PATH" -exec chown "$OWNER" {} +; then
      err "  chown failed for $DATASET_NAME"
      DATASET_STATUS="FAILED_CHOWN"
    fi
  fi

  # ── chmod directories ─────────────────────────────────────────────────────
  if [[ "$DATASET_STATUS" == "SUCCESS" ]]; then
    log "  → chmod $DIR_MODE (directories only)"
    if [[ "$DRY_RUN" == true ]]; then
      dryrun "find '$DATASET_PATH' -type d -exec chmod $DIR_MODE {} +"
    else
      if ! find "$DATASET_PATH" -type d -exec chmod "$DIR_MODE" {} +; then
        err "  chmod dirs failed for $DATASET_NAME"
        DATASET_STATUS="FAILED_CHMOD_DIR"
      fi
    fi
  fi

  # ── chmod files ───────────────────────────────────────────────────────────
  if [[ "$DATASET_STATUS" == "SUCCESS" ]]; then
    log "  → chmod $FILE_MODE (files only)"
    if [[ "$DRY_RUN" == true ]]; then
      dryrun "find '$DATASET_PATH' -type f -exec chmod $FILE_MODE {} +"
    else
      if ! find "$DATASET_PATH" -type f -exec chmod "$FILE_MODE" {} +; then
        err "  chmod files failed for $DATASET_NAME"
        DATASET_STATUS="FAILED_CHMOD_FILE"
      fi
    fi
  fi

  # ── Timing ────────────────────────────────────────────────────────────────
  END_TS=$(date +%s)
  END_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
  DURATION=$(( END_TS - START_TS ))

  log "  End:      $END_HUMAN"
  log "  Duration: ${DURATION}s"

  if [[ "$DATASET_STATUS" == "SUCCESS" ]]; then
    ok "  Status:   ✔ SUCCESS — $DATASET_NAME"
    PASSED=$((PASSED + 1))
  else
    err "  Status:   ✘ $DATASET_STATUS — $DATASET_NAME"
    FAILED=$((FAILED + 1))
    FAILED_DATASETS+=("$DATASET_NAME ($DATASET_STATUS)")
  fi

  # ── Append to CSV summary ─────────────────────────────────────────────────
  echo "${POD_NAME},${DATASET_PATH},${DATASET_STATUS},${START_HUMAN},${END_HUMAN},${DURATION}" >> "$SUMMARY_FILE"

done

# ---------------------------------------------------------------------------- #
# Final summary
# ---------------------------------------------------------------------------- #
echo ""
log "========================================================"
log " ${BOLD}SUMMARY — $POD_NAME${RESET}"
log " Total:   $TOTAL"
log " ${GREEN}Passed:  $PASSED${RESET}"
log " ${RED}Failed:  $FAILED${RESET}"

if [[ ${#FAILED_DATASETS[@]} -gt 0 ]]; then
  log " Failed datasets:"
  for fd in "${FAILED_DATASETS[@]}"; do
    log "   - $fd"
  done
fi

log " Log:     $LOG_FILE"
log " Summary: $SUMMARY_FILE"
log "========================================================"

[[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
