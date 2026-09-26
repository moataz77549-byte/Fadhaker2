# Quran reader beta.3 audit

Date: 2026-09-26. This is a source and live endpoint audit, not a device acceptance certificate.

## Implemented in the Flutter application

- Four modes (`madani`, `tajweed`, `thematic`, `text`) use the same page view and persisted `QuranLocation`.
- The Madani renderer uses QCF word and line metadata when returned by the service; otherwise it clearly falls back to Uthmani text. Tajweed markup uses source tags. The thematic layer stores topic and verse relations separately from Quran text.
- Page text is cached in bounded SQLite storage (180 pages); topic records are stored in a separate SQLite database after first sync. Existing bookmarks and reading progress remain in SharedPreferences. No destructive user-data migration is used.
- Search distinguishes text and topic matches. Verse actions reuse the application audio service.
- Explicit surah, deep-link, and bookmark destinations now override older saved progress on first open; later mode changes restore the current saved verse. Cached topic data remains readable when a refresh fails.
- The Android release workflow checks Flutter analysis/tests, APK ABI, packaged minSdk 26, and APK signature before publishing.

## Verified during this audit

- Canonical dataset: 114 surahs, 6236 verses, checksum validated.
- Backend lookup `2:255` returned page 42. Live page 1 returned 7 verses and page 604 returned 15 verses, ending at `114:6`.
- Live topic endpoint returned 6100 records. The Edge Function was active.
- Local Node mapping tests: 3 passed. Flutter tests and Android device tests require the GitHub build environment or actual devices.

## Remaining acceptance gaps

- The live page endpoint currently identifies its response source as `alquran-cloud`. It does not provide QCF word/line data in that fallback response, so exact Madani line layout is **not verified**. Quran Foundation credentials and service response must be checked in the protected backend configuration; never add secrets to the APK.
- The Android 8, recent Android, low-memory, rotation, offline-first-install, dark-theme contrast, rapid paging, and playback interaction scenarios still need device acceptance testing. Automated preference and mapping tests do not establish these outcomes.
- Flutter uses `sqflite` and `shared_preferences`, so Android Room and DataStore are not applicable to this codebase. Replacing them solely to match an Android-specific design would duplicate storage.
- Quranpedia attribution is shown in the application. Confirm the provider's current redistribution and offline-cache terms with the provider before treating the topic dataset as redistributable outside its API.
- APK size cannot be attributed solely to the Quran change because the previous beta also included audio and other app changes. Compare release artifacts under the same build conditions before claiming a reduction.
