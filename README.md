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
- Minitest
- RuboCop
- Brakeman

## Requirements

- Ruby 3.3+
- Bundler
- MySQL 8+

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

## Security Notes

- Passwords use BCrypt through `has_secure_password` when authentication models are implemented.
- Phone numbers are stored in normalized E.164 format.
- Activation codes, OTP values, session tokens, and device fingerprints are represented by digests.
- Secrets and Rails master keys are excluded from version control.
- Database credentials are supplied only through environment variables.

## Status

The database foundation is implemented and verified against MySQL 8. API resources, authentication services, authorization policies, OTP delivery, and business workflows will be added incrementally on top of this schema.
