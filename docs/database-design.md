# Database Design

## Purpose

The database is the source of truth for the ElMourdy platform. It is designed for one educational organization, one primary subject, three secondary-school grades, activation-code access, and multiple user roles.

The schema uses MySQL 8, InnoDB, `utf8mb4`, and Rails bigint primary keys. All application timestamps are stored in UTC and converted to the Cairo time zone at the application boundary.

## Data Domains

### Identity

- `users` stores login identity, password digests, role, account status, and verified phone state.
- `student_profiles`, `parent_profiles`, and `assistant_profiles` hold role-specific data.
- `assistant_permissions` stores fine-grained permissions instead of hard-coding every assistant role.
- `student_parent_links` supports one parent account linked to multiple students.

Phone numbers used for identity are normalized to E.164 before persistence. Display formatting is not used for lookup or uniqueness.

### Academic organization

- `academic_years` separates current and historical data.
- `grades` contains the three supported secondary-school levels.
- `student_enrollments` assigns one student to one grade in each academic year.
- `branches`, `chapters`, `lessons`, and `lectures` form the curriculum hierarchy.

Every ordered content level has a positive `position` and a scoped unique index. This guarantees deterministic ordering and prevents two items from occupying the same position in one parent container.

### Video

- `video_assets` represents an uploaded source video and its processing state.
- `video_variants` stores one generated file per supported quality.
- `lecture_watch_events` stores progress and completion data.

Storage provider keys are persisted instead of public URLs. A delivery service can later generate short-lived signed URLs.

### Access codes

- `activation_code_batches` describes a generated batch for one lesson, grade, and academic year.
- `activation_codes` stores a keyed digest for exact lookup and optional encrypted ciphertext only when later export is required.
- `lesson_access_grants` is the actual entitlement record.

A code unlocks a lesson rather than a single lecture. New lectures added to the lesson automatically become available to the student.

### Exams

- `exams` supports lesson, chapter, branch, or comprehensive scope.
- A comprehensive exam always belongs to exactly one grade and one academic year.
- `exam_questions` and `exam_choices` hold multiple-choice content.
- `exam_attempts` snapshots question order and stores scoring results.
- `exam_answers` stores one answer per question and attempt.

Database check constraints enforce a single matching scope reference. Composite unique indexes protect attempt numbering and answer uniqueness.

### Devices and sessions

- `device_registrations` stores a keyed fingerprint digest and device metadata.
- `user_sessions` stores a digest of the authentication token, never the raw token.

The three-device limit and single-active-student-session rule require transactions and row locks. A normal index cannot enforce a maximum row count or a conditional single row in MySQL.

### Operations

- `otp_verifications` supports registration and phone-change verification while remaining provider-neutral.
- `support_requests` and `support_request_actions` model review workflows.
- `announcements` and `announcement_targets` support grade and direct-user targeting.
- `audit_logs` stores append-only security and administration history.

## Integrity Layers

The project deliberately uses three integrity layers:

1. Active Record validations provide clear application errors.
2. Unique indexes and check constraints protect the database from invalid direct writes.
3. Transactions and row locks protect multi-row business rules from concurrent requests.

Application validation is not a replacement for a database constraint. Two processes can pass the same validation at the same time. The database remains the final authority.

## Delete Policies

- `CASCADE` is used only for true owned children with no independent history, such as assistant permissions, video variants, support request actions, and announcement targets.
- `SET NULL` preserves history when an optional actor account is deleted, such as audit actors and content creators.
- `RESTRICT` is the default for academic history, attempts, answers, grants, codes, devices, and watch events.
- User-facing deletion should archive records first. Hard deletion must run through a dedicated service that checks dependencies and records an audit event.

## Indexing Rules

- Every foreign key is indexed directly or covered by the leftmost columns of a composite index.
- Composite index column order follows equality filters first, then range or ordering columns.
- Unique indexes enforce identity and business invariants.
- Duplicate single-column indexes are avoided when a composite index already provides the same leftmost lookup.
- Indexes are validated with production-like queries and `EXPLAIN ANALYZE` after realistic data volume exists.

## Concurrency Rules

### Activation-code redemption

`ActivationCodes::Redeem` locks the code row with `SELECT ... FOR UPDATE`, validates its current state, marks it redeemed, and creates the entitlement in one transaction.

### Exam attempts

`ExamAttempts::Start` locks the student profile, counts existing attempts, assigns the next attempt number, snapshots question order, and relies on the unique index as the final race-condition guard.

### Devices

`Devices::Register` locks the student profile before counting active devices. This serializes concurrent registration attempts for the same student.

### Sessions

`Sessions::Start` locks the user, revokes earlier active student sessions, generates a random raw token, stores only its digest, and returns the raw token once.

### Parent linking

`ParentLinks::Sync` locks the parent profile and creates missing links for every student with the verified parent phone number.

## Future Performance Verification

Index design must be revisited after production-like data is available. Capture and analyze the slow query log, then use:

```sql
EXPLAIN ANALYZE SELECT ...;
```

Priority queries include student rosters, current curriculum, active entitlements, exam reports, support queues, announcements, and audit history.
