#!/bin/bash

set -u

BUCKET=""
TICKET=""
SILENT=0
DETACHED=0
RUN_ID=""

usage() {
    cat <<EOF
Usage:
  $0 [--bucket BUCKET_NAME] [--ticket TICKET_NUMBER] [--silent]

Options:
  --bucket   Bucket name
  --ticket   Ticket number
  --silent   Run the script in background
  -h, --help Show this help

Examples:
  $0
  $0 --bucket mybucket --ticket ONEDI-12345
  $0 --bucket mybucket --ticket ONEDI-12345 --silent
  $0 --silent
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bucket)
            [[ $# -lt 2 ]] && { echo "ERROR: --bucket requires a value."; exit 1; }
            BUCKET="$2"
            shift 2
            ;;
        --ticket)
            [[ $# -lt 2 ]] && { echo "ERROR: --ticket requires a value."; exit 1; }
            TICKET="$2"
            shift 2
            ;;
        --silent)
            SILENT=1
            shift
            ;;
        --detached)
            DETACHED=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${BUCKET}" ]]; then
    read -rp "Enter BUCKET NAME: " BUCKET
fi

if [[ -z "${TICKET}" ]]; then
    read -rp "Enter TICKET NUMBER: " TICKET
fi

if [[ -z "${BUCKET}" || -z "${TICKET}" ]]; then
    echo "ERROR: Bucket name and ticket number are required."
    exit 1
fi

LOGFILE="delete-${TICKET}.log"

# If --silent is requested, detach BEFORE any logging.
# Only the detached child should write the operational log.
if [[ "${SILENT}" -eq 1 && "${DETACHED}" -eq 0 ]]; then
    nohup "$0" --bucket "${BUCKET}" --ticket "${TICKET}" --detached >/dev/null 2>&1 &
    BG_PID=$!
    echo "Job started in background."
    echo "PID: ${BG_PID}"
    echo "Log file: ${LOGFILE}"
    exit 0
fi

# Fresh log file for each run
: > "${LOGFILE}" || {
    echo "ERROR: Cannot create log file ${LOGFILE}"
    exit 1
}

RUN_ID=$(date +"%Y%m%d-%H%M%S")

log() {
    if [[ "${DETACHED}" -eq 1 ]]; then
        echo "$1" >> "${LOGFILE}"
    else
        echo "$1" | tee -a "${LOGFILE}"
    fi
}

log "========================================"
log "INPUT SUMMARY"
log "========================================"
log "Run ID: ${RUN_ID}"
log "Date: $(date)"
log "Bucket: ${BUCKET}"
log "Ticket: ${TICKET}"
log "Log File: ${LOGFILE}"
log ""

log "========================================"
log "CHECKING OBJECT COUNT"
log "========================================"

BUCKET_STATS_OUTPUT="$(radosgw-admin bucket stats --bucket="${BUCKET}" 2>&1)"
RC=$?

echo "${BUCKET_STATS_OUTPUT}" >> "${LOGFILE}"

if [[ ${RC} -ne 0 ]]; then
    log "ERROR: Failed to get bucket stats. See radosgw-admin output above."
    exit 1
fi

OBJ_COUNT="$(echo "${BUCKET_STATS_OUTPUT}" | awk -F: '/"num_objects"/ {gsub(/[ ,]/,"",$2); print $2; exit}')"

if [[ -z "${OBJ_COUNT}" ]]; then
    log "WARNING: Unable to parse object count from bucket stats."
else
    log "Object Count: ${OBJ_COUNT}"
fi

log ""
log "========================================"
log "DELETE ACTION"
log "========================================"
log "Starting delete in background with wait..."
log "Command: radosgw-admin bucket rm --bucket=\"${BUCKET}\" --purge-objects"
log "Start Time: $(date)"

{
    echo "----- DELETE COMMAND OUTPUT START: $(date) -----"
    radosgw-admin bucket rm --bucket="${BUCKET}" --purge-objects
    DELETE_RC=$?
    echo "----- DELETE COMMAND OUTPUT END: $(date) -----"
    echo "Delete Exit Code: ${DELETE_RC}"
    exit ${DELETE_RC}
} >> "${LOGFILE}" 2>&1 &

DELETE_PID=$!
log "Delete PID: ${DELETE_PID}"
log "Waiting for delete process to complete..."

wait "${DELETE_PID}"
WAIT_RC=$?

log "Delete process finished."
log "Delete Wait Exit Code: ${WAIT_RC}"
log "End Time: $(date)"
log ""

log "========================================"
log "POST CHECK"
log "========================================"

POST_CHECK_OUTPUT="$(radosgw-admin bucket stats --bucket="${BUCKET}" 2>&1)"
POST_RC=$?

echo "${POST_CHECK_OUTPUT}" >> "${LOGFILE}"

if [[ ${POST_RC} -eq 0 ]]; then
    log "POST CHECK RESULT: Bucket still exists."
else
    log "POST CHECK RESULT: Bucket no longer exists or bucket stats failed."
fi

log ""
log "========================================"
log "DONE"
log "========================================"

if [[ ${WAIT_RC} -eq 0 ]]; then
    if [[ "${DETACHED}" -eq 0 ]]; then
        echo "Completed. Check log: ${LOGFILE}"
    fi
    exit 0
else
    if [[ "${DETACHED}" -eq 0 ]]; then
        echo "Delete command returned non-zero exit code. Check log: ${LOGFILE}"
    fi
    exit "${WAIT_RC}"
fi