# Cloud & Backend Mapping Architecture — Fadhkur (فذكر)

This document establishes the unified pipeline connecting the user interfaces (Flutter Client / Next.js Admin) to Supabase Database Tables, RPC functions, Storage Buckets, and Firebase cloud services.

```
┌─────────────────┐       ┌────────────────────────┐       ┌───────────────────────┐
│ Flutter Client  │ ────► │ Supabase Edge API      │ ────► │ Supabase Postgres     │
│ & Admin Web     │       │ (/fadhkur-api)     │       │ Schemas: app & radio  │
└─────────────────┘       └────────────────────────┘       └───────────────────────┘
         │                            │                                │
         ▼                            ▼                                ▼
┌─────────────────┐       ┌────────────────────────┐       ┌───────────────────────┐
│ Firebase FCM    │       │ Private Storage        │       │ Audio & Radio Workers │
│ Messaging v1    │       │ 8 Specialized Buckets  │       │ (Liquidsoap / Icecast)│
└─────────────────┘       └────────────────────────┘       └───────────────────────┘
```

---

## Detailed Mapping Matrix

| Frontend Feature / Screen | Client Protocol / RPC / REST | Database Table(s) / RPC | Storage Bucket | Firebase / External Cloud Service |
| :--- | :--- | :--- | :--- | :--- |
| **Home Dashboard (الرئيسية)** | `GET /home` | `app.get_public_home()` / `app.app_config`, `radio.now_playing` | `reciter-artwork`, `station-artwork` | N/A (Offline Solar Calculation for Prayer Times) |
| **Reciters Directory (دليل القراء)** | `GET /reciters` | `app.reciters`, `app.reciter_provider_mappings` | `reciter-artwork` | Official King Fahd Complex / Cairo Archive CDN |
| **Reciter Audio Tracks (المصحف الصوتي)** | `GET /reciters/:id/tracks` | `app.quran_audio_tracks` | `media-source-private`, `media-processed-private` | Audio Worker (EBU R128 -16.0 LUFS) |
| **Quran Text & Pages (المصحف)** | `GET /quran/surahs`, `GET /quran/page/:n` | `app.quran_surahs`, `app.quran_ayahs`, `app.quran_pages` | `quran-mushaf` (`editions/madinah-hafs/v1/`) | Manifest verification (SHA-256) |
| **Live Virtual Radio (الإذاعة المدارة)** | `GET /stations`, Icecast Stream | `radio.stations`, `radio.now_playing`, `radio.play_history` | `media-processed-private` | Icecast 2 Mounts (`/live/khashia.mp3`, `/live/murattal.mp3`) |
| **External Radio (المحطات الخارجية)** | `GET /stations` (`source_type='external'`) | `app.stations`, `app.external_sources` | `station-artwork` | Direct Source URL streaming (Cairo / Mecca) |
| **Favorites & Playlists (المفضلة)** | RPC / Direct Client Store | `app.favorites`, `app.playlists`, `app.playlist_items` | N/A | Sync via `installation_id` (Zero Auth required) |
| **Playback History (سجل الاستماع)** | REST `POST /playback/history` | `app.playback_history` | N/A | Anonymized device state |
| **Opt-in Notifications (الإشعارات)** | `POST /installations/register` | `app.installations`, `app.notification_preferences` | N/A | **Firebase Cloud Messaging (FCM v1)** |
| **Admin Campaigns (حملات الإشعارات)** | Admin `POST /notifications/send` | `app.notification_campaigns`, `app.notification_deliveries` | N/A | **Firebase Admin SDK (FCM HTTP v1 API)** |
| **Media Ingestion (معالجة الصوت)** | Admin Upload & Worker Claim | `app.media_assets`, `app.processing_jobs` | `media-source-private` ➔ `media-processed-private` | Node/TypeScript Audio Worker with FFmpeg |
| **Radio Playout Queue (محرك البث)** | Scheduler Loop & Fencing | `radio.schedules`, `radio.schedule_occurrences`, `radio.queue_entries` | `media-processed-private` | Liquidsoap 2.2 Playout Engine |
| **App Remote Config & Flags** | `GET /config` | `app.app_config`, `app.announcements` | `app-content` | Anti-code-injection JSON Sanitizer |
| **Audit & Security Logs** | Auto-trigger on Mutations | `app.audit_logs`, `app.system_logs` | `exports-private` | Immutable Append-Only Audit Trail |

---

## 8 Specialized Storage Buckets Specification

| Bucket Name | Access Level | Permitted Operations | Description & Contents |
| :--- | :--- | :--- | :--- |
| `quran-mushaf` | **Public Read** | Admin / Service Role write only | High-resolution Medina Mushaf WebP pages & checksum manifest |
| `reciter-artwork` | **Public Read** | Admin / Service Role write only | Verified portrait avatars and visual cards of Quran reciters |
| `station-artwork` | **Public Read** | Admin / Service Role write only | Logos and station cover art for internal and external radio feeds |
| `app-content` | **Public Read** | Admin write only | Structured Islamic library, Adhkar, and Fortress of the Muslim JSON |
| `media-source-private` | **PRIVATE** | Service Role / Admin only | Raw, un-normalized master audio recordings owned by the platform |
| `media-processed-private` | **PRIVATE** | Service Role (Audio Worker / Radio Engine) | Transcoded 128/192 kbps MP3 files normalized to -16.0 LUFS EBU R128 |
| `admin-uploads-private` | **PRIVATE** | Authenticated Admins only | Temporary staging space for incoming files prior to validation |
| `exports-private` | **PRIVATE** | Authenticated Admins only | Administrative exports, compliance dumps, and audit reports |
