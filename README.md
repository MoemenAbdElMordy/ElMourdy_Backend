# ElMourdy Backend

Ruby on Rails API and MySQL database for the ElMourdy Arabic educational platform.

## Current Scope

This repository contains the backend foundation and the first production-oriented database schema. The initial migration creates the identity, academic content, activation, examination, device, session, support, announcement, and auditing tables with foreign keys and query-driven indexes.

Payment processing is intentionally outside the current product scope. Lesson access is granted through activation codes, free access, or manual administration.

## Technology

- Ruby 3.3
- Rails 8.1 API mode
- MySQL 8 with `utf8mb4`
- Puma
- FFmpeg and FFprobe
- Cloudflare R2-compatible object storage
- Solid Queue
- Minitest
- RuboCop
- Brakeman

## Requirements

- Ruby 3.3+
- Bundler
- MySQL 8+
- FFmpeg 7+

## Setup

```bash
bundle install
cp .env.example .env
bin/rails db:prepare
bin/rails server
```

Configure the database connection through `DB_HOST`, `DB_PORT`, `DB_USERNAME`, and `DB_PASSWORD`. Production uses `DATABASE_URL`.

The health endpoint is available at:

```text
GET /up
```

## Database Domains

- Users, students, parents, assistants, and permissions
- Academic years, grades, enrollments, and curriculum hierarchy
- Lectures, video assets, and viewing progress
- Activation-code batches, secure code digests, and lesson entitlements
- Grade-scoped exams, questions, choices, attempts, and answers
- Student devices and authenticated sessions
- OTP verification with a provider-neutral WhatsApp-ready design
- Support requests and administrative actions
- Targeted announcements and immutable audit trails

## Database Commands

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:migrate:status
bin/rails db:rollback
```

## Quality Checks

```bash
bin/rails test
bundle exec rubocop
bundle exec brakeman --no-pager
```

## Video Pipeline

Large video files upload directly to object storage through short-lived signed URLs. A single-concurrency Solid Queue worker downloads each original, uses FFmpeg to create 360p, 480p, and 720p HLS variants, uploads the generated playlists and segments, and removes the original after successful verification.

Development defaults to local storage under `tmp/video_storage`. Production requires the R2 and media-delivery environment variables documented in `.env.example`. Start durable background processing with:

```bash
bin/jobs
```

The media gateway in `cloudflare/video-gateway` validates short-lived playback tokens before reading private HLS objects from R2.

## Security Notes

- Passwords use BCrypt through `has_secure_password` when authentication models are implemented.
- Phone numbers are stored in normalized E.164 format.
- Activation codes, OTP values, session tokens, and device fingerprints are represented by digests.
- Secrets and Rails master keys are excluded from version control.
- Database credentials are supplied only through environment variables.

## Status

The production database foundation, integrity constraints, Active Record domain models, concurrency-safe database services, deterministic seeds, and automated database tests are implemented and verified against MySQL 8.

Detailed references:

- [Database design](docs/database-design.md)
- [Production database operations](docs/production-operations.md)

API resources, authentication controllers, authorization policies, and WhatsApp OTP delivery will be added incrementally on top of this foundation.
