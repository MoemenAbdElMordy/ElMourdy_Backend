# ElMourdy Backend

The production-oriented Ruby on Rails API behind **ElMourdy**, an Arabic educational platform for secondary-school students, parents, teachers, and teaching assistants.

This service owns authentication, authorization, academic data, examinations, protected media, progress tracking, account administration, reporting, and operational audit records. It is designed around a relational MySQL model with explicit integrity constraints and query-driven indexes.

## Core Capabilities

- Secure phone-and-password authentication with revocable database sessions
- Student and parent registration with provider-neutral verification workflows
- Password recovery and verification status polling
- Role-based authorization for students, parents, teachers, and assistants
- Granular assistant permissions enforced by the API
- Student, parent, enrollment, device, and account management
- Academic years, grade progression, curriculum hierarchy, and ordering
- Lesson activation codes and manual access grants
- Grade-scoped examinations, attempts, answers, results, and error review
- Targeted announcements and support-request workflows
- Management dashboards, reports, student previews, and assistant audit logs
- Direct object-storage uploads and multi-quality HLS video processing
- Signed private playback delivery with watch-progress persistence
- Managed lecture thumbnails, descriptions, attachments, scheduling, and free access
- Consistent API pagination for high-volume administrative collections
- Versioned catalog caching backed by Solid Cache
- Durable video processing and maintenance jobs backed by Solid Queue
- WhatsApp Cloud API integration points and verified webhook handling

Payment processing is intentionally outside the current product scope.

## Technology Stack

| Area | Technology |
| --- | --- |
| Framework | Ruby on Rails 8.1 in API mode |
| Language | Ruby 3.3+ |
| Database | MySQL 8 with `utf8mb4` |
| Web server | Puma |
| Background work | Solid Queue |
| Object storage | Cloudflare R2 through the S3-compatible API |
| Video processing | FFmpeg and FFprobe |
| Authentication | BCrypt-backed passwords and digested session tokens |
| Testing | Minitest |
| Quality | RuboCop, Brakeman, Bundler Audit |

## Domain Architecture

The database is organized around these connected domains:

- **Identity:** users, role profiles, assistants, permissions, sessions, and devices
- **Academics:** academic years, grades, enrollments, branches, chapters, lessons, and lectures
- **Access:** activation-code batches, codes, redemptions, and lesson grants
- **Assessment:** examinations, questions, choices, attempts, and answers
- **Learning activity:** video assets, playback progress, and watch events
- **Operations:** announcements, support requests, dashboards, reports, and audit logs
- **Verification:** registration and password-reset verification records with provider delivery metadata

Foreign keys protect relationships, database constraints protect valid states, and indexes follow real filtering, uniqueness, ordering, and lookup paths.

## Local Setup

### Requirements

- Ruby 3.3 or newer
- Bundler
- MySQL 8 or newer
- FFmpeg 7 or newer for video processing

### Installation

```bash
git clone https://github.com/MoemenAbdElMordy/ElMourdy_Backend.git
cd ElMourdy_Backend
bundle install
```

Copy the environment template and provide local values:

```bash
cp .env.example .env
```

Prepare the database and start Rails:

```bash
bin/rails db:prepare
bin/rails server
```

The API starts on `http://localhost:3000` by default. Health checks are available at:

```text
GET /up
```

## Environment Configuration

The complete variable list is documented in `.env.example`. Important groups include:

### Database

```env
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=
```

Production may use a single `DATABASE_URL` instead.

### Application Security

```env
FRONTEND_ORIGINS=https://example.com
SECURITY_PEPPER=replace-with-a-long-random-production-secret
VIDEO_PLAYBACK_SECRET=replace-with-a-long-random-playback-secret
```

### Media Storage

```env
VIDEO_STORAGE_SERVICE=local
R2_BUCKET=elmourdy-videos
R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=replace-with-an-r2-access-key
R2_SECRET_ACCESS_KEY=replace-with-an-r2-secret-key
MEDIA_DELIVERY_BASE_URL=https://video.example.com
```

### WhatsApp Verification

```env
WHATSAPP_ACCESS_TOKEN=replace-with-a-system-user-access-token
WHATSAPP_PHONE_NUMBER_ID=replace-with-the-phone-number-id
WHATSAPP_OTP_TEMPLATE_NAME=replace-with-an-approved-template
WHATSAPP_WEBHOOK_VERIFY_TOKEN=replace-with-a-long-random-webhook-token
META_APP_SECRET=replace-with-the-meta-app-secret
```

Never commit real credentials, production tokens, database passwords, or Rails master keys.

## Authentication and Authorization

Passwords are verified with `has_secure_password`. A successful login returns a random bearer token while only its digest is stored in MySQL. Logout and security-sensitive account changes revoke sessions at the database level.

Phone numbers are normalized to E.164 before lookup. Suspended or archived accounts cannot reuse an old session. Generic authentication errors avoid leaking whether a phone number exists.

Every protected controller checks the authenticated role, account status, and—where applicable—the assistant permission required for that operation.

## Video Pipeline

Large uploads do not pass through a normal Rails multipart request.

1. Rails creates a short-lived upload target.
2. The client uploads the original directly to the configured storage service.
3. A Solid Queue job reads the original and runs FFmpeg locally.
4. The pipeline creates 360p, 480p, and 720p HLS renditions.
5. Playlists and segments are uploaded once to object storage.
6. The output is verified before the video becomes publishable.
7. The original may be removed after successful processing.

Start the durable worker with:

```bash
bin/jobs
```

Development uses local storage under `tmp/video_storage` by default. Production uses private R2 objects and short-lived playback tokens.

Lecture thumbnails are stored privately and streamed through an authenticated endpoint with private browser caching, ETags, and last-modified validation.

## Pagination and Caching

Large collection endpoints return a consistent `pagination` object containing the current page, page size, total count, total pages, and adjacent page numbers. The default page size is 20 and the enforced maximum is 100.

Stable public catalog reads use Solid Cache with versioned keys. Model changes automatically advance the catalog version, preventing stale academic content without broad cache scans. Authentication, permissions, dashboards, and student progress remain uncached because they are personal or security-sensitive.

Production uses MySQL-backed Solid Cache by default, so a separate cache service is not required for the initial deployment.

## Background Jobs

Production uses Solid Queue for durable background processing. Video jobs run on a dedicated single-threaded queue to avoid competing FFmpeg processes for server resources, while ordinary jobs use the default worker pool.

A recurring maintenance job removes old completed queue records. Puma may supervise Solid Queue in the initial single-server deployment through `SOLID_QUEUE_IN_PUMA=true`; larger deployments should run workers as separately supervised processes.

## API Areas

All application endpoints are under `/api` and include:

- Sessions, registration, verification, password resets, profiles, and devices
- Academic years, grades, students, parents, assistants, and reports
- Curriculum branches, chapters, lessons, lectures, and ordering
- Video upload, processing, playback, delivery, and watch events
- Activation-code batches, codes, redemptions, and access grants
- Examinations, attempts, answers, announcements, and support requests
- Free lectures, dashboards, student previews, and audit logs
- WhatsApp webhook verification and event delivery

Refer to `config/routes.rb` for the authoritative route list.

## Database Operations

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:migrate:status
bin/rails db:seed
bin/rails db:rollback
```

Demo records used for local end-to-end testing can be managed with the tasks in `lib/tasks/demo_data.rake`. They are development data and must not be treated as production fixtures.

## Testing and Security Checks

Run the automated test suite:

```bash
bin/rails test
```

Run style and static security analysis:

```bash
bundle exec rubocop
bundle exec brakeman --no-pager
bundle exec bundler-audit check --update
```

Production readiness requires passing tests, zero RuboCop offenses, and review of every Brakeman or dependency-audit finding.

## Production Notes

- Serve Rails and background jobs as separate supervised processes
- Use a managed or regularly backed-up MySQL instance
- Keep R2 objects private and deliver them only through signed playback URLs
- Configure explicit frontend origins instead of wildcard CORS
- Rotate all secrets independently and keep them outside the repository
- Run migrations before shifting application traffic
- Monitor failed jobs, API errors, storage usage, database health, and video-processing duration

Operational references are available in:

- [Database design](docs/database-design.md)
- [Production operations](docs/production-operations.md)

## Related Repository

The React application is maintained in [ElMourdy](https://github.com/MoemenAbdElMordy/ElMourdy).

## License

Private and proprietary software. All rights reserved.
