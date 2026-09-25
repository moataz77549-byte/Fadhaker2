# RADIO STREAM FOUNDATION COMPLETION REPORT

## 1. STATUS

**PASS WITH WARNINGS**

The continuous-source core is real and passed with Liquidsoap, generated audio, FFmpeg decoders, multiple delayed listeners, failure injection, PostgreSQL ownership and regression tests. Full PASS is intentionally withheld because the Work sandbox runs as UID 0 and blocks the privilege drop required by Icecast. The listener proof therefore used a deliberately limited fan-out relay as the distribution endpoint. Real Icecast E2E remains a blocking Phase 5 closure test.

## 2. CONTINUOUS SOURCE TECHNOLOGY

**Liquidsoap 2.2.4-1+dev** was selected over custom long-running FFmpeg orchestration. It provides purpose-built continuous playlists, track-sensitive fallback, Icecast output/reconnect, metadata hooks, and a clean future path for live takeover. FFmpeg/ffprobe remain processing, validation and test-decoder tools; business scheduling remains in Radio Engine.

## 3. ICECAST CONFIGURATION

Development configuration is under `infrastructure/icecast/` and targets Icecast 2.4.4. It uses environment-only source/relay/admin credentials, a runtime-rendered configuration, container-local privilege drop, read-only root filesystem, tmpfs logs/config, localhost-only host publishing and a status health check. No real password is committed.

The generated configuration was rendered and parsed. Icecast distribution could not be executed in this sandbox because `setuid/setgroups` is forbidden; this is an environment limitation, not reported as a successful runtime test.

## 4. FIXED MOUNT

`/tarteel.mp3`. The URL is independent of media and remains fixed through track changes.

## 5. STREAM CODEC/FORMAT

| Property | Value |
|---|---|
| Codec | MP3 |
| MIME | `audio/mpeg` |
| Bitrate | 128 kbps |
| Sample rate | 44.1 kHz |
| Channels | Stereo |
| Storage input | Existing AAC-LC/M4A 96 kbps processed artifact; unchanged |

## 6. RADIO ENGINE FOUNDATION

`services/radio-engine/` is a standalone Node.js/TypeScript long-running service. It validates a development playlist, acquires station ownership, starts Liquidsoap, tracks current/next estimates, publishes metadata, checkpoints state, exposes local health endpoints and recovers the source with bounded exponential backoff. It does not implement Scheduler, Play Now/Next, priority, emergency commands, or live takeover.

## 7. STATE MACHINE IMPLEMENTED

Operational transitions implemented in this phase:

- `STOPPED → STARTING`
- `STARTING → AUTO | ERROR | STOPPED`
- `AUTO → RECOVERING | ERROR | STOPPED`
- `RECOVERING → AUTO | ERROR | STOPPED`
- `ERROR → RECOVERING | STOPPED`

`SCHEDULED`, `MANUAL`, and `LIVE` remain in the domain model only.

## 8. OWNERSHIP/LEASE

PostgreSQL RPCs atomically acquire, renew and release one lease per INTERNAL station using database time. TTL is 15 seconds and heartbeat is 5 seconds in Development. Every acquisition after expiry increments a fencing token. Real managed-Supabase validation proved:

- Engine A acquired the lease.
- Engine B was denied while A was valid.
- B acquired a higher fencing token after forced expiry.
- stale A renew and checkpoint were rejected.
- B checkpoint succeeded.

All four RPCs deny `anon` and `authenticated`; only `service_role` can execute them.

## 9. HEARTBEAT

Every 5 seconds the owner renews the 15-second lease and writes a fenced checkpoint/service heartbeat. Loss of the lease stops the source and moves the engine to `ERROR`. Lease timing uses PostgreSQL `now()`, not application wall time.

## 10. NOW PLAYING FOUNDATION

`radio.now_playing` and `radio.engine_states` store station, media/current/next, state, start/expected end, processing profile, mount, source connectivity and fencing token. Phase 5 timing is derived from probed duration after source connection; it is not an actual Liquidsoap playout ACK and must not back the public API yet.

## 11. CONTINUOUS PLAYBACK RESULTS

Real generated M4A tracks A/B/C were decoded and continuously encoded by Liquidsoap. Independent FFmpeg listeners decoded the MP3 source. The source advanced for 5.0 seconds with no listeners and continued across multiple joins/disconnects. The mount path remained `/tarteel.mp3` throughout the proof relay test.

## 12. TRACK TRANSITION RESULTS

Listeners observed A (nominal 440 Hz) and then B (nominal 660 Hz); their observed transition times differed by 504 ms. A later B→C transition differed by 162 ms between listeners B/C. The one-second frequency windows and decoder buffering limit precision. This proves the common evolving source but does **not** prove sample-gapless transitions; no gapless claim is made.

## 13. TWO-LISTENER TEST

Three listener processes were used. A joined after the source had already run; B joined later. A first detected 421 Hz and B first detected 423 Hz, both within Track A, so B did not start a private copy from the beginning. Both observed Track B while remaining on the same endpoint. Disconnecting A did not stop B. This result used the proof relay, not Icecast, so the critical Icecast-specific acceptance item remains open.

## 14. NO-LISTENER TEST

PASS for the continuous source: it ran 5.0 seconds before Listener A connected and did not wait for listener demand.

## 15. SOURCE CRASH TEST

PASS. Test-only `SIGUSR2` fault injection killed the Liquidsoap child; the Engine detected non-readiness, entered recovery, restarted the source, and returned ready in **5.819 seconds**. Fault injection is disabled unless explicitly enabled.

## 16. ENGINE CRASH TEST

PASS in isolated local mode. The Engine process group was killed and restarted; readiness returned in **5.801 seconds**. Managed lease takeover/fencing was validated separately against Supabase rather than combined with the local audio proof.

## 17. ICECAST FAILURE/RECOVERY TEST

**NOT EXECUTED against Icecast.** The development proof relay was stopped and restarted; Liquidsoap/source readiness recovered in **2.282 seconds**. This validates source reconnect behavior but is not evidence of Icecast recovery. An actual Icecast container restart must be tested in Phase 5B.

## 18. FALLBACK TEST

PASS. A playlist containing only an invalid item selected the generated development fallback; a decoder detected **330 Hz**. Invalid media was logged and skipped. The tone is a legal test fixture, not a production Never Silence asset.

## 19. METADATA TEST

PASS through the authenticated development metadata endpoint; the observed title was `Development Track C`. PostgreSQL remains the intended Now Playing source of truth.

## 20. STREAM TEST DURATION

**72.4 seconds**, covering multiple transitions, 3 listeners, no-listener progress, listener disconnect, source crash/recovery, distributor restart/reconnect, engine restart, fallback and metadata. A long soak was not performed.

## 21. REGRESSION RESULTS

| Suite | Result |
|---|---:|
| Database validation | 20/20 PASS |
| Storage validation | 16/16 PASS |
| Audio-processing DB validation | 16/16 PASS |
| Radio-stream DB validation | PASS, no exception |
| Audio Worker real unit/security | 20/20 PASS |
| Radio Engine unit/security | 3/3 PASS |

## 22. SECURITY RESULTS

- Lease/checkpoint RPC ACL: 4/4 deny anon/authenticated and allow service role only.
- Secret scan: no committed Supabase/Icecast secret value found.
- Runtime log scan: no generated source/relay/admin password leaked.
- Liquidsoap config is per-instance mode `0600`; workspace is `0700`; cleanup runs on stop.
- Commands use argument arrays; no user input is interpolated into a shell command.
- Mount is strictly validated and object paths must be absolute/ffprobe-valid.
- Supabase security advisor: 45 INFO notices, 0 WARN, 0 ERROR. The INFO items are primarily intentional RLS-enabled/no-policy deny-all tables in the API-first design; see the [advisor remediation reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

## 23. REAL TESTS VS SIMULATED TESTS

| Area | Classification |
|---|---|
| Liquidsoap continuous decode/encode | Real |
| FFmpeg listener decode/frequency analysis | Real |
| Generated M4A input/fallback | Real |
| Managed PostgreSQL ownership/fencing/checkpoints | Real, separate test |
| Multi-listener distributor | Minimal proof relay; not Icecast |
| Icecast config/version parsing | Real static/runtime startup attempt; distribution blocked |
| Icecast failure/recovery | Simulated distributor restart only |
| Container restart/supervisor | Not executed; Docker unavailable |

## 24. KNOWN ISSUES

1. Critical two-listener proof has not run through Icecast in this environment.
2. Current/next timing is duration-estimated, not Liquidsoap track-ACK driven.
3. Metadata update and source audio progression can briefly diverge because of item 2.
4. No 6-hour/24-hour soak, 500-transition waveform test, mobile-device compatibility test, or measured sample gap.
5. No production emergency asset/cache exists.
6. Engine and source restart tests were not combined with managed DB lease ownership in one E2E runtime.

## 25. WARNINGS

- Do not publish the proof relay; it exists only inside the test script.
- `TARTEEL_LIQUIDSOAP_ALLOW_ROOT=true` is a Work-sandbox test accommodation and defaults to false.
- Icecast 2.4.4 is the Ubuntu Development package; staging should pin a reviewed image digest/version.
- Private processed Storage retrieval is not yet integrated; Phase 5 uses validated local test files.

## 26. DEFERRED ITEMS

Scheduler, Play Now/Next/Interrupt, priority arbitration, live microphone/takeover, public API, Admin, Flutter, external providers, Nginx/TLS, Icecast HA, private Storage materialization/cache, production fallback assets, accurate playout ACK, long soak and production deployment.

## 27. FILES CREATED/MODIFIED

- `.gitignore`
- `README.md`
- `docs/ICECAST.md`
- `docs/STREAMING.md`
- `docs/RADIO_ENGINE.md`
- `docs/MVP_PLAN.md`
- `docs/RADIO_STREAM_FOUNDATION_REPORT.md`
- `services/radio-engine/**` source, tests, package/config documentation
- `infrastructure/icecast/**`
- `infrastructure/docker-compose.radio.yml`
- `infrastructure/radio/development-playlist.example.json`
- `infrastructure/scripts/generate-radio-fixtures.sh`
- `supabase/migrations/20260830001300_radio_stream_foundation.sql`
- `supabase/migrations/20260830001400_fix_engine_checkpoint_status_cast.sql`
- `supabase/tests/radio_stream_foundation_validation.sql`

Generated `node_modules/` and `dist/` are ignored and are not repository artifacts.

## 28. GIT/WORKSPACE STATE

The Work directory is a connector-backed staging copy without local `.git`. Phase files are prepared and validated locally; the final GitHub commit SHA is recorded in the handoff message after connector upload. No credential file is included.

## 29. EXACT NEXT RECOMMENDED PHASE

**Phase 5B — Real Icecast E2E Acceptance Closure** on a normal Docker/non-root Linux host. Run the checked-in proof without the relay, confirm `distribution_endpoint=icecast`, test an actual Icecast restart, measure two delayed listeners across at least two transitions, then perform a longer soak. Do not begin Scheduler until this gate passes or the owner explicitly accepts the residual risk.

## 30. ACCEPTANCE CHECKLIST

- [x] Liquidsoap continuous-source architecture implemented and actually executed.
- [x] Icecast Development config, secrets boundary and fixed mount created.
- [x] Live MP3 codec/container decision documented.
- [x] Radio Engine service/state subset implemented.
- [x] Atomic station lease, fencing, heartbeat and stale-owner rejection tested on Supabase.
- [x] Invalid-track skip and legal Development fallback tested.
- [x] Source crash and Engine restart tested with measured recovery.
- [x] Source independence from listener count tested.
- [x] Multiple delayed listeners proved on one continuous source endpoint.
- [x] Metadata foundation tested.
- [x] Database, Storage and Audio Processing regressions pass.
- [x] Secrets/RPC authorization reviewed.
- [ ] Real Icecast two-listener test passes.
- [ ] Actual Icecast restart/reconnect passes.
- [ ] Container/Docker startup and health check pass.
- [ ] Playout ACK replaces estimated track timeline.
- [ ] Long-duration/transition-gap soak meets approved target.

