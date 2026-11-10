#!/bin/sh
. /scripts/lib.sh

restic_unlock
log "forget + prune (daily=${KEEP_DAILY:-7} weekly=${KEEP_WEEKLY:-4} monthly=${KEEP_MONTHLY:-12} yearly=${KEEP_YEARLY:-3})"
restic forget \
  --keep-daily "${KEEP_DAILY:-7}" \
  --keep-weekly "${KEEP_WEEKLY:-4}" \
  --keep-monthly "${KEEP_MONTHLY:-12}" \
  --keep-yearly "${KEEP_YEARLY:-3}" \
  --prune
log "prune finished"
