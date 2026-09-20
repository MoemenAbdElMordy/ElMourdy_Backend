#!/usr/bin/env bash
# Run on the production host before the folder migration. Never prunes old backups.
set -euo pipefail
umask 077

app_dir=/srv/elmourdy
backup_root=/srv/elmourdy/backups
test -f "$app_dir/.env.production"
test -f "$app_dir/compose.production.yml"
install -d -m 700 "$backup_root"
test "$(realpath "$backup_root")" = "$backup_root"
backup_dir=$(mktemp -d "$backup_root/folders-preflight-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
cd "$app_dir"
compose=(docker compose --env-file .env.production -f compose.production.yml)

# Password stays inside the database container's environment, not process arguments.
"${compose[@]}" exec -T db sh -c '
  MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump \
    --single-transaction --quick --lock-tables=false --hex-blob \
    --routines --triggers --events --no-tablespaces \
    -u root el_mourdy_backend_production
' | gzip -9 > "$backup_dir/database.sql.gz.partial"
gzip -t "$backup_dir/database.sql.gz.partial"
test -s "$backup_dir/database.sql.gz.partial"
mv "$backup_dir/database.sql.gz.partial" "$backup_dir/database.sql.gz"

# Store configuration privately, alongside (never inside) the source repository.
cp -- .env.production compose.production.yml "$backup_dir/"
"${compose[@]}" images > "$backup_dir/images.txt"
if git rev-parse --verify HEAD > "$backup_dir/backend-revision.txt" 2>/dev/null; then
  git archive --format=tar.gz -o "$backup_dir/backend-source.tar.gz" HEAD
fi
"${compose[@]}" exec -T db sh -c '
  MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -u root --batch --skip-column-names \
    el_mourdy_backend_production -e "
      SELECT '\''branches'\'', COUNT(*) FROM branches UNION ALL
      SELECT '\''chapters'\'', COUNT(*) FROM chapters UNION ALL
      SELECT '\''lessons'\'', COUNT(*) FROM lessons UNION ALL
      SELECT '\''lectures'\'', COUNT(*) FROM lectures UNION ALL
      SELECT '\''video_assets'\'', COUNT(*) FROM video_assets UNION ALL
      SELECT '\''lecture_watch_events'\'', COUNT(*) FROM lecture_watch_events UNION ALL
      SELECT '\''lecture_access_grants'\'', COUNT(*) FROM lecture_access_grants UNION ALL
      SELECT '\''lesson_access_grants'\'', COUNT(*) FROM lesson_access_grants UNION ALL
      SELECT '\''activation_codes'\'', COUNT(*) FROM activation_codes UNION ALL
      SELECT '\''exam_attempts'\'', COUNT(*) FROM exam_attempts;"
' > "$backup_dir/record-counts.txt"

(
  cd "$backup_dir"
  sha256sum database.sql.gz .env.production compose.production.yml record-counts.txt > SHA256SUMS
  sha256sum --check SHA256SUMS >/dev/null
)
printf 'Archive created: %s\n' "$backup_dir"
printf '%s\n' 'NOT RESTORE-VERIFIED: restore into an isolated database before approving migration.'
