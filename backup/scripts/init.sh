#!/bin/sh
. /scripts/lib.sh

remote=${RCLONE_REMOTE:-gdrive}
log "checking rclone remote '$remote'"
rclone lsd "$remote:" --max-depth 1 >/dev/null || die "rclone remote '$remote' not reachable (check config/rclone.conf and token)"

if restic snapshots >/dev/null 2>&1; then
  log "restic repository already initialized"
else
  log "initializing restic repository at $RESTIC_REPOSITORY"
  restic init
fi

restic snapshots --compact || true
log "init OK"
