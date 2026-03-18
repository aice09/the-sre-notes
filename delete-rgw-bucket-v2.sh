#!/bin/bash

set -u

SILENT=0
DETACHED=0
BUCKET=""
TICKET=""

usage() {
    cat <<EOF
Usage:
  $0 [--bucket BUCKET_NAME] [--ticket TICKET_NUMBER] [--silent]

Options:
  --bucket   Bucket name to delete
  --ticket   Ticket number for log filename
  --silent   Run the whole job in background, logs still go to delete-<ticket>.log
  -h, --help Show this help

Examples:
  $0
  $0 --bucket mybucket --ticket ONEDI-12345
  $0 --bucket mybucket --ticket ONEDI-12345 --silent
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bucket)
            [[ $# -lt 2 ]] && { echo "ERROR: --bucket requires a value"; exit 1; }
            BUCKET="$2"
            shift 2
            ;;
        --ticket)
            [[ $# -lt 2 ]] && { echo "ERROR: --ticket requires a value"; exit 1; }
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

touch "${LOGFILE}" || {
    echo "ERROR: Cannot create log file ${LOGFILE}"
    exit 1
}

log() {
    if [[ "${DETACHED}" -eq 1 ]]; then
        echo "$1" >> "${LOGFILE}"
    else
        echo "$1" | tee -a "${LOGFILE}"
    fi
}

# If --silent is used, re-run the script in the background after inputs are known.
if [[ "${SILENT}" -eq 1 && "${DETACHED}" -eq 0 ]]; then
    nohup "$0" --bucket "${BUCKET}" --ticket "${TICKET}" --detached >/dev/null 2>&1 &
    BG_PID=$!

    echo "Job started in background."
    echo "PID: ${BG_PID}"
    echo "Log file: ${LOGFILE}"

    {
        echo "========================================"
        echo "INPUT SUMMARY"
        echo "========================================"
        echo "Date: $(date)"
        echo "Bucket: ${BUCKET}"
        echo "Ticket: ${TICKET}"
        echo "Log File: ${LOGFILE}"
        echo "Silent Mode: YES"
        echo "Background PID: ${BG_PID}"
        echo ""
    } >> "${LOGFILE}"

    exit 0
fi

log "========================================"
log "INPUT SUMMARY"
log "========================================"
log "Date: $(date)"
log "Bucket: ${BUCKET}"
log "Ticket: ${TICKET}"
log "Log File: ${LOGFILE}"
if [[ "${SILENT}" -eq 1 || "${DETACHED}" -eq 1 ]]; then
    log "Silent Mode: YES"
else
    log "Silent Mode: NO"
fi
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
