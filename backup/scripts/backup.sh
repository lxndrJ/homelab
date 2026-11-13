#!/bin/sh
. /scripts/lib.sh

DUMPS=/data/staging/dumps
mkdir -p "$DUMPS"

restic_unlock

dump_db() {
  container=$1
  db_type=$2
  db_user=$3
  db_password=$4
  out=$5
  if [ -z "$container" ]; then
    log "no db container configured, skipping $out"
    return 0
  fi
  log "dumping database from container '$container' to $out"
  case "$db_type" in
    postgres)
      if [ -n "$db_password" ]; then
        docker exec -e PGPASSWORD="$db_password" "$container" pg_dumpall -U "$db_user" > "$out"
      else
        docker exec "$container" pg_dumpall -U "$db_user" > "$out"
      fi
      ;;
    mariadb)
      if [ -n "$db_password" ]; then
        docker exec -e MARIADB_PWD="$db_password" "$container" mariadb-dump -u "$db_user" --all-databases > "$out"
      else
        docker exec "$container" mariadb-dump -u "$db_user" --all-databases > "$out"
      fi
      ;;
    mysql)
      if [ -n "$db_password" ]; then
        docker exec -e MYSQL_PWD="$db_password" "$container" mysqldump -u "$db_user" --all-databases > "$out"
      else
        docker exec "$container" mysqldump -u "$db_user" --all-databases > "$out"
      fi
      ;;
    *)
      die "unknown db type '$db_type'"
      ;;
  esac
}

dump_db "${IMMICH_DB_CONTAINER:-}" "${IMMICH_DB_TYPE:-postgres}" "${IMMICH_DB_USER:-postgres}" "${IMMICH_DB_PASSWORD:-}" "$DUMPS/immich-postgres.sql"
dump_db "${NEXTCLOUD_DB_CONTAINER:-}" "${NEXTCLOUD_DB_TYPE:-mariadb}" "${NEXTCLOUD_DB_USER:-nextcloud}" "${NEXTCLOUD_DB_PASSWORD:-}" "$DUMPS/nextcloud-db.sql"

if [ -d /data/immich ]; then
  log "backing up immich"
  restic backup /data/immich --tag immich --exclude-file /config/excludes/global.txt --exclude-file /config/excludes/immich.txt
else
  log "skip immich (/data/immich not mounted)"
fi

if [ -d /data/nextcloud ]; then
  log "backing up nextcloud"
  restic backup /data/nextcloud /data/nextcloud-config --tag nextcloud --exclude-file /config/excludes/global.txt --exclude-file /config/excludes/nextcloud.txt
else
  log "skip nextcloud (/data/nextcloud not mounted)"
fi

if [ -d /data/vms ] && [ -n "$(ls -A /data/vms 2>/dev/null)" ]; then
  log "backing up vm dumps"
  restic backup /data/vms --tag vms --exclude-file /config/excludes/global.txt
else
  log "skip vms (/data/vms empty or not mounted)"
fi

if [ -d /data/vm-config ] && [ -n "$(ls -A /data/vm-config 2>/dev/null)" ]; then
  log "backing up vm config exports"
  for dir in /data/vm-config/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    restic backup "$dir" --tag "vm-config:$name" --exclude-file /config/excludes/global.txt
  done
else
  log "skip vm config exports (/data/vm-config empty or not mounted)"
fi

if ls "$DUMPS"/*.sql >/dev/null 2>&1; then
  log "backing up db dumps"
  restic backup "$DUMPS" --tag db
else
  log "skip db dumps (none created)"
fi

log "snapshots:"
restic snapshots --compact
log "backup finished"
