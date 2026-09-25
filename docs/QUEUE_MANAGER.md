# Queue Manager — Phase 6

Queue Manager هو الحكم الوحيد لاختيار المحتوى للمحطات `INTERNAL`. لا يكتب Scheduler أو API مباشرة إلى Liquidsoap. الحالة التجارية تحفظ في PostgreSQL (`radio.queue_entries`)؛ buffer الصوتي يبقى داخل Liquidsoap ولا ينسخ إلى DB.

## Lanes والقرار

| Lane | الاستخدام | الاستمرارية |
|---|---|---|
| CURRENT | العنصر الذي بدأ وفق Liquidsoap ACK | history + now playing |
| MANUAL | PLAY_NOW / PLAY_NEXT | persistent queue entry |
| SCHEDULED | occurrence فائزة | occurrence + queue entry |
| AUTO | Default Playlist | cursor/checkpoint |
| FALLBACK | fixture آمنة عند تعذر AUTO | event + alert |

المفتاح الكلي: `priority rank DESC → source rank DESC → intended_at ASC → created_at ASC → sequence ASC → UUID ASC`. رتب الأولوية صريحة: LIVE=50، EMERGENCY=40، HIGH=30، NORMAL=20، LOW=10. وعند تساويها: LIVE، EMERGENCY، MANUAL، SCHEDULED، AUTO، FALLBACK.

عند boundary يختار أعلى pending صالح، وإلا يكمل Default Playlist دائريًا، ثم fallback. `INTERRUPT` وحده يسمح بقرار قبل boundary؛ `PLAY_NEXT` و`FINISH_CURRENT` ينتظران. لا crossfade ولا overlap ولا tempo/pitch/trimming.

## Persistence وRecovery

- `(station_id,idempotency_key)` يمنع mutation مكررة.
- claim وكل ACK يحملان fencing token صالحًا.
- `DISPATCHED` من token قديم يعاد `PENDING` فقط بواسطة `recover_stale_automation`.
- ACK متكرر يستخدم `playout_id` نفسه، فلا ينشئ history جديدًا.
- `record_playout_start` هو لحظة تحديث Now Playing؛ enqueue ليس تشغيلًا.
- item فاشل يصبح FAILED، ثم يعاد التحكيم؛ playlist فارغة تنتقل fallback.

## Liquidsoap control

Liquidsoap يبقى process مستمرًا. Default Playlist تبقى source `main`، والقرارات المجدولة/اليدوية تدخل `request.queue(id="automation")`. المقاطعة ترسل `main.skip` أو `automation.skip` إلى المصدر النشط فقط. command server مربوط حصريًا بـ`127.0.0.1`؛ أسماء الأوامر allowlisted نصيًا، والوسيط يرفض NUL/CR/LF، ولا يقبل shell/URL من payload، كما يعتبر رد الرفض runtime failure.

## Acceptance

Unit tests تغطي loop/fallback، priorities، PLAY_NEXT، interrupt، stop/resume، duplicate mutations. SQL validation يغطي idempotency، fencing، conflict loser، ACK/history. الاختبار الحقيقي عبر Icecast موثق في artifact Phase 6.
