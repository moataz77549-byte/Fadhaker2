# PHASE 6 — RADIO AUTOMATION COMPLETION REPORT

## 1. STATUS

**PASS WITH WARNINGS** — The deterministic scheduler, persistent queue, fenced commands, real Liquidsoap/Icecast automation path, two-listener test, and 30-minute soak passed. The remaining warning is integration closure: the protected Supabase write path and the real audio path were proven in separate trusted runs, and the production coordinator that materializes every claimed occurrence into the queue still needs one combined-runtime acceptance gate.

Evidence:

- Phase 6 real automation run: `33318285194` — PASS.
- Phase 5B regression run: `33318285201` — PASS.
- Final commit under test: `4c9b8cde9197614074a6c1bcf7d35fe2714c96bf`.

## 2. INTERNAL DEVELOPMENT STATION

- ID: `00000000-0000-4000-8000-000000000006`
- Arabic name: `ترتيل — تطوير`
- Slug: `tarteel-dev`
- Source/stream: `INTERNAL` / `INTERNAL`
- Mount: `/tarteel.mp3`
- Timezone: `Asia/Aden`
- `production_enabled = false`
- Four READY generated tone fixtures and one two-item default playlist were seeded.

## 3. SUPABASE ENGINE SMOKE TEST

Real DEVELOPMENT Supabase calls passed:

- Engine A acquired fencing token 1; Engine B acquired token 2 after expiry.
- A stale checkpoint was rejected with SQLSTATE `55000`.
- Heartbeat/checkpoint and Now Playing persisted under the current owner.
- A Liquidsoap ACK from run `33318285194` was persisted with fencing token 3.
- Database `started_at = 2026-08-30T14:59:23.240Z` exactly matched the ACK timestamp.
- Persisted source was `AUTO`, media A, mount `/tarteel.mp3`.
- No credentials appeared in structured logs.

Limitation: CI did not receive a Supabase service secret; therefore the live audio run and protected DB smoke test were separate trusted executions.

## 4. DATABASE CHANGES

Five focused migrations added queue persistence, command effects, occurrence hardening, fenced history/Now Playing references, recovery, and the DEVELOPMENT seed. Existing Phase 2–5 schema was not rebuilt.

## 5. SCHEDULER ARCHITECTURE

The scheduler computes IANA-timezone occurrences, persists one row per intended instant, claims due rows atomically, rejects stale ownership, classifies missed rows, and hands business decisions to the Queue Manager. It does not communicate with Liquidsoap or Icecast directly.

## 6. SCHEDULE OCCURRENCE MODEL

`radio.schedule_occurrences` records schedule version, intended UTC instant, content snapshot, priority, interrupt policy, claim owner/token, execution timestamps, result, and failure. Uniqueness on `(schedule_id, scheduled_for)` prevents duplicate materialization.

Statuses distinguish pending, claimed, executing, completed, failed, skipped/missed, and conflict loss. A same-boundary conflict loser is terminally `SKIPPED/CONFLICT_LOST`, not replayed on the next poll.

## 7. TIMEZONE IMPLEMENTATION

- IANA zones are evaluated independently from server local time.
- Operational instants are UTC.
- DAILY, WEEKLY, multiple weekdays, day/week boundaries, and `Asia/Aden` conversion passed.
- DST gap policy: shift to the first valid wall-clock instant.
- DST fold policy: choose the earlier instant once.
- ONE_TIME is materialized once and is not replayed after restart.
- Configurable grace classifies late occurrences as executable or `MISSED`.

## 8. QUEUE MANAGER

Persistent business lanes are: `EMERGENCY`, `MANUAL`, `SCHEDULED`, `AUTO`, and `FALLBACK`. Current/next selection is deterministic. Liquidsoap retains only its runtime audio buffer; business intent survives engine restarts in PostgreSQL.

## 9. PRIORITY DECISION TABLE

| Rank | Decision |
|---:|---|
| 50 | LIVE reservation (behavior deferred) |
| 40 | EMERGENCY |
| 30 | HIGH |
| 20 | NORMAL |
| 10 | LOW |

Tie-break order is priority rank, intended/scheduled instant, creation time/sequence, then stable UUID. Rows are never selected using unordered database results.

Operational precedence at a boundary is LIVE reservation → emergency interrupt → valid manual interrupt → due schedule by priority → manual Play Next → continuing active content → default playlist → fallback.

## 10. DEFAULT PLAYLIST

The seeded station default playlist loops through valid READY media. Empty or invalid AUTO content falls through to the configured DEVELOPMENT fallback. External stations cannot use this automation path.

## 11. COMMAND PROCESSING

`PENDING → PROCESSING → COMPLETED|FAILED|CANCELLED` uses atomic claim, station fencing, payload validation, internal IDs only, and a command-effect ledger. `idempotency_key` plus effect uniqueness prevents blind reapplication after a crash.

## 12. PLAY_NOW RESULT

Media and playlist payloads are validated. Real E2E `PLAY_NOW D` interrupted active playout in **21 ms** at the control layer, without changing the mount or applying crossfade/overlap.

## 13. PLAY_NEXT RESULT

Multiple requests retain deterministic sequence. Real E2E waited **19,823 ms** for the current track boundary before `PLAY NEXT C` started.

## 14. SKIP RESULT

PASS in command/queue tests. Skip targets only the currently active Liquidsoap source (`main` or `automation`) and then returns to the central decision flow. It was not separately injected into the 30-minute live scenario.

## 15. STOP_AFTER_CURRENT RESULT

PASS in state/command tests. The command sets intentional stop-after-boundary behavior; `STOPPED` is an operator state rather than a failure. It was not exercised against the final real stream run.

## 16. RESUME_AUTO RESULT

PASS in state/command tests. It clears the applicable manual intent and resumes the next valid automated decision without changing the stream URL. It was not separately injected into the final real stream run.

## 17. FINISH_CURRENT RESULT

PASS in real E2E. The due scheduled item waited for the track boundary; measured boundary-control delay was **93 ms**. No crossfade, overlap, trimming, tempo, or pitch change was used.

## 18. INTERRUPT RESULT

PASS in real E2E. Manual D interrupted the active item cleanly in **21 ms** at the control layer. The data model records `interrupted`, reason, command, queue entry, and playout ID.

## 19. SCHEDULE CONFLICT TESTS

HIGH beat NORMAL. Equal-priority conflicts resolved by intended instant, creation order, then stable ID. Only one occurrence won; the loser was marked `CONFLICT_LOST`. Disabled/future schedules and external stations were rejected/ignored as designed.

## 20. IDEMPOTENCY RESULTS

- Duplicate occurrence uniqueness: PASS.
- Duplicate command idempotency key: rejected.
- Duplicate queue mutation: one row/effect.
- Duplicate Playout ACK: one history row via unique `playout_id`.
- Real E2E schedule occurrences executed: **1**.
- Real E2E direct command/control actions: **12**.

## 21. FENCING RESULTS

PASS. Tokens advanced 1 → 2 → 3 across real Supabase tests. A stale engine could not checkpoint, claim/complete a command, change queue state, or write Now Playing after ownership loss.

## 22. RECOVERY RESULTS

A command left `PROCESSING` by an expired owner was recovered and claimed once by the next fenced owner. Monotonic fencing survives release because lease rows are expired, not deleted.

A shutdown race was discovered after the first 1802.5-second run: a late Liquidsoap disconnect callback attempted a checkpoint after lease release. Late source events are now ignored once shutdown owns the final checkpoint; the complete 1801.4-second rerun passed including cleanup.

## 23. NEVER SILENCE RESULT

Invalid tracks are skipped, AUTO continues, and an empty/failed default path selects fallback. The queue tests and prior real-stream regressions passed. The final Phase 6 soak recorded **0 mount failures** and **0 decoder errors**. A forced fallback activation was not injected into the final soak.

## 24. PLAY HISTORY ACCURACY

History is created from Playout ACK, not enqueue time, and references station, media, source, queue entry, command, occurrence, playlist, fencing token, and unique playout ID. Interruption/completion fields are explicit. The real Supabase ACK produced history ID 3 with an exact start timestamp match.

## 25. NOW PLAYING ACCURACY

Now Playing is updated from Liquidsoap track-start ACK. The final live run produced **107 ACKs**. The persisted Supabase proof matched the selected ACK timestamp exactly at database precision. End-to-end listener metadata skew was not measured independently from the callback in this phase.

## 26. REAL ICECAST AUTOMATION E2E

PASS: real Radio Engine → Liquidsoap 2.2.4 → real Docker Icecast → `/tarteel.mp3` → FFmpeg decoders. Sequence proven: AUTO → scheduled B → AUTO → Play Next C → Play Now D interrupt → AUTO. Content type was `audio/mpeg`.

## 27. TWO-LISTENER RESULT

Two real FFmpeg listeners used the same mount. Listener B joined **5,000 ms** later. Observed decision differences were **320 ms** for the schedule transition and **321 ms** for interrupt, within independent decoder buffering.

## 28. FIXED MOUNT RESULT

PASS. `/tarteel.mp3` remained unchanged through all schedule, manual, interrupt, AUTO, join/leave, and no-listener transitions. Mount failures: **0**.

## 29. SOAK TEST

- Duration: **1,801.4 seconds** (30 minutes 1.4 seconds).
- Track transitions: **101**.
- Playout ACKs: **107**.
- Listeners: **2**.
- No-listener interval: **25 seconds**; ACK count advanced by **1**.
- Commands/control actions: **12**.
- Schedule occurrences: **1**.
- Decoder errors: **0**.
- Unexpected failures: **0**.

## 30. REGRESSION RESULTS

- Radio Engine local: **18/18 PASS**.
- Audio Worker local real FFmpeg/ffprobe: **20/20 PASS**.
- Supabase database, storage, audio-processing, and radio-stream validation suites: PASS.
- Phase 5B real Icecast regression run `33318285201`: PASS, including its 30-minute acceptance.

## 31. SECURITY RESULTS

- `anon` and ordinary `authenticated` roles have no `radio` schema usage or sensitive function execution.
- Direct queue insert, command insert, claim, and effect writes were denied.
- Commands accept internal IDs, not shell arguments, paths, or arbitrary URLs.
- External station/content injection is rejected.
- Icecast credentials were ephemeral environment values and masked.
- Evidence reported `secret_leak = false`.

## 32. REAL VS SIMULATED TESTS

Real: Supabase migrations/functions/fencing/ACK persistence; FFmpeg/ffprobe; Liquidsoap; Docker Icecast; fixed mount; two decoder listeners; 30-minute automation and Phase 5B regressions.

Deterministic component tests: timezone recurrence, DST, missed grace, command variants, conflict ordering, STOP/SKIP/RESUME, duplicate behavior, and fallback selection.

Not a single combined process: GitHub Actions had no Supabase service secret, so the real streaming scenario drove engine controls directly while the protected PostgreSQL claim/effect path was validated separately against DEVELOPMENT Supabase.

## 33. BUGS FOUND AND FIXED

1. Liquidsoap playlist reload could defer manual tracks: added a dedicated `request.queue` automation lane.
2. Unsupported Liquidsoap 2.2.4 `queue_length`: removed.
3. Generic skip targeted the wrong source: skip now targets the active lane only.
4. Lease release reset fencing risk: release now expires the row and preserves monotonic tokens.
5. Same-time conflict loser could replay: it is now terminally skipped.
6. Enum CASE assignments needed explicit PostgreSQL casts: corrected.
7. Late disconnect during shutdown wrote after lease release: source callbacks now stop at shutdown boundary.

## 34. KNOWN ISSUES

- The production coordinator still needs to connect `SchedulerLoop.claim()` to queue materialization and command polling in one long-running, secret-backed runtime.
- SKIP, STOP_AFTER_CURRENT, RESUME_AUTO, and forced fallback were not each repeated in the final 30-minute audio run; their deterministic tests pass.
- Now Playing listener-perceived timing was not independently correlated beyond Liquidsoap ACK and two-decoder transition observations.

## 35. WARNINGS

- DEVELOPMENT fixtures and fallback are not production content.
- External stations remain isolated from internal automation.
- LIVE input behavior remains reserved but unimplemented.
- PostgreSQL is sufficient for MVP; no Redis/Kafka was introduced.

## 36. DEFERRED ITEMS

Admin/Public APIs, Admin UI, Flutter, live microphone, provider sync, external health worker, push notifications, production deployment, and full LIVE takeover remain deferred.

## 37. FILES CREATED/MODIFIED

Thirty-one Phase 6 files changed: five migrations, one SQL validation suite, Radio Engine scheduler/queue/command/store modules and tests, real E2E workflow/script, fixture generator/config, six design documents, and this report. See PR #2 for the exact reviewed list.

## 38. GIT/WORKSPACE STATE

- Implementation pull request: `#2`, merged into `main` as `422f08743df7024dc176e6924702ab4836e8290f` after both required checks passed.
- Tested implementation head: `4c9b8cde9197614074a6c1bcf7d35fe2714c96bf`.
- Completion report is delivered as a documentation-only follow-up from `phase6-radio-automation`.
- DEVELOPMENT Supabase contains the approved station seed plus one retained Phase 6 ACK/history evidence row.

## 39. EXACT NEXT RECOMMENDED PHASE

**PHASE 6B — Protected Runtime Integration Closure**: run the long-lived coordinator with a trusted Supabase service credential so occurrence claim → queue materialization → command claim/effect → Liquidsoap ACK → history/Now Playing is proven in one runtime. This is a narrow closure gate, not Admin, Flutter, or a redesign.

## 40. ACCEPTANCE CHECKLIST

- [x] INTERNAL DEVELOPMENT station and default playlist.
- [x] Real Supabase lease, heartbeat/checkpoint, fencing, Now Playing, and ACK persistence.
- [x] ONE_TIME, DAILY, WEEKLY, multiple weekdays, timezone and DST tests.
- [x] Persistent deterministic queue and occurrence idempotency.
- [x] Conflict priority and stable tie-breaking.
- [x] FINISH_CURRENT, INTERRUPT, PLAY_NEXT, PLAY_NOW.
- [x] SKIP, STOP_AFTER_CURRENT, RESUME_AUTO component tests.
- [x] Command idempotency, effect ledger, stale-owner rejection and recovery.
- [x] Play history and source-aware Now Playing model.
- [x] Never Silence/default/fallback decision path.
- [x] Real Liquidsoap/Icecast automation E2E and two listeners.
- [x] Fixed mount and 30-minute soak.
- [x] No secret leakage and previous-phase regressions.
- [x] Documentation updated.
- [ ] Single combined secret-backed coordinator runtime acceptance (Phase 6B warning).

Phase 6 stops here; no Phase 7 work was started.
