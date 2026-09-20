# Flexible curriculum folders — safety and acceptance gate

Status: additive backend, management UI and student rendering implemented and
tested in isolation; no production migration or deployment has run.

## Confirmed defect

The current frontend `openDirectLectureEditor` creates a chapter named
`محتوى عام` and a lesson named `محاضرات المادة` before the lecture dialog is
saved. Cancelling can therefore leave real records behind. The fixed
Branch → Chapter → Lesson → Lecture schema is also leaking into the UI.

## Required behavior

- A folder creation submits exactly one intentional folder. Opening/cancelling
  a dialog performs no database writes.
- Folders and lectures coexist at the same level. A folder may contain folders
  and lectures, without mandatory chapter/lesson levels or automatic names.
- Rename, move to another folder, move to the subject root, and reorder are
  available with keyboard/touch controls; drag and drop is an enhancement.
- Moving a folder must reject itself and every descendant as destinations.
- Moving within the subject must preserve lecture IDs, storage/video IDs,
  watch history, assessment references, paid grants and activation codes.
- Cross-grade/year moves must not silently broaden access. They require a
  separately specified audience/access operation, not an ordinary folder move.
- Never infer that an old folder is disposable solely from its title.

## Migration design constraints

Use an additive folder hierarchy and explicit legacy-to-folder mappings.
Keep legacy records and foreign keys during rollout; do not drop/recreate
lectures or rewrite access grants as a side effect of rearranging folders.
Backfill must be idempotent, record source IDs, and validate complete lecture
coverage. Existing shared placements must not be lost or duplicated.
The published/student tree and playback visibility must use the same folder
visibility rules. Hidden/draft ancestor content must not leak through direct
URLs, free-content lists, search or video playback.

All hierarchy mutations must execute transactionally, serialize conflicting
changes, invalidate the catalog cache, and enforce content-management
permissions on the server. Retried create operations need stable idempotency
keys, not merely a disabled frontend button.

## Backup / restore gate

1. Establish authenticated host access and confirm the deployed revision.
2. Run `deploy/backup-before-folders.sh`. It creates a private, unique directory,
   dumps the production database, checks gzip/checksums, saves configuration and
   record counts, and never prunes earlier backups.
3. Make a protected off-host copy; do not commit data, configuration or credentials.
4. Restore the dump into a separately named, isolated database. Verify record
   counts and sample relationships. A checksum is NOT a restore test.
5. Test migration/backfill against that isolated restore, with email delivery
   and cloud deletion disabled. Record before/after counts and mapping checks.
6. Keep the old application image/revision. The additive schema must allow app
   rollback without dropping newly created content. Do not blindly restore an
   old database over new student activity.

## Required test cases

| Case | Expected result |
|---|---|
| Open/cancel folder or lecture dialog | Zero new records |
| Save one folder | Exactly one folder, specified parent/name |
| Double click, Enter twice, retry same request | Exactly one created item |
| Empty name / unavailable parent | Clear Arabic error, no partial records |
| Folder with sibling lecture | Both visible without forced extra levels |
| Nested folder creation | Only explicitly requested nesting |
| Move lecture to root or ancestor | Same lecture/video IDs, same watched progress |
| Move folder with descendants | Entire subtree preserved |
| Move into self / descendant | Rejected atomically |
| Stale or simultaneous move/reorder | No orphan, duplicate or lost item |
| Incomplete/duplicate reorder list | Rejected, original ordering retained |
| Unauthorized assistant/student mutation | Forbidden; unchanged database |
| Paid/free lecture after move | Same valid access, no newly exposed content |
| Existing codes and lesson grants | Continue to unlock the original entitlement |
| Shared lecture in two grades | Both placements preserved, one video asset |
| Draft/hidden ancestor | Hidden through tree and direct playback |
| Existing exam/homework references | Same questions, attempts and results |
| Backfill rerun | No duplicate folder mappings or lecture placements |
| Delete non-empty folder | Explicit safe behavior; never recursive data loss |
| Browser mobile/desktop/light/dark | Usable actions, visible errors, no overflow |

## Current execution evidence — 2026-09-20

- Production `/up` returned HTTP 200.
- SSH to the known production address timed out. No production writes occurred.
- OVH opened at its sign-in page; authenticated access is still required.
- Code archives created locally (NOT database backups):
  - Backend revision `e77e408`, SHA256
    `630F100D73A1AE869EAE23503F697C537C2EC3B6A4599164945884D5736B86E1`.
  - Frontend revision `a7a3616`, SHA256
    `71F55DD8CDA7695790CBDA069D55202E1C1845EB2740A9E34314C412AD04B915`.
- Subsequent authenticated OVH inspection: VPS Active, automatic provider backup
  dated 19 September, next payment 12 October. Renewal still displayed as manual.
- SSH access works intermittently, interspersed with connection timeouts.
- Fresh database/config backup created at
  `/srv/elmourdy/backups/folders-preflight-20260920T015628Z-VcpVvc`.
- Restored successfully into an isolated MySQL container with no network/ports.
  Recorded counts matched: branches 6, chapters 6, lessons 8, lectures 8,
  video assets 2, watch events 227, lecture grants 1, lesson grants 0,
  activation codes 502, exam attempts 116. This is database/config backup,
  not a copy of Cloudflare video objects or application storage volumes.
- Restore container retained stopped: `mourdy-restore-check-20260920015854`.
  An earlier startup-readiness attempt is also retained stopped:
  `mourdy-restore-check-20260920015757`.
- Additive CurriculumNode migration/model, locked folder operations, idempotent
  create and legacy backfill are implemented locally. They do not change existing
  lecture IDs, lesson ownership, permissions, grants or playback behavior.
- Protected off-host backup copied to the private local backup directory and its
  SHA256 matched the server archive.
- Migration/backfill rehearsal completed twice against a restored production
  snapshot. Legacy counts remained unchanged; there were zero orphan nodes and
  zero duplicate legacy mappings. The second backfill was idempotent.
- Latest isolated backend run using the production image plus the new source:
  **22 tests, 116 assertions, 0 failures/errors/skips**. It covers permissions,
  idempotent creation, cycle rejection, reorder validation, student visibility,
  access state, repeated backfill and first-lecture creation in an empty subject.
- Frontend quality gate: TypeScript and lint passed, **32 tests passed**, and the
  production build completed. Production dependency audit reported zero known
  vulnerabilities; the connected-video bundle still has a size warning.
- Staging API smoke test with the teacher account passed: login, tree retrieval,
  idempotent folder retry and cleanup. No production data was changed.
- Remaining release gate: complete a visual desktop/mobile click-through once a
  browser-control session is available, rerun the restore rehearsal if the schema
  changes again, then commit/push and deploy with post-deploy smoke tests.
