#!/bin/sh
. /scripts/lib.sh

SNAP=${1:-latest}
TARGET=${2:-/restore}
INCLUDE=${3:-}

mkdir -p "$TARGET"
log "restoring snapshot '$SNAP' to $TARGET${INCLUDE:+ (include: $INCLUDE)}"
if [ -n "$INCLUDE" ]; then
  restic restore "$SNAP" --target "$TARGET" --include "$INCLUDE"
else
  restic restore "$SNAP" --target "$TARGET"
fi
log "restore finished -> $TARGET"
