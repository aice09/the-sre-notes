#!/bin/bash

set -u

read -rp "Enter BUCKET NAME: " BUCKET
read -rp "Enter TICKET NUMBER: " TICKET

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
    echo "$1" | tee -a "${LOGFILE}"
}

log "========================================"
log "INPUT SUMMARY"
log "========================================"
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
    echo "Completed. Check log: ${LOGFILE}"
    exit 0
else
    echo "Delete command returned non-zero exit code. Check log: ${LOGFILE}"
    exit ${WAIT_RC}
fi