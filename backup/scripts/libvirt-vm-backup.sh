#!/bin/sh
# Runs on the KVM/libvirt host (not inside the backup container).
# Exports VM definitions (virsh dumpxml), storage pools, UEFI NVRAM files and
# /etc/libvirt/qemu to CONF_DIR. Optionally (DUMP_IMAGES=yes) creates qcow2
# images of STOPPED VMs in DUMP_DIR. Both directories are picked up by the
# backup container (VM_CONFIG_DIR / VM_BACKUP_DIR).
set -eu

CONF_DIR=${CONF_DIR:-/srv/vm-backups/libvirt-config}
DUMP_DIR=${DUMP_DIR:-/srv/vzdump}
DUMP_IMAGES=${DUMP_IMAGES:-no}
DOMAINS=${DOMAINS:-}

mkdir -p "$CONF_DIR/pools" "$CONF_DIR/nvram" "$DUMP_DIR"

export_domain() {
  d=$1
  echo "exporting domain xml: $d"
  virsh dumpxml "$d" > "$CONF_DIR/$d.xml"

  # UEFI-NVRAM mit sichern (Pfad steht im <nvram>-Element)
  line=$(grep -o "<nvram[^<]*</nvram>" "$CONF_DIR/$d.xml" || true)
  if [ -n "$line" ]; then
    nvram=${line#*>}
    nvram=${nvram%</nvram>}
    if [ -f "$nvram" ]; then
      cp "$nvram" "$CONF_DIR/nvram/$(basename "$nvram")"
    fi
  fi
}

if [ -n "$DOMAINS" ]; then
  for d in $DOMAINS; do
    export_domain "$d"
  done
else
  for d in $(virsh list --all --name); do
    export_domain "$d"
  done
fi

for p in $(virsh pool-list --name 2>/dev/null); do
  virsh pool-dumpxml "$p" > "$CONF_DIR/pools/$p.xml"
done

cp -a /etc/libvirt/qemu "$CONF_DIR/etc-libvirt-qemu" 2>/dev/null || true

if [ "$DUMP_IMAGES" = "yes" ]; then
  for d in $(virsh list --all --name); do
    state=$(virsh domstate "$d")
    if [ "$state" = "shut off" ]; then
      echo "dumping images of stopped vm: $d"
      for disk in $(virsh domblklist "$d" --name | grep -v "^-"); do
        [ -f "$disk" ] || continue
        qemu-img convert -O qcow2 "$disk" "$DUMP_DIR/${d}-$(basename "$disk").qcow2"
      done
    else
      echo "skip $d (running: shutdown oder 'virsh backup-begin' verwenden)"
    fi
  done
fi

echo "libvirt export finished"
