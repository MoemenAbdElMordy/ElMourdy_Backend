#!/usr/bin/env bash
set -euo pipefail
umask 077
base_archive=${1:?Base source archive required}
overlay_archive=${2:?Overlay archive required}
backup_dir=${3:?Backup directory required}
port=${4:-38080}
case "$port" in
  *[!0-9]*|'') echo 'Port must be numeric' >&2; exit 2 ;;
esac
if (echo >"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1; then
  echo "Staging port $port is already in use" >&2
  exit 2
fi
stamp=$(date -u +%Y%m%d%H%M%S)
work=$(mktemp -d "/tmp/mourdy-folder-staging-$stamp-XXXXXX")
network="mourdy-folder-staging-net-$stamp"
db="mourdy-folder-staging-db-$stamp"
app="mourdy-folder-staging-app-$stamp"
image="mourdy-folder-staging:$stamp"
tar -xzf "$base_archive" -C "$work"
tar -xzf "$overlay_archive" -C "$work"
docker build -t "$image" "$work"
docker network create "$network" >/dev/null
docker run -d --name "$db" --network "$network" --memory 1g \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -e MYSQL_DATABASE=el_mourdy_backend_production mysql:8.4 >/dev/null
ready=false
for attempt in $(seq 1 60); do
  if docker exec "$db" mysql --protocol=TCP -h 127.0.0.1 -u root el_mourdy_backend_production -e 'SELECT 1' >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
test "$ready" = true
gzip -dc "$backup_dir/database.sql.gz" | docker exec -i "$db" mysql -u root el_mourdy_backend_production
common=(--network "$network" -e RAILS_ENV=production
  -e DATABASE_URL=mysql2://root@"$db"/el_mourdy_backend_production
  -e VIDEO_STORAGE_SERVICE=local -e SECURITY_PEPPER=isolated-staging-only
  -e SECRET_KEY_BASE=isolated-staging-key-not-for-production
  -e SMTP_USERNAME=disabled@example.invalid -e SMTP_PASSWORD=disabled
  -e APPLICATION_HOST=localhost -e FRONTEND_ORIGIN=http://127.0.0.1:5190)
docker run --rm "${common[@]}" "$image" bundle exec rails db:migrate
docker run --rm "${common[@]}" "$image" bundle exec rails curriculum:backfill_folders
docker run -d --name "$app" "${common[@]}" -p "127.0.0.1:$port:80" "$image" ./bin/rails server -b 0.0.0.0 -p 80 >/dev/null
for attempt in $(seq 1 60); do
  if curl -fsS -H 'Host: localhost' "http://127.0.0.1:$port/up" >/dev/null; then
    printf 'STAGING READY app=%s db=%s network=%s image=%s work=%s\n' "$app" "$db" "$network" "$image" "$work"
    exit 0
  fi
  sleep 1
done
docker logs --tail 80 "$app" >&2
exit 1
