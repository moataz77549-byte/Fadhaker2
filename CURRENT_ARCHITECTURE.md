# Current Architecture — Fadhkur (فذكر)

## Overview & Target Identity
Fadhkur is an Arabic-first, sovereign, production-grade Holy Quran and Curated 24/7 Virtual Radio platform.

- **Brand Colors**: Deep Indigo (`#243B6B`), Acoustic Teal (`#2E9E9E`), Copper Accent (`#C77955`), Pearl White Canvas (`#F8F6F1`).
- **Target App ID**: `com.aistudio.fadhkur.live`
- **Primary Production Backend**: Supabase (PostgreSQL 15+, RLS, Edge Functions, Storage).
- **Audio Standards**: EBU R128 (-16.0 LUFS) normalization, 128 kbps (Radio) / 192 kbps (Recitations), SHA-256 asset verification.
- **Fail-Closed Policy**: If dataset checksums or record counts do not match the verified baseline (114 Surahs, 6236 Ayahs), deployment aborts and API rejects execution.

---

## Structural Topology & Schemas

### 1. `app` Schema
Handles domain entities, administrative RBAC, metadata, remote configurations, and notification consent.
- `app.permissions` & `app.roles`: Granular permissions (`dashboard.read`, `radio.control`, `media.write`, etc.).
- `app.administrators`: Membership mapped to authenticated Supabase users.
- `app.providers`: Verified institutional content owners (King Fahd Complex, Cairo Radio Archive, Haramain).
- `app.reciters`: Normalized reciter identities.
- `app.quran_surahs` & `app.quran_ayahs`: Immutable canonical Uthmanic text.
- `app.audio_tracks`: Verified audio files with provenance and SHA-256.
- `app.app_config`: Sanitized runtime configuration without script or eval fields.
- `app.notification_installations`: Privacy-first notification subscriptions.
- `app.audit_logs`: Immutable tracking of administrative modifications.

### 2. `radio` Schema
Powers the 24/7 curated virtual radio streams.
- `radio.stations`: Stream URLs, fallback endpoints, and bitrates.
- `radio.now_playing`: Live track metadata, listeners count, and duration.
- `radio.play_history`: Historical playback log.
- `radio.engine_state`: Liquidsoap / Icecast cluster synchronization.

---

## Public Edge API Contracts (`fadhkur-api`)
- `GET /health`: Engine status, version, and canonical Quran edition.
- `GET /runtime-config`: Feature flags and allowed public keys.
- `GET /home`: Daily reading recommendation, featured radio, and prayer times.
- `GET /stations`: List of managed radio stations with fallback failover.
- `GET /reciters`: Normalized reciters directory with biographies.
- `GET /quran/surahs`: Canonical 114 Surahs index.
- `GET /quran/page/:page`: Uthmanic page representation (1 to 604).
- `POST /notifications/register`: Installation registration with consent evidence.
- `POST /notifications/revoke`: Immediate revocation and metadata obfuscation.
