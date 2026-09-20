#!/usr/bin/env bash
set -euo pipefail
umask 077
backup_dir=${1:?Specify the exact backup directory}
case "$(realpath "$backup_dir")" in
  /srv/elmourdy/backups/folders-preflight-*) ;;
  *) echo 'Unexpected backup location' >&2; exit 1 ;;
esac
cd "$backup_dir"
sha256sum --check SHA256SUMS >/dev/null
container="mourdy-restore-check-$(date -u +%Y%m%d%H%M%S)"
# No published ports, no application, no mail delivery and no cloud access.
docker run -d --name "$container" --network none --memory 1g \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
  -e MYSQL_DATABASE=el_mourdy_backend_production mysql:8.4 >/dev/null
trap 'docker stop "$container" >/dev/null; printf "Isolated restore retained in stopped container: %s\n" "$container"' EXIT
ready=false
for attempt in $(seq 1 60); do
  if docker exec "$container" mysql --protocol=TCP -h 127.0.0.1 -u root el_mourdy_backend_production -e 'SELECT 1' >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
test "$ready" = true
gzip -dc database.sql.gz | docker exec -i "$container" mysql -u root el_mourdy_backend_production
while read -r table expected; do
  case "$table" in *[!a-z_]*|'') exit 1;; esac
  actual=$(docker exec "$container" mysql -u root --batch --skip-column-names el_mourdy_backend_production -e "SELECT COUNT(*) FROM $table")
  printf '%s expected=%s restored=%s\n' "$table" "$expected" "$actual"
  test "$actual" = "$expected"
done < record-counts.txt
printf 'Restore verified at %s UTC\nContainer: %s\n' "$(date -u +%FT%T)" "$container" > restore-verification.txt
printf '%s\n' 'RESTORE VERIFIED: all recorded counts match.'
