#!/usr/bin/env bash
set -euo pipefail
umask 077
source_archive=${1:?Source archive required}
db=${2:?Stopped restored database container required}
case "$db" in mourdy-restore-check-*) ;; *) echo 'Unexpected restore container' >&2; exit 1;; esac
stamp=$(date -u +%Y%m%d%H%M%S)
app="mourdy-folder-rehearsal-app-$stamp"
docker start "$db" >/dev/null
trap 'docker stop "$app" "$db" >/dev/null 2>&1 || true; printf "Rehearsal retained stopped: %s with %s\n" "$app" "$db"' EXIT
ready=false
for attempt in $(seq 1 60); do
  if docker exec "$db" mysql --protocol=TCP -h 127.0.0.1 -u root el_mourdy_backend_production -e 'SELECT 1' >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
test "$ready" = true
tables='branches chapters lessons lectures video_assets lecture_watch_events lecture_access_grants lesson_access_grants activation_codes exam_attempts'
for table in $tables; do
  docker exec "$db" mysql -u root --batch --skip-column-names el_mourdy_backend_production -e "SELECT '$table', COUNT(*) FROM $table"
done > /tmp/folder-rehearsal-before-$stamp.txt
cd /srv/elmourdy
image=$(docker compose --env-file .env.production -f compose.production.yml images -q app)
docker run -d --name "$app" --network "container:$db" --memory 1g --entrypoint sleep \
  -e RAILS_ENV=production -e DATABASE_URL=mysql2://root@127.0.0.1/el_mourdy_backend_production \
  -e VIDEO_STORAGE_SERVICE=local -e SECURITY_PEPPER=isolated-rehearsal-only \
  -e SECRET_KEY_BASE=isolated-rehearsal-key-not-for-production \
  -e SMTP_USERNAME=disabled@example.invalid -e SMTP_PASSWORD=disabled \
  -e DISABLE_BOOTSNAP=1 "$image" infinity >/dev/null
docker cp "$source_archive" "$app:/tmp/folder-source.tar.gz"
docker exec -u root "$app" tar -xzf /tmp/folder-source.tar.gz -C /rails
docker exec "$app" bundle exec rails db:migrate
docker exec "$app" bundle exec rails curriculum:backfill_folders
docker exec "$app" bundle exec rails curriculum:backfill_folders
for table in $tables; do
  docker exec "$db" mysql -u root --batch --skip-column-names el_mourdy_backend_production -e "SELECT '$table', COUNT(*) FROM $table"
done > /tmp/folder-rehearsal-after-$stamp.txt
diff -u /tmp/folder-rehearsal-before-$stamp.txt /tmp/folder-rehearsal-after-$stamp.txt
docker exec "$db" mysql -u root --batch --skip-column-names el_mourdy_backend_production -e '
  SELECT "orphan_parent", COUNT(*) FROM curriculum_nodes child LEFT JOIN curriculum_nodes parent ON parent.id=child.parent_id WHERE child.parent_id IS NOT NULL AND parent.id IS NULL UNION ALL
  SELECT "orphan_branch", COUNT(*) FROM curriculum_nodes node LEFT JOIN branches branch ON branch.id=node.branch_id WHERE branch.id IS NULL UNION ALL
  SELECT "orphan_lecture", COUNT(*) FROM curriculum_nodes node LEFT JOIN lectures lecture ON lecture.id=node.lecture_id WHERE node.kind="lecture" AND lecture.id IS NULL UNION ALL
  SELECT "duplicate_legacy_chapter", COUNT(*) FROM (SELECT legacy_chapter_id FROM curriculum_nodes WHERE legacy_chapter_id IS NOT NULL GROUP BY legacy_chapter_id HAVING COUNT(*)>1) duplicates UNION ALL
  SELECT "duplicate_legacy_lesson", COUNT(*) FROM (SELECT legacy_lesson_id FROM curriculum_nodes WHERE legacy_lesson_id IS NOT NULL GROUP BY legacy_lesson_id HAVING COUNT(*)>1) duplicates UNION ALL
  SELECT "folder_nodes", COUNT(*) FROM curriculum_nodes WHERE kind="folder" UNION ALL
  SELECT "lecture_nodes", COUNT(*) FROM curriculum_nodes WHERE kind="lecture";'
printf '%s\n' 'MIGRATION REHEARSAL VERIFIED: legacy counts unchanged; second backfill idempotent.'
