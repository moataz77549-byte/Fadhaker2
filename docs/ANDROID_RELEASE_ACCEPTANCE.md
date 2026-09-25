# Android Release Acceptance & Quality Checklist

## 1. Release identity
- **App Name (Arabic):** فذكر
- **App Name (English):** Fadhkur
- **Application ID:** `app.fadhkur`
- **Release candidate:** `1.0.68+68`
- **Minimum SDK:** 26 — Android 8.0+
- **Target SDK:** 36
- **Compile SDK:** 36
- **Release APK ABI:** `arm64-v8a` only
- **Java/Kotlin target:** 17
- **Flutter:** 3.35.7

## 2. Production configuration
- Supabase URL is injected as a production dart-define.
- Supabase publishable key is injected from GitHub Actions Secrets.
- Firebase Android configuration must match project `fadhkur-2f78c` and package `app.fadhkur`.
- Firebase Admin credentials never enter Flutter, APK/AAB, repository source, or dart-defines.
- Release signing material is read only from GitHub Actions Secrets.

## 3. Audio & Android runtime
- Background playback uses `audio_service` + Android MediaSession.
- Lock-screen/media notification supports play, pause and stop.
- Live radio starts without blocking the caller for the lifetime of the stream.
- Radio failover can switch to an alternate HTTPS source.
- Smart Radio refresh never takes audio focus back after the user manually chooses another source.
- Sleep timer and playback controls remain available.

## 4. Smart Fadhkur Radio
- Personalized virtual channel: `fadhkur-smart`.
- Prayer-aware rules use local prayer times and IANA timezone.
- Precise latitude/longitude is rejected by the resolver.
- Admin rules/sources/overrides are not directly readable by `anon`.
- Manual overrides are time-bounded.
- Database audit triggers record Smart Radio administrative changes.
- Resolver filters source health and rights/provenance before playback.
- Client caches the last successful resolution for continuity.
- Built-in radio fallback remains available when the backend cannot resolve.

## 5. Quran/content integrity
- Canonical 114-surah metadata remains covered by tests.
- Downloaded Quran audio uses disk streaming/recovery paths rather than whole-file memory loading.
- Imported QuranEnc/HadeethEnc content remains gated by provider rights/version rules.
- No source is made production-eligible merely to fill an empty UI.

## 6. Privacy & permissions
- No background location tracking is introduced by Smart Radio.
- Smart Radio sends prayer times/timezone, not precise coordinates.
- Android 13+ notification permission follows the runtime permission flow.
- Unused microphone permission and obsolete cleartext HTTP exceptions are removed.

## 7. Release build gates
The production workflow must pass all of the following before publication:

1. Admin TypeScript typecheck.
2. Provider + Smart Radio contract tests.
3. `flutter analyze --no-fatal-infos`.
4. `flutter test`.
5. Signed release APK build.
6. Packaged manifest confirms `minSdk 26` and `targetSdk 36`.
7. APK contains `arm64-v8a` native libraries only.
8. `apksigner verify --verbose --print-certs` succeeds.
9. SHA-256 checksum is generated and published with the APK.

A release must not be described as verified until these gates have actually executed successfully.
