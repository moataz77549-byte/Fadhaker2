# REST API Contract

> هذا العقد لمنصة **ترتيل (Tarteel)**؛ لا يغيّر اعتماد الاسم مسارات API المعتمدة.

## 1. Conventions

- Base URLs: `https://api.example.com/api/v1` و`https://api.example.com/admin/api/v1`.
- JSON UTF-8، أسماء الحقول `snake_case`، أوقات RFC 3339 UTC، IDs UUID.
- `X-Request-Id` يولّد/يمرر ويعود في response.
- عمليات الإنشاء الحرجة تتطلب `Idempotency-Key` (uploads, commands, schedule create/duplicate).
- pagination cursor opaque: `?limit=20&cursor=...`; الحد 1–100.
- sorting whitelist فقط؛ search normalized server-side.
- optimistic concurrency للإدارة عبر `ETag`/`If-Match` أو `version`.
- OpenAPI 3.1 هو العقد القابل للتوليد في مرحلة API، و`packages/api-types` يولد منه.

### Success envelope

```json
{
  "data": {},
  "meta": { "request_id": "uuid", "next_cursor": null }
}
```

### Error envelope

```json
{
  "error": {
    "code": "SCHEDULE_CONFLICT",
    "message": "A conflicting event exists.",
    "details": [{ "field": "start_time", "reason": "overlap" }],
    "request_id": "uuid"
  }
}
```

لا يعيد public API stack traces، paths داخلية، object keys خاصة، admin IDs، command payloads، أو health internals.

## 2. Public API

| Method | Endpoint | الغرض | Cache |
|---|---|---|---|
| GET | `/stations` | active stations، filter/search/page | public 60s, stale 5m |
| GET | `/stations/{slug}` | station + stream URLs الآمنة | public 60s |
| GET | `/stations/{slug}/now-playing` | status/current/next/revision | no-store أو 2s |
| GET | `/reciters` | active reciters، search/page | public 10m |
| GET | `/reciters/{id}` | reciter metadata | public 10m |
| GET | `/reciters/{id}/surahs` | active tracks، quality filter | private/public بحسب URL 5m |
| GET | `/surahs` | 114 seed | public 24h, immutable by version |
| GET | `/categories` | public category tree | public 10m |
| GET | `/featured` | curated stations/reciters | public 5m |
| GET | `/app-config` | allowlisted public config only | public 5m |
| GET | `/health` | `{status, timestamp}` فقط | no-store |

### Now Playing

```json
{
  "data": {
    "station": { "id": "uuid", "slug": "quran", "name": "إذاعة القرآن" },
    "status": "ONLINE",
    "mode": "SCHEDULED",
    "revision": 1842,
    "current": {
      "id": "uuid",
      "title": "سورة البقرة",
      "artist": "محمود خليل الحصري",
      "started_at": "2026-08-30T10:00:00Z",
      "duration_ms": 3600000,
      "artwork_url": "https://assets.example.com/..."
    },
    "next": { "title": "أذكار المساء" },
    "updated_at": "2026-08-30T10:00:02Z"
  },
  "meta": { "request_id": "uuid" }
}
```

`started_at` للمعلومة لا يعني أن live stream seekable. Flutter لا يعرض seek bar للمحطة.

### Unified radio catalog

`GET /stations` يدعم `source=INTERNAL|EXTERNAL`, `provider`, `category`, `stream_type`, `health`, `featured`, `q`, cursor. لا يعيد provider raw payload أو internal notes/rights evidence. مثال External:

```json
{
  "id": "uuid",
  "name_ar": "إذاعة ماهر المعيقلي",
  "name_en": "Maher Al-Muaiqly",
  "station_source": "EXTERNAL",
  "stream_type": "SHOUTCAST",
  "category": { "code": "RECITER", "name_ar": "القراء" },
  "playback": { "primary_url": "https://example/stream", "fallback_url": null },
  "health": "HEALTHY",
  "is_live": true,
  "is_featured": false,
  "capabilities": { "managed": false, "now_playing": false, "scheduling": false },
  "attribution": null
}
```

`playback` هو contract قابل لتغيير direct URL إلى token/proxy مستقبلًا. Favorites تستخدم `id`. في production لا يدخل record إلا إذا station/provider active، effective rights approved، production gate true، وسياسة health تسمح. External `/now-playing` يعيد `current=null` وcapability `metadata_available=false` ما لم يوفر provider metadata adapter موثوقًا؛ لا يختلق title.

### On-demand URLs

Public processed Quran audio إما CDN public immutable path أو short-lived signed URL يعيده API. الأصل لا يعود أبدًا. يدعم endpoint/CDN `Range` و`HEAD` لseek. الجودة whitelist، ولا يقبل client object path.

### Search normalization

نسخة مفهرسة غير معروضة: إزالة التشكيل والتطويل، توحيد أ/إ/آ→ا، ى→ي، ة policy موثقة (لا توحد افتراضيًا لتقليل false positives)، whitespace collapse، lowercase للإنجليزية. يحتفظ النص الأصلي للعرض.

## 3. Admin API

كل endpoint يتطلب Supabase access token صالحًا وpermission backend-side.

### Media / Uploads

| Method | Endpoint | Permission |
|---|---|---|
| GET/POST | `/media` | `media.read` / `media.create` |
| GET/PATCH/DELETE | `/media/{id}` | read/update/archive |
| POST | `/uploads` | `media.create`؛ ينشئ upload intent |
| POST | `/uploads/{id}/complete` | يثبت checksum ويبدأ job مرة واحدة |
| GET | `/uploads/{id}` | status/progress/error الآمن |
| POST | `/media/{id}/retry-processing` | `media.process` |
| POST | `/media/{id}/preview-url` | signed preview |

Upload intent يحدد method/headers/max size/object key server-generated. إكمال upload يعيد `202 PROCESSING`. لا يمكن تحويل status إلى READY من الواجهة.

### Playlists / Stations / Catalog

- CRUD `/playlists`, `/playlists/{id}/items`, endpoint reorder transactionally مع `If-Match`.
- CRUD `/stations`؛ تغيير default playlist يتحقق من station ownership وREADY count.
- CRUD `/reciters`, `/reciter-tracks`, `/categories`; `/surahs` read-only بعد seed إلا super-admin migration workflow.
- CRUD `/content-providers` و`/external-stations` بصلاحيات مستقلة، مع provider/category/type/rights/health filters.
- `POST /external-stations/{id}/health-checks` ينشئ job ويعيد `202`؛ `GET /external-stations/{id}/health-checks` يعيد history paginated.
- `POST /content-providers/{id}/sync-runs` يبدأ sync idempotent؛ `GET /content-providers/{id}/sync-runs` يعرض النتائج.
- تغيير rights/production gate يتطلب permission وreason ويولد audit. Response لا يعيد secrets أو internal notes دون صلاحية.
- أي playlist/schedule/radio command يستهدف EXTERNAL يعيد `422 STATION_NOT_MANAGED`؛ الحماية Backend + DB trigger.

### Schedules

- CRUD `/schedules` مع preview/conflict warnings.
- `POST /schedules/preview` يعيد occurrences المحسوبة وDST notes من الخوارزمية نفسها.
- `POST /schedules/{id}/duplicate` idempotent.
- `POST /schedules/{id}/enable|disable` مع optimistic version.
- CRUD/clone/preview/activate `/schedule-templates`؛ التفعيل ينشئ versioned overlay/occurrences ولا يدمر base definitions.

Conflict warning ليس دائمًا منعًا؛ overlap مسموح إذا priorities/policies واضحة. أخطاء target غير READY أو cross-station تمنع الحفظ/التفعيل.

### Radio commands

`POST /radio/commands`:

```json
{
  "station_id": "uuid",
  "command_type": "PLAY_NOW",
  "target": { "type": "MEDIA", "id": "uuid" },
  "interrupt_policy": "INTERRUPT",
  "priority": "HIGH",
  "reason": "Operator request"
}
```

Phase 6 يثبت أن API المستقبلي ينشئ command فقط. لا يعيد endpoint path أو URL أو Liquidsoap command. payload الطبيعي هو `{media_id}` أو `{playlist_id}` مع `interrupt` boolean لـPLAY_NOW، ويُرفض الجمع بين targetين. `Idempotency-Key` فريد داخل station؛ polling يعرض PENDING/PROCESSING/COMPLETED/FAILED/CANCELLED وresult آمنًا فقط.

Response `202` مع command resource. لا ينتظر HTTP بدء الصوت. العميل يتابع `GET /radio/commands/{id}`. `CANCEL` مسموح لـPENDING فقط. Commands `START_LIVE/STOP_LIVE` محفوظة بالschema لكن endpoints/UI غير مفعلة في MVP.

### Dashboard / Analytics / Settings

- `GET /dashboard?station_id=` projection يجمع health/now/next/listeners/recent/upcoming.
- `GET /analytics` aggregates فقط مع range limits.
- `GET /health/details` permission `system.health.read`.
- CRUD `/administrators`, `/roles` بصلاحيات super-admin ومنع self-lockout transactionally.
- `/settings` لا يعيد secrets؛ يعيد حالة configured فقط.
- Dashboard external section يعرض provider sync health، unhealthy counts، last checks، fallback usage، rights review queue؛ منفصل عن Engine/Icecast health.

## 4. Validation and status codes

| Code | الاستخدام |
|---|---|
| 200/201 | نجاح sync/create |
| 202 | command/job accepted |
| 204 | archive/cancel بلا body |
| 400 | malformed request |
| 401 | missing/invalid auth |
| 403 | authenticated but forbidden |
| 404 | غير موجود أو مخفي لمنع enumeration |
| 409 | version/idempotency semantic conflict |
| 412 | `If-Match` قديم |
| 422 | domain validation (not READY/cross-station) |
| 429 | rate limited + `Retry-After` |
| 503 | dependency unavailable؛ public may serve stale cache |

## 5. Caching and resilience

- ETag للcatalog/config؛ Cache-Control مختلف حسب الجدول أعلاه.
- Now Playing revision monotonic؛ يمكن Flutter تجاهل response أقدم.
- API timeouts قصيرة وbounded، DB pool منفصل عن workers.
- Public catalog يدعم stale cache عند DB outage؛ admin writes تفشل بوضوح ولا تُخزن client-side لإعادة غامضة.
- rate limits منفصلة: public read، auth، upload intent، command mutation.
- provider sync/health actions تستخدم job queue وper-provider concurrency؛ لا تنفذ network probe داخل request thread.

## 6. Dependencies / Risks

- signed URL expiry يجب أن يتجاوز بدء playback المتوقع دون أن يكون طويلًا بلا حاجة.
- cursor يتضمن sort/filter fingerprint حتى لا يُعاد استخدامه مع query مختلفة.
- Now Playing lag يخفض بالدفع لاحقًا، لكن MVP polling 5–10s كافٍ ولا يعتمد correctness على Realtime.
- Direct external URLs قد تتغير/تعمل redirects؛ DTO يبقى stable بالـstation ID، والـAPI cache يُبطل عند URL/health/rights change.
- OpenAPI/types generation قد يسبب drift إن كتب يدويًا؛ CI يمنع uncommitted generated diff.

## 7. Acceptance Criteria

- OpenAPI في مرحلة التنفيذ يغطي كل endpoint هنا ويجتاز contract tests.
- anon لا يستطيع الوصول لأي admin route أو internal table.
- كل command/upload retry بالمفتاح نفسه يعيد resource نفسه.
- API لا يكشف original paths أو health secrets.
- now-playing يتغير فقط بعد playout ACK ويقبل out-of-order protection بالrevision.
- Provider جديد أو URL/category/disable يتغير بلا Flutter release، وproduction لا يعرض restricted/unapproved sources.
