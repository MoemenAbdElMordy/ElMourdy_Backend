#!/usr/bin/env bash
set -euo pipefail

cd /srv/elmourdy
set -a
source .env.production
set +a

backup_dir="/srv/elmourdy/backups"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

install -d -m 700 "$backup_dir"
docker compose --env-file .env.production -f compose.production.yml exec -T db \
  mysqldump --single-transaction --quick --lock-tables=false \
    -u root "-p${MYSQL_ROOT_PASSWORD}" el_mourdy_backend_production \
  | gzip -9 > "${backup_dir}/database-${timestamp}.sql.gz"

chmod 600 "${backup_dir}/database-${timestamp}.sql.gz"
find "$backup_dir" -type f -name "database-*.sql.gz" -mtime +7 -delete
