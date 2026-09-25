# PHASE 5B — REAL ICECAST ACCEPTANCE REPORT

## 1. STATUS

**PASS WITH WARNINGS.** The real distribution path passed. The warning is limited to managed Supabase persistence not being connected to GitHub Actions; playout acknowledgement and audio comparison were real, but `radio.now_playing` was not written to Supabase by this CI run.

Evidence: run `33310689611`, job `99255070512`, tested commit `3bbfcf3260d5638879f42135369f16f4f5e071ff`, artifact `9732285971` (SHA-256 `ed7e1744fa6d45b82162e191a15adbc7eeef3b4844ad6e2a92c6e8f23ce02e39`).

## 2. TEST ENVIRONMENT

GitHub Actions Ubuntu 24.04, real Docker Engine/Compose and Icecast container, host Liquidsoap and FFmpeg decoders. Credentials were generated per run, masked, stored in an ignored mode-0600 file, and removed during cleanup.

## 3. ICECAST VERSION

Icecast 2.4.4 (`2.4.4-4build4`).

## 4. LIQUIDSOAP VERSION

Liquidsoap `2.2.4-1+dev`.

## 5. REAL SOURCE CONNECTION

Radio Engine launched Liquidsoap; Liquidsoap authenticated to Icecast and created the mount. Two connections were observed: initial and automatic reconnect after the deliberate restart. Liquidsoap itself was not restarted.

## 6. FIXED MOUNT RESULT

`/tarteel.mp3` remained unchanged through joins, 90 transitions, no-listener operation, and recovery.

## 7. STREAM FORMAT VERIFIED

`audio/mpeg`, MP3, about 128 kbps, 44.1 kHz, stereo. Icecast reported `channels=2;samplerate=44100;bitrate=128`; FFmpeg decoded 1,733 analyzed frames with zero stable decoder errors.

## 8. LISTENER A RESULT

Real FFmpeg listener A decoded the Icecast mount; first measured development tone: 421 Hz (440 Hz fixture with encoding/window tolerance).

## 9. LISTENER B RESULT

Listener B connected 5,504 ms after A to the same mount. Its first tone was 422 Hz, proving current-broadcast join rather than track restart.

## 10. LISTENER C RESULT

Listener C joined later and decoded the current broadcast. Six real decoder instances were used across scenarios; Icecast observed 3 concurrent listeners at peak.

## 11. DELAYED JOIN PROOF

A and B started on the same in-progress fixture within 1 Hz despite B joining 5.504 seconds later. Listener D joined after a 25-second zero-listener period and heard the then-current 440 Hz item.

## 12. TRACK TRANSITION RESULTS

A→B differed by 519 ms and B→C by 721 ms between listeners, both below the 2,000 ms threshold. Ninety playout transitions were acknowledged.

## 13. NO-LISTENER CONTINUITY

All listeners were disconnected for 25 seconds. ACK count advanced by one, and a later listener decoded the current item. PASS.

## 14. ICECAST STOP TEST

Stopped at `2026-08-30T12:10:53.031Z`. The existing TCP listener disconnected as expected; the Engine observed source disconnection.

## 15. ICECAST RESTART TEST

Restart initiated `12:10:54.336Z`; process available `12:10:55.055Z`; source connected `12:10:58.334Z`; mount visible `12:10:58.336Z`; listener decoded audio `12:10:59.591Z`.

## 16. LIQUIDSOAP RECONNECT RESULT

PASS. Liquidsoap survived the outage and reconnected without Radio Engine or Liquidsoap restart. Source connections: 2; source starts: 1.

## 17. RECOVERY TIMINGS

| Measurement | Result |
|---|---:|
| Failure detection | 1,305 ms |
| Icecast process availability | 719 ms |
| Source reconnect | 3,998 ms |
| Mount restore | 4,000 ms |
| Listener audio restore | 5,255 ms |

The old listener socket correctly died; client auto-reconnect remains a Flutter responsibility.

## 18. PLAYOUT ACK IMPLEMENTATION

Liquidsoap `main.on_track` emits the actual boundary. The Engine advances the deterministic validated playlist, closes the previous item, sets current/next, publishes metadata, and checkpoints. Duration timers no longer declare track starts. The callback is strict-safe and does not interpolate filenames or titles into Liquidsoap code.

## 19. NOW PLAYING ACCURACY

Observed 91 real start ACKs and 90 end ACKs. ACK-to-heard errors for analyzed transitions were 1,192 ms and 1,635 ms (maximum 1,635 ms), within expected distribution/decoder buffering. Managed Supabase persistence was not connected in CI; this is the warning.

## 20. SOAK TEST DURATION

1,807.5 seconds (30 minutes 7.5 seconds), measured from source readiness.

## 21. AUDIO GAP OBSERVATIONS

No crossfade/overlap. Maximum stable decoded chunk gap: 143 ms; recurring malformed/decoder errors: 0; post-recovery mount probe failures: 0. This is not a claim of sample-gapless output.

## 22. STREAM INTEGRITY

PASS: valid MP3, `audio/mpeg`, 44.1 kHz, stereo, about 128 kbps, 1,733 frames analyzed, zero stable decoder errors.

## 23. LISTENER COUNT OBSERVATION

Icecast reported 3 simultaneous listeners during A/B/C. Listener count is observability only.

## 24. DOCKER VERIFICATION

PASS. Compose build/start, loopback binding, health, stop/restart, networking, artifact collection, and cleanup ran for real. Final state: `running`; health: `healthy`. Health probing was corrected from HEAD-style `wget --spider` to GET, and `healthy/running` became an explicit assertion.

## 25. SECURITY RESULTS

No real Icecast or Supabase secrets were committed. Random credentials were masked and absent from evidence (`secret_leak=false`). The container uses a read-only root filesystem, tmpfs log/temp, no-new-privileges, and `127.0.0.1` development binding. Paths reject NUL/newline injection; literals are escaped; subprocesses use argument arrays.

Supabase advisors: security 45 INFO / 0 WARN / 0 ERROR (service-only RLS-without-policy notices); performance 55 INFO / 0 WARN / 0 ERROR. No DDL changed.

## 26. REGRESSION RESULTS

Radio Engine build and 3/3 unit tests passed in the same workflow. Managed DB still has `radio.engine_states`, `radio.now_playing`, `radio.station_leases`, and four radio routines. No Storage/Audio Worker files or schema changed. Supabase currently has zero INTERNAL stations and zero persisted Engine/Now Playing rows, consistent with the CI database-disabled warning.

## 27. REAL VS SIMULATED TESTS

Real: Icecast, Docker health/restart, Liquidsoap, MP3 distribution, six FFmpeg listener instances, delayed join, transitions, zero-listener continuity, source reconnect, mount recovery, soak, and ACK timing.

Not connected: Supabase lease/checkpoint/Now Playing writes inside Actions. Schema/functions were checked read-only; no service secret was added to CI.

No relay, mock distributor, simulated Icecast, external station, or per-listener file playback was used.

## 28. BUGS FOUND AND FIXED

1. Exclusive Icecast config renderer failed because its target was pre-created: changed to a private temp directory and new target.
2. Callback parameter shadowed Liquidsoap metadata module: renamed.
3. Liquidsoap returned empty identity metadata: mapped real boundaries deterministically to the validated normal playlist.
4. Strict mode rejected unused callback data: safely consumed it.
5. HEAD-style Docker probe marked working Icecast unhealthy: changed to GET and asserted final health.

## 29. KNOWN ISSUES

- Managed Supabase playout writes were not exercised by this CI run.
- Development Supabase currently has zero INTERNAL station rows.
- Sequential ACK mapping is correct for the Phase 5 normal loop; Scheduler/manual operations should use immutable request IDs.
- Existing listener sockets cannot survive Icecast restart; Flutter reconnect is deferred.

## 30. WARNINGS

- Keep Icecast admin endpoints private.
- Measured source reconnect was 3.998 seconds; listener audio restoration was 5.255 seconds.
- Third-party GitHub Actions emitted Node runtime deprecation notices; acceptance was unaffected.

## 31. FILES MODIFIED

- `.github/workflows/phase5b-real-icecast.yml`
- `infrastructure/docker-compose.radio.yml`
- `infrastructure/icecast/entrypoint.sh`
- `services/radio-engine/src/{database,engine,health,playlist,source,types}.ts`
- `services/radio-engine/test/real-icecast-e2e.mjs`
- `services/radio-engine/test/state-and-security.test.ts`
- `docs/PHASE5B_REAL_ICECAST_REPORT.md`

## 32. GIT/WORKSPACE STATE

Branch `phase5b-real-icecast`, PR #1. Tested implementation commit: `3bbfcf3260d5638879f42135369f16f4f5e071ff`; documentation follows it. No secrets/artifacts committed. Work scratch is a synchronized copy, not a local Git checkout.

## 33. EXACT NEXT RECOMMENDED PHASE

After approval, start **Phase 6 — Scheduler + Queue Manager + Radio Commands**. First seed/identify the INTERNAL development station and run a protected-secret Engine lease/checkpoint smoke test before ONE_TIME/DAILY/WEEKLY or Play Now/Next.

## 34. ACCEPTANCE CHECKLIST

- [x] Real Icecast and Liquidsoap source.
- [x] Fixed `/tarteel.mp3` and decoded audio.
- [x] Real A/B delayed join and current-position proof.
- [x] Real listener C.
- [x] Two required transitions (90 total).
- [x] Stable mount and zero-listener continuity.
- [x] Real stop/restart and automatic Liquidsoap reconnect.
- [x] Recovery timings and playout ACK accuracy measured.
- [x] No secret leakage.
- [x] Docker `running/healthy`.
- [x] Soak ≥30 minutes (1,807.5 s).
- [x] Engine build/unit regression.
- [ ] Managed Supabase Now Playing write in the same E2E runtime (warning; deferred pending protected CI secret and INTERNAL station).
