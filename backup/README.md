# Backup-Stack (restic → Google Drive, clientseitig verschlüsselt)

Sichert **Immich**, **Nextcloud** (Daten + Config + Datenbank), **VM-Dumps** (KVM/libvirt) und **VM-Config-Exporte** (Ansible, siehe `ansible/`) verschlüsselt nach **Google Drive**.

## Architektur

```
libvirt-Host ──qemu-img/virsh──▶ /srv/vzdump ─┐
/srv/immich ──────────────────────────┤
/srv/nextcloud ───────────────────────┼─▶ restic (AES-256, clientseitig) ─▶ rclone ─▶ Google Drive
DB-Container ──pg_dumpall/mysqldump──▶ /srv/backup-staging ─┘
VMs ──Ansible-Export──▶ /srv/vm-backups ─┘
```

- **restic** verschlüsselt und dedupliziert **vor dem Upload** (AES-256 + Poly1305). In Google Drive liegen nur verschlüsselte, nicht lesbare Chunks — Google (oder jemand mit Zugriff auf den Drive) sieht keine Klartextdaten.
- **rclone** ist nur das Transport-Backend (`rclone:gdrive:...`).
- Snapshots werden pro Quelle getaggt: `immich`, `nextcloud`, `vms`, `vm-config:<name>`, `db`.

## Voraussetzungen

- Docker + Docker Compose auf dem Host
- `rclone` lokal (einmalig, nur für die Ersteinrichtung des Google-Drive-Tokens)
- Ein Google-Konto

## Ersteinrichtung

```bash
cd backup
cp .env.example .env
# .env anpassen: Pfade, DB-Container, Retention

# restic-Passwort erzeugen (WICHTIG: im Passwort-Manager sichern!)
openssl rand -base64 32 > config/restic-password
chmod 600 config/restic-password

# rclone-Remote "gdrive" anlegen und config/rclone.conf erzeugen
rclone config          # -> new remote "gdrive" -> Google Drive -> scope: drive.file
# Headless-Host ohne Browser: lokal "rclone authorize \\"gdrive\\" \\"<code>\\\"" ausführen
# und die Ausgabe nach config/rclone.conf kopieren
chmod 600 config/rclone.conf

docker compose build
docker compose run --rm backup /scripts/init.sh
```

**`scope = drive.file` verwenden** (statt `drive`): Der Token kann dann nur Dateien sehen/ändern, die rclone selbst angelegt hat — nicht den Rest deines Drives.

**Sicherheit:** `.env`, `config/rclone.conf` und `config/restic-password` sind via `.gitignore` geschützt und dürfen **niemals committed** werden. Ohne das restic-Passwort ist ein Restore unmöglich — Passwort im Passwort-Manager ablegen und getrennt vom Repo aufbewahren.

Hinweis: Der Container mountet `/var/run/docker.sock`, damit er per `docker exec` die DB-Dumps aus den Immich-/Nextcloud-DB-Containern ziehen kann. Auf einem dedizierten Backup-Host ist das üblich; alternativ die Dumps hostseitig erzeugen und nur `STAGING_DIR` mounten.

## Betrieb

```bash
cd backup

# Backup ausführen
docker compose run --rm backup /scripts/backup.sh

# Snapshots anzeigen
docker compose run --rm backup /scripts/list.sh

# Alte Snapshots aufräumen + Repository prüfen (Retention aus .env)
docker compose run --rm backup /scripts/prune.sh
docker compose run --rm backup /scripts/check.sh
```

### Automatisierung (systemd, auf dem Docker-Host)

```bash
sudo cp backup/systemd/homelab-backup*.{service,timer} /etc/systemd/system/
sudo sed -i 's|/srv/homelab/backup|/PFAD/ZU/homelab/backup|' /etc/systemd/system/homelab-backup*.service
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-backup.timer homelab-backup-maintenance.timer
```

- `homelab-backup.timer`: täglich 03:00 Uhr Backup
- `homelab-backup-maintenance.timer`: sonntags 04:00 Uhr prune + check

Cron-Alternative: `0 3 * * * cd /srv/homelab/backup && docker compose run --rm backup /scripts/backup.sh`

### VM-Config-Export (Ansible)

Der Ordner `ansible/` enthält ein Playbook, das **vor dem Backup-Lauf** (systemd: 02:30 Uhr) per SSH die Konfiguration aller VMs einsammelt und nach `/srv/vm-backups/ansible/<vm>` exportiert. Der Backup-Container nimmt das Verzeichnis als `/data/vm-config` mit auf und sichert es mit Tags `vm-config:<name>`. Siehe `ansible/README.md`.

### VMs (KVM/libvirt)

`scripts/libvirt-vm-backup.sh` läuft **auf dem libvirt-Host** und exportiert:

- Domain-XMLs (`virsh dumpxml`) aller VMs nach `CONF_DIR` (Standard: `/srv/vm-backups/libvirt-config`, wird über `VM_CONFIG_DIR` mitgesichert)
- Storage-Pool-XMLs, UEFI-NVRAM-Dateien und `/etc/libvirt/qemu`
- optional mit `DUMP_IMAGES=yes`: qcow2-Images **gestoppter** VMs nach `VM_BACKUP_DIR` (`qemu-img convert`)

```bash
# /etc/cron.d/libvirt-vm-backup  (auf dem KVM-Host, vor dem Backup-Lauf)
0 2 * * * root CONF_DIR=/srv/vm-backups/libvirt-config DUMP_DIR=/srv/vzdump DUMP_IMAGES=no /srv/homelab/backup/scripts/libvirt-vm-backup.sh >> /var/log/libvirt-vm-backup.log 2>&1
```

- `DOMAINS` leer = alle VMs; sonst Liste von Domain-Namen.
- Laufende VMs werden beim Image-Dump übersprungen (Shutdown oder `virsh backup-begin` für Live-Backups nutzen).
- Restore einer VM-Definition: `virsh define <vm>.xml`; Disk-Image zurückkopieren und in der XML auf den Pfad zeigen lassen.

## Golden-Image-VMs (qcow2-Overlays)

Tier-1/Tier-2-VMs können statt eigener Voll-Disks ein **Overlay (Copy-on-Write) auf einem read-only Basis-Image** nutzen:

```
/srv/images/ubuntu-base-v1.qcow2     (read-only, versioniert, liegt im restic-Backup)
   ├── overlays/dns-vm.qcow2          (backing_file=base, nur Deltas)
   └── overlays/docker-vm.qcow2       (OS-Overlay; Daten auf separater Disk ohne Backing-File!)
```

### Neue VM vom Basis-Image

```bash
BASE_IMAGE=/srv/images/ubuntu-base-v1.qcow2 VM_NAME=dns-vm OVERLAY_SIZE=20G \
  /srv/homelab/backup/scripts/create-vm-from-base.sh
```

- Erzeugt `overlays/<VM_NAME>.qcow2` (`qemu-img create -b <base>`) und optional eine separate Daten-Disk (`DATA_DISK_SIZE=50G`).
- Mit `XML_TEMPLATE=/srv/images/vm-template.xml` wird die VM direkt per `virsh define` registriert (Platzhalter: `__VM_NAME__`, `__OVERLAY__`, `__DATA_DISK__`).

### Pflege-Regeln

1. **Basis-Image nie verändern.** Updates = neue Datei (`ubuntu-base-v2.qcow2`), alte Version behalten; Basis-Images liegen mit im Backup.
2. **Umstellen auf neue Basis:** `qemu-img rebase -b /srv/images/ubuntu-base-v2.qcow2 overlays/<vm>.qcow2` (VM vorher stoppen).
3. **Maximal 2 Ebenen** (Basis + Overlay). Keine Overlays auf Overlays - die Backing-Chains werden sonst unübersichtlich.
4. **Anwendungsdaten immer auf einer separaten Disk** ohne Backing-File; im Overlay nur OS/Config. Dann bleibt das Overlay klein.
5. **Overlays aufräumen:** gelegentlich `virt-sparsify --in-place overlays/<vm>.qcow2` (VM gestoppt), sonst wachsen Logs/Caches das Overlay auf GB-Größe.

### Backup-Auswirkungen

- Basis-Image: einmal pro Version ins Backup (klein, dedupliziert gut).
- Pro VM: Overlay (meist MB-Bereich) + Daten-Disk-Inhalte via restic + Ansible-Config-Export.
- Für Overlay-basierte Tier-1-VMs ist `DUMP_IMAGES=yes` i. d. R. unnötig - Overlay + Config reichen zum Rebuild.

## Restore

```bash
cd backup

# komplette neueste Sicherung nach $RESTORE_DIR (hostseitig, siehe .env)
docker compose run --rm backup /scripts/restore.sh latest /restore

# nur Nextcloud aus einem bestimmten Snapshot
docker compose run --rm backup /scripts/list.sh        # ID kopieren
docker compose run --rm backup /scripts/restore.sh <SNAPSHOT-ID> /restore /data/nextcloud
```

Die Dateien liegen danach unter `$RESTORE_DIR/data/...` (restic stellt die vollständigen Pfade wieder her).

**Immich-Datenbank wiederherstellen:**

```bash
docker exec -i immich_postgres psql -U postgres < $RESTORE_DIR/data/staging/dumps/immich-postgres.sql
```

## Konfiguration

| Datei | Zweck |
|---|---|
| `.env` | Pfade, DB-Container, Retention (aus `.env.example` kopieren, gitignored) |
| `config/rclone.conf` | Google-Drive-Token (gitignored, nie committen) |
| `config/restic-password` | restic-Passwort (gitignored, im Passwort-Manager sichern!) |
| `config/excludes/*.txt` | restic-Exclude-Dateien pro Quelle |

## Hinweise

- Immich: `thumbs/` und `encoded-video/` werden ausgeschlossen (werden von Immich neu generiert). In `.env` `IMMICH_DATA` auf das gesamte `UPLOAD_LOCATION` zeigen lassen.
- Nextcloud: Datenverzeichnis + `config/` (enthält `config.php`) + DB-Dump werden gesichert.
- `scripts/check.sh` prüft 5 % der Datenpakete (`restic check --read-data-subset=5%`); für einen Vollcheck ohne Subset-Flag ausführen.
- Falls das Image-Build scheitert (`rclone` nicht im Alpine-Repo): statisches rclone-Binary von downloads.rclone.org im Dockerfile installieren.
- VM-Config-Exporte können Secrets enthalten (`.env`-Dateien, App-Configs mit Passwörtern). Der Export auf dem Host sollte mit `chmod 700`/`600` laufen; restic verschlüsselt clientseitig, aber der Staging-Bereich auf dem Host ist Klartext.
- Berechtigungen (uid/gid) bleiben beim Ansible-Export erhalten (`rsync -a` über `synchronize` als root). Beim Restore `tar --numeric-owner -p` bzw. `restic restore` als root verwenden.