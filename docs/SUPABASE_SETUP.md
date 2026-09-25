# Supabase Setup & Architecture Guide — Fadhkur (فذكر)

## 1. Overview
Fadhkur utilizes a multi-schema PostgreSQL database managed by Supabase:
- **`app` Schema**: Application profiles, reciters, providers, Quran canonical datasets, stations, playlists, installations, announcements, and configuration.
- **`radio` Schema**: Managed playout engines, schedules, occurrences, queue entries, and playback events.

## 2. Row Level Security (RLS)
- 43 distinct tables actively enforce RLS.
- Public read access is strictly filtered to active rows (`is_active = true`).
- Write operations for administrative mutations require `app.admin_has_permission(permission_key)`.
- Backend workers (Audio Worker, Radio Engine) operate under `service_role` authorization.

## 3. Storage Architecture
8 purpose-built buckets provide clean segregation between public assets and internal media masters.
