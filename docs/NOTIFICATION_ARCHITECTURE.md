# Notification Architecture & Dispatching — Fadhkur (فذكر)

## 1. Single Device Test vs. Broadcast Campaign
- The Next.js Admin interface and Supabase `notifications` Edge Function support:
  - **Single Device Test (`targetType = 'device'`)**: Delivers only to a specific `testInstallationId` for developer verification.
  - **Broadcast Campaign (`targetType = 'all'`)**: Targets active consent installations with revocable tokens.

## 2. Route Allow-List
All notifications must point to an allow-listed destination (`/`, `/home`, `/radio`, `/quran`, `/reciters`, `/library`, `/adhkar`, `/prayer-times`, `/custom-reminders`, `/learning`, `/favorites`, or `/quran/surah/[1-114]`). Every allow-listed route has a matching case in `AppRouter.onGenerateRoute`; unknown routes fall back to `/home`.

### 2.1 Alias normalization (sanitizer)
Before the allow-list check, `sanitizeNotificationRoute` normalizes legacy/shorthand links to canonical routes:
- `/azkar` → `/adhkar`, `/live` → `/radio`, `/prayer` → `/prayer-times`, `/recitations` → `/reciters`
- `/quran?surah=18` → `/quran/surah/18` (query form; invalid surah ids fall back to `/home`)

All delivery paths (terminated cold start via `getInitialMessage`, background via `onMessageOpenedApp`, foreground via `onMessage` → local-notification tap) route through the sanitizer. When the navigator isn't ready yet, the route is stashed as `pendingNotificationRoute` and flushed on the first post-frame callback in `main.dart`.
