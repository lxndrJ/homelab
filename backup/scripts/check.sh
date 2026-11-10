#!/bin/sh
. /scripts/lib.sh

restic_unlock
restic check --read-data-subset=5%
log "check finished"
