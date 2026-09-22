#!/usr/bin/env bash
set -euo pipefail
umask 077

archive=${1:?Source archive required}
backup=${2:?Verified backup directory required}
image=${3:?Tested image tag required}
app_dir=/srv/elmourdy
case "$(realpath "$backup")" in
  "$app_dir"/backups/folders-preflight-*) ;;
  *) echo 'Backup must be inside the production backup directory' >&2; exit 2 ;;
esac
test -s "$backup/database.sql.gz"
test -s "$backup/backend-source-before.tar.gz"
gzip -t "$backup/database.sql.gz"
tar -tzf "$backup/backend-source-before.tar.gz" >/dev/null
tar -tzf "$archive" >/dev/null
docker image inspect "$image" >/dev/null

cd "$app_dir"
compose=(docker compose --env-file .env.production -f compose.production.yml)
old_image=$(docker image inspect elmourdy-app:latest --format '{{.Id}}')
rollback_tag="elmourdy-app:pre-folders-$(date -u +%Y%m%d%H%M%S)"
docker tag "$old_image" "$rollback_tag"
printf 'Previous app image retained as %s\n' "$rollback_tag"

# The schema change only adds a table. The running old app remains in service
# until migration, backfill and integrity checks finish.
tar -xzf "$archive" -C "$app_dir"
docker tag "$image" elmourdy-app:latest
"${compose[@]}" run --rm --no-deps app bundle exec rails db:migrate
"${compose[@]}" run --rm --no-deps app bundle exec rails curriculum:backfill_folders
"${compose[@]}" run --rm --no-deps app bundle exec rails runner '
  placements = CurriculumNode.where(kind: "lecture")
  abort "Unmapped lectures" unless Lecture.where.not(id: placements.select(:lecture_id)).count.zero?
  abort "Orphan lecture nodes" unless placements.where(lecture_id: nil).count.zero?
  puts "Integrity: lectures=#{Lecture.count}, placements=#{placements.count}, watches=#{LectureWatchEvent.count}"
'

"${compose[@]}" up -d --no-deps --force-recreate --no-build app
healthy=false
for attempt in $(seq 1 30); do
  if curl -fsS --max-time 5 --resolve api.mourdy.com:443:127.0.0.1 \
      https://api.mourdy.com/up >/dev/null; then healthy=true; break; fi
  sleep 2
done
if [ "$healthy" != true ]; then
  echo 'New app failed health check; restoring previous image' >&2
  docker tag "$rollback_tag" elmourdy-app:latest
  "${compose[@]}" up -d --no-deps --force-recreate --no-build app
  exit 1
fi
printf 'BACKEND DEPLOYED: image=%s rollback=%s backup=%s\n' "$image" "$rollback_tag" "$backup"
