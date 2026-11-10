#!/bin/sh
set -eu

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

if [ -z "${RESTIC_REPOSITORY:-}" ]; then die "RESTIC_REPOSITORY is not set"; fi
if [ -z "${RESTIC_PASSWORD_FILE:-}" ] || [ ! -f "$RESTIC_PASSWORD_FILE" ]; then die "RESTIC_PASSWORD_FILE missing: ${RESTIC_PASSWORD_FILE:-unset}"; fi
if [ -z "${RCLONE_CONFIG:-}" ] || [ ! -f "$RCLONE_CONFIG" ]; then die "RCLONE_CONFIG missing: ${RCLONE_CONFIG:-unset}"; fi

restic_unlock() {
  restic unlock --remove-all >/dev/null 2>&1 || true
}
