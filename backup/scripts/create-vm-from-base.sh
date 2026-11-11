#!/bin/sh
# Erzeugt eine neue VM als Copy-on-Write-Overlay auf einem read-only
# Basis-Image (Golden Image) und registriert sie optional per virsh define.
# Läuft auf dem KVM/libvirt-Host.
#
#   BASE_IMAGE=/srv/images/ubuntu-base-v1.qcow2 VM_NAME=dns-vm \\
#   OVERLAY_SIZE=20G DATA_DISK_SIZE=50G XML_TEMPLATE=/srv/images/vm-template.xml \\
#   create-vm-from-base.sh
set -eu

BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE=/srv/images/ubuntu-base-vN.qcow2 erforderlich}
VM_NAME=${VM_NAME:?VM_NAME=<domain-name> erforderlich}
OVERLAY_DIR=${OVERLAY_DIR:-/srv/images/overlays}
OVERLAY_SIZE=${OVERLAY_SIZE:-20G}
DATA_DISK_SIZE=${DATA_DISK_SIZE:-}
XML_TEMPLATE=${XML_TEMPLATE:-}

[ -f "$BASE_IMAGE" ] || { echo "BASE_IMAGE nicht gefunden: $BASE_IMAGE" >&2; exit 1; }

mkdir -p "$OVERLAY_DIR"
overlay="$OVERLAY_DIR/$VM_NAME.qcow2"
[ -e "$overlay" ] && { echo "Overlay existiert bereits: $overlay" >&2; exit 1; }

echo "erstelle Overlay: $overlay (backing: $(basename "$BASE_IMAGE"), size $OVERLAY_SIZE)"
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$overlay" "$OVERLAY_SIZE"

data_disk=""
if [ -n "$DATA_DISK_SIZE" ]; then
  data_disk="$OVERLAY_DIR/$VM_NAME-data.qcow2"
  echo "erstelle Daten-Disk (kein Backing-File): $data_disk ($DATA_DISK_SIZE)"
  qemu-img create -f qcow2 "$data_disk" "$DATA_DISK_SIZE"
fi

if [ -n "$XML_TEMPLATE" ]; then
  [ -f "$XML_TEMPLATE" ] || { echo "XML_TEMPLATE nicht gefunden: $XML_TEMPLATE" >&2; exit 1; }
  xml="/tmp/$VM_NAME.xml"
  sed -e "s|__VM_NAME__|$VM_NAME|g" \
      -e "s|__OVERLAY__|$overlay|g" \
      -e "s|__DATA_DISK__|$data_disk|g" \
      "$XML_TEMPLATE" > "$xml"
  virsh define "$xml"
  rm -f "$xml"
  echo "VM '$VM_NAME' definiert. Start: virsh start $VM_NAME"
else
  echo "kein XML_TEMPLATE angegeben - VM manuell definieren, z.B.:"
  echo "  virt-install --name $VM_NAME --memory 2048 --vcpus 2 --import \\"
  echo "    --disk path=$overlay \\"
  [ -n "$data_disk" ] && echo "    --disk path=$data_disk \\"
  echo "    --network bridge=br0 --noautoconsole"
fi

qemu-img info "$overlay" | head -n 6
echo "fertig."
