# Radio Commands — Phase 6

## Boundary

المسار الوحيد: trusted Admin API مستقبلًا → `radio.radio_commands` → fenced Engine claim → command effect ledger → Queue Manager → Liquidsoap. `anon` و`authenticated` لا يملكان usage/grants على `radio`، ولا توجد shell arguments أو object paths في payload.

| Command | Effect | Mode/result |
|---|---|---|
| PLAY_NOW media/playlist | FINISH_CURRENT افتراضيًا، أو INTERRUPT صريح | MANUAL ثم re-arbitrate |
| PLAY_NEXT | deterministic sequence بعد current | MANUAL أثناء المحتوى |
| SKIP | clean hard boundary، يسجل السبب | next decision |
| STOP_AFTER_CURRENT | operator STOP بعد boundary | STOPPED متعمد؛ ليس failure |
| RESUME_AUTO | يلغي manual pending ويعيد التحكيم | AUTO أو SCHEDULED |
| START_LIVE / STOP_LIVE | محجوزان | deferred؛ لا microphone في Phase 6 |

Payload يقبل internal `media_id` أو `playlist_id` واحدًا فقط. resolver يرفض EXTERNAL station، media غير READY، playlist من محطة أخرى، target غير active، أو payload مبهم.

## Lifecycle وIdempotency

`PENDING → PROCESSING → COMPLETED|FAILED`، و`CANCELLED` قبل claim. `(station_id,idempotency_key)` فريد. `claim_radio_command` يستخدم `FOR UPDATE SKIP LOCKED` وترتيبًا ثابتًا. `radio.command_effects` يسجل PREPARED/DISPATCHED/ACKED، مع command فريد وSHA-256 ثابت للpayload. هذا يمنع إعادة SKIP/interrupt عمياء بعد crash.

المحرك الذي فقد lease لا يستطيع claim أو enqueue أو complete أو ACK. تحرير lease يبقي صفه منتهيًا بدل حذفه، لذلك fencing token يزداد ولا يعاد استخدامه.

## Recovery

- PROCESSING بلا queue/effect من token أقدم يعاد PENDING.
- وجود effect/queue يعني reconciliation، لا replay.
- completion مكرر يعيد `false` ولا يكرر event.
- PLAY_NOW نجح صوتيًا ثم crash: Liquidsoap ACK/`playout_id` وeffect ledger يحسمان النتيجة.
- retry النهائي يحتاج command جديدًا ومفتاحًا جديدًا؛ لا infinite retry.
