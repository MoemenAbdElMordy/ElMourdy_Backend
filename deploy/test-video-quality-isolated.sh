#!/usr/bin/env bash
set -euo pipefail
source_archive=${1:?Source archive required}
stamp=$(date -u +%Y%m%d%H%M%S)
db="mourdy-video-test-db-$stamp"
app="mourdy-video-test-app-$stamp"
cd /srv/elmourdy
image=$(docker compose --env-file .env.production -f compose.production.yml images -q app)
test -n "$image"
docker run -d --name "$db" --network none --memory 1g \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -e MYSQL_DATABASE=el_mourdy_backend_test mysql:8.4 >/dev/null
trap 'docker stop "$app" "$db" >/dev/null 2>&1 || true' EXIT
for attempt in $(seq 1 60); do
  if docker exec "$db" mysql --protocol=TCP -h 127.0.0.1 -u root el_mourdy_backend_test -e 'SELECT 1' >/dev/null 2>&1; then break; fi
  sleep 1
done
docker run -d --name "$app" --network "container:$db" --memory 2g --entrypoint sleep \
  -e RAILS_ENV=test -e DATABASE_URL=mysql2://root@127.0.0.1/el_mourdy_backend_test \
  -e VIDEO_STORAGE_SERVICE=local -e SECURITY_PEPPER=isolated-video-test-only \
  -e SECRET_KEY_BASE=isolated-video-test-key-not-for-production -e DISABLE_BOOTSNAP=1 \
  "$image" infinity >/dev/null
docker cp "$source_archive" "$app:/tmp/video-test-source.tar.gz"
docker exec -u root "$app" tar -xzf /tmp/video-test-source.tar.gz -C /rails
docker exec "$app" bundle exec rails db:schema:load db:migrate
docker exec "$app" bundle exec rails test test/jobs/video_processing_job_test.rb test/controllers/api/videos_controller_test.rb
printf 'Video test containers retained stopped: %s %s\n' "$app" "$db"
