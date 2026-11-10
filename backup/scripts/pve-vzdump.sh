#!/bin/sh
# Runs on the Proxmox VE host (not inside the backup container).
# Creates vzdump archives in DUMP_DIR, which the backup container mounts as /data/vms.
set -eu

DUMP_DIR=${DUMP_DIR:-/srv/vzdump}
VMIDS=${VMIDS:-}
MODE=${MODE:-snapshot}
STORAGE=${STORAGE:-}

mkdir -p "$DUMP_DIR"

dump_one() {
  vmid=$1
  echo "vzdump $vmid (mode=$MODE)"
  if [ -n "$STORAGE" ]; then
    vzdump "$vmid" --mode "$MODE" --dumpdir "$DUMP_DIR" --storage "$STORAGE" --remove 1
  else
    vzdump "$vmid" --mode "$MODE" --dumpdir "$DUMP_DIR" --remove 1
  fi
}

if [ -n "$VMIDS" ]; then
  for vmid in $VMIDS; do
    dump_one "$vmid"
  done
else
  for vmid in $(qm list | awk 'NR>1 {print $1}'); do
    dump_one "$vmid"
  done
fi
