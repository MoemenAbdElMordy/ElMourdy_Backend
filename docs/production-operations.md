# Production Database Operations

## Deployment migration flow

Run migrations as a dedicated release step before starting new application processes:

```bash
RAILS_ENV=production bin/rails db:migrate
```

Do not run destructive schema changes in the same release that removes application compatibility. Use an expand-and-contract sequence:

1. Add nullable columns or new tables.
2. deploy code that writes both old and new structures when necessary.
3. backfill in controlled batches.
4. switch reads to the new structure.
5. remove obsolete structures in a later release.

## Backup policy

Use encrypted automated backups with retention in a separate storage account or region. A practical baseline is:

- daily full backup;
- binary-log retention for point-in-time recovery;
- thirty daily restore points;
- twelve monthly restore points;
- quarterly restore drills.

Example logical backup:

```bash
mysqldump \
  --single-transaction \
  --routines \
  --triggers \
  --set-gtid-purged=OFF \
  --databases el_mourdy_backend_production \
  > el_mourdy_backend.sql
```

Supply credentials through a protected MySQL option file or the hosting provider's secret system. Do not place passwords directly in shell history.

## Restore verification

Restore into an isolated database, never over the live production database during a drill:

```bash
mysql < el_mourdy_backend.sql
RAILS_ENV=production DATABASE_URL="$RESTORE_DATABASE_URL" bin/rails db:migrate:status
```

Verify row counts for users, enrollments, grants, attempts, and audit logs. Then run application smoke tests against the isolated restore.

## Monitoring

Monitor at least:

- connection usage and rejected connections;
- CPU, memory, disk latency, and free storage;
- replication lag when replicas exist;
- slow-query count and query latency percentiles;
- deadlocks and lock wait timeouts;
- failed migrations and backup jobs;
- table growth for watch events, sessions, OTP records, and audit logs.

Enable the slow query log with a conservative threshold, inspect recurring queries, and validate candidate indexes with `EXPLAIN ANALYZE` before changing production indexes.

## Data retention

- Expire OTP records after their operational troubleshooting window.
- Revoke and later purge old sessions according to the security policy.
- Keep submitted exam attempts and answers as academic history.
- Keep audit logs according to legal and operational requirements.
- Archive academic years rather than deleting them.
- Aggregate old watch events before purging raw events if long-term analytics are required.

Retention jobs must work in small batches to avoid long transactions and lock spikes.

## Secrets

Production requires unique values for:

- `DATABASE_URL`;
- `SECRET_KEY_BASE` or `RAILS_MASTER_KEY`;
- `SECURITY_PEPPER`;
- the initial teacher password during first-time seeding;
- future WhatsApp and video-provider credentials.

Rotate exposed secrets immediately. Changing `SECURITY_PEPPER` requires a planned token and digest migration because existing digests depend on it.

## Incident safety

- Never run `db:drop`, `db:reset`, or `db:schema:load` against production.
- Confirm the target host and database name before every manual operation.
- Prefer read-only diagnostic users for investigation.
- Record manual corrections in the audit log or an incident record.
- Test rollback behavior before deploying migrations, while recognizing that MySQL DDL may not be fully transactional.
