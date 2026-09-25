# Islamic content source integration — live status

Audit and implementation date: 2026-09-25. This inventory is **not** a rights approval.
Evidence: `main` at `10b1490`, deployed Supabase project `ttvasynaxkkcwrmvlorg`,
`app.content_providers`, `app.content_sources`, and current table inventory.
Recheck the live schema and source terms before further import.

| Source | State | Existing implementation / gap | Production decision |
| --- | --- | --- | --- |
| Quran Foundation | PARTIALLY_INTEGRATED | `quran-yutla-api` OAuth proxy, Flutter Quran reader, tafsir and page routes; no verified server content sync | Preserve canonical text; extend this proxy only after terms review |
| KFGQPC / Medina Mushaf | PARTIALLY_INTEGRATED | 604-page reader and `docs/MUSHAF_SOURCES.md`; some images/fonts are delivered by third-party mirrors with conflicting or unverified licensing | Do not claim the mirror's license is the Complex's license |
| Tanzil | PARTIALLY_INTEGRATED | Reference catalog row in `app.content_sources`; no verified comparison job against canonical checksums | Verification only; no automatic canonical writes |
| QuranEnc | PARTIALLY_INTEGRATED | Source metadata row, but no translation table, import, or selection UI found | No production ingestion yet |
| HadeethEnc | PARTIALLY_INTEGRATED | Source metadata row; daily hadith uses local Nawawi collection; no database hadith corpus found | Keep offline Nawawi fallback; no bulk import yet |
| Dorar | NOT_INTEGRATED | No production adapter or verified terms found | Search/reference only after API and terms review |
| MP3Quran | PARTIALLY_INTEGRATED | Existing `app.content_providers` row, reciter/provider mapping tables, station catalog and 174 active station rows | Provider remains `REVIEW_REQUIRED`, `production_enabled=false` for other datasets; official API radio links explicitly authorized by the owner |
| IslamHouse | NOT_INTEGRATED | No verified curated import or provider row found | Wait for item-specific provenance and rights review |
| Hisn Al-Muslim | UNSAFE_OR_UNVERIFIED | `app.adhkar` exists but has zero rows; existing third-party dhikr catalog entries do not establish Hisn provenance | No unverified seed content |

## Station access and owner authorization

Migration `20260924230458_provider_station_rights_gate.sql` first closed the
previously unguarded public catalog. After the owner explicitly authorized
linking documented API stations, `20260924231017_owner_approved_mp3quran_api_radio_links.sql`
added a separate, narrow `api_stream_links_enabled` flag. The final RLS
policy in `20260924231156_radio_provider_rights_private_helper.sql`
exposes only healthy, playable MP3Quran stations with an external key and
the exact official radio catalog URL. Anonymous reads now return 174 rows.
It does not authorize audio copying, rehosting, other API datasets, or
commercial redistribution; those fields remain `REVIEW_REQUIRED / UNKNOWN`
and `production_enabled=false`. The intermediate column-privilege fix
migration is retained because it was applied, although the final policy uses
a narrowly scoped helper in the private schema instead.

The owner authorization is recorded as an application scope decision, not as
an assertion that MP3Quran published a general commercial license. The
official [developer API](https://www.mp3quran.net/ar/api) documents radio
catalog URLs. The existing Settings → About screen now names active sources
and distinguishes them from sources awaiting integration.

## Next implementation gates

1. Review actual provider terms, attribution, and item-level provenance; record a
   dated decision before any `production_enabled` change.
2. Inspect current migrations and live columns for translations, hadith, and media;
   create append-only schema changes only for verified gaps.
3. Build bounded sample adapters behind the existing `provider-sync`, validate
   pagination, hashing, duplicate handling, failures, and RLS; then backfill.
4. Add Flutter/Admin screens against the unified backend and test offline fallback.
5. Run Quran checksum gate, provider tests, Flutter analysis/tests and a signed
   arm64 APK build with Android `minSdk=26`. Do not issue a release before those
   gates pass.

## Implementation update — 2026-09-25

The earlier matrix above records the **pre-implementation audit**, and its descriptions
of missing QuranEnc and HadeethEnc tables are historical. The integration branch now
contains append-only migrations `20260925010000_islamic_content_catalog.sql` and
`20260925011000_arabic_content_search.sql`; both were applied to the live project.
The existing `provider-sync` function has bounded QuranEnc and HadeethEnc adapters,
rate-limit handling, sync state, source identity, content hashes, and administrative
authorization. Seven QuranEnc verses and two HadeethEnc Arabic hadith records were
sampled; these are inactive and the public role sees zero of them. No bulk backfill
or rights approval is implied. The mobile translation and hadith catalog UIs cannot
present these sample rows to the public until provenance review and rights activation.

The existing MP3Quran provider remains unapproved for general content, with the
narrow owner-authorized official API station link exception. The smart station
`fadhkur-smart` reuses `app.stations`: 14 program rules and 43 station references
were present in production at the time of inspection. Its resolver returned HTTP
200 for a Friday test context and chose the Friday program; the client falls back
to builtin radio when resolution fails. A broadcast link is not a license to copy,
redistribute or rehost a recording.

IslamHouse has no configured verified API key or item-level review; keep it disabled.
Hisn Al-Muslim items require authenticated text and references before import. Tanzil
is for integrity comparison only; canonical Quran writes remain blocked. Dorar is
for reference/search after an approved access path is documented. No fabricated
content or license approval is part of this update.

Before a signed Android release, GitHub Actions must execute its jobs, Flutter
analysis/tests and Quran checksum gate must pass, Android signing material must be
available, and Firebase server credentials must be installed and exercised. The
observed PR runs currently fail before any job step starts, so a release cannot
truthfully be certified yet.

## Prayer engine and radio scheduling

Offline Adhan alarms are calculated locally from device coordinates and the
user-selected calculation method. The smart radio consumes the existing
`PrayerTimesService` schedule; its remote schedule calls now map the same
method choice to AlAdhan method IDs (Umm al-Qura 4, MWL 3, Egyptian 5,
Karachi 1). The API schedule still needs an online request, so builtin radio
is the continuity fallback. A production resolver request returned the
Friday program with HTTP 200. The Adhan alarm is scheduled locally and is
never inserted into a radio stream. Missing Android exact-alarm permission
now causes scheduling to fail visibly instead of showing a false success.
The mobile prayer timetable and remote schedule should be checked together on
real devices and across location/timezone transitions before final release.
