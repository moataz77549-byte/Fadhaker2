# Scheduler Design

## 1. المسؤولية والحدود

Scheduler يحول تعريفات `ONE_TIME`, `DAILY`, `WEEKLY` إلى occurrences UTC ثابتة. لا يشغّل الصوت ولا يرسل FFmpeg commands؛ يقدّم occurrences المستحقة إلى Queue Manager. قاعدة البيانات هي ledger، وخوارزمية حساب المواعيد pure ومشتركة بين preview والتنفيذ.

Scheduler يقبل `INTERNAL` stations فقط. EXTERNAL stations موجودة في radio catalog ولا تملك schedule aggregates؛ API وDB trigger يرفضان أي محاولة cross-boundary.

## 2. نموذج الوقت

- schedule يحتفظ بـ`start_date`, `end_date`, `start_time`, `timezone` بصيغة IANA، و`days_of_week` عند WEEKLY.
- timezone نسخة ثابتة داخل schedule؛ تغيير timezone المحطة لا يعيد تفسير schedules القائمة ضمنيًا.
- occurrence يحتفظ بـ`scheduled_for timestamptz` ونسخة القيم المحلية و`fold`.
- timers القصيرة monotonic، أما eligibility فتستخدم DB UTC time، لا server local clock.

## 3. Materialization algorithm

```text
tick every 1 second:
  require valid station lease and fencing token
  read enabled definitions whose next_run_at enters 24h lookahead
  for each local date matching type/date/day constraints:
    resolve local date+time in schedule timezone
    apply DST policy and compute fold
    build occurrence_key(schedule_id, schedule_version, local tuple, fold)
    INSERT occurrence ON CONFLICT DO NOTHING
  advance next_run_at in the same transaction
  claim due rows using FOR UPDATE SKIP LOCKED
  revalidate enabled/version/target ownership/media readiness
  submit valid candidates to deterministic arbiter
```

Lookahead 24 ساعة وtick ثانية قيم ابتدائية قابلة للضبط. `schedule_occurrences` unique key يجعل replay/restart آمنًا. Realtime notification يمكن أن يوقظ loop لكنه ليس correctness path.

## 4. قواعد الأنواع

| النوع | القاعدة | بعد النهاية |
|---|---|---|
| ONE_TIME | تاريخ ووقت محلي واحد، بلا days_of_week | يعطل بعد terminal occurrence |
| DAILY | كل يوم بين start/end، أو بلا نهاية | يحسب اليوم التالي محليًا |
| WEEKLY | الأيام المحددة فقط بين start/end | يحسب أقرب يوم مطابق |

`end_date` inclusive. schedule disabled لا يولد occurrences جديدة؛ future PENDING occurrences الخاصة بنسخته تصبح `CANCELLED/DISABLED`. occurrence بدأ بالفعل لا يوقف تلقائيًا؛ يحتاج command/policy صريحة.

## 5. DST وTimezone

- وقت غير موجود في spring-forward: ينتقل لأول وقت صالح بعد الفجوة ويسجل `DST_SHIFTED_FORWARD`.
- وقت مكرر في fall-back: أول occurrence فقط (`fold=0`) افتراضيًا.
- timezone identifier غير صالح يرفض عند API/DB validation.
- تحديث timezone schedule عملية versioned، تلغي future PENDING وتعيد materialization؛ لا تعدل history.
- test matrix تشمل مناطق بلا DST، نصف ساعة، spring/fall، year boundary، leap day، midnight.

## 6. Missed schedules وrestart

| الحالة | القرار |
|---|---|
| تأخر ≤120 ثانية | due ضمن `late_grace` ويطبق policy |
| أقدم من grace | `SKIPPED/LATE` |
| EMERGENCY وله `valid_until` صالح | يبقى candidate حتى انتهاء النافذة |
| restart قصير | occurrences موجودة تُطالب بعد lease recovery |
| restart تجاوز lookahead | backfill bounded ثم late rules؛ لا replay غير محدود |

قيمة 120 ثانية تحتاج اعتمادًا. كل skip له reason/event؛ لا يختفي موعد بصمت.

## 7. Conflicts وPriority

المفتاح الكلي:

```text
(priority_rank DESC, source_rank DESC,
 intended_start_at ASC, created_at ASC, stable_uuid ASC)
```

`LIVE > EMERGENCY > HIGH > NORMAL > LOW`. عند تساوي الأولوية: authorized live، ثم interrupt command، ثم schedule، ثم manual-next، ثم default؛ بعدها أقدم وقت مقصود، ثم أقدم إنشاء، ثم UUID ثابت. النتيجة لا تعتمد ترتيب query.

Loser صالح النافذة يبقى/defer حسب policy؛ وإلا `SKIPPED/CONFLICT`. `FINISH_CURRENT` يعيد التحكيم عند boundary ولا يحجز المستقبل بصورة تمنع حدثًا أعلى.

## 8. Concurrency وIdempotency

- leader واحد لكل station عبر lease/fencing.
- claim بـ`FOR UPDATE SKIP LOCKED`.
- unique occurrence key يمنع duplicate materialization.
- stale claim يعاد فقط بعد reconciliation مع play history/current correlation.
- schedule edit يزيد version؛ worker يرفض occurrence من version ملغاة قبل البدء.

## 9. Dependencies والمخاطر

- يعتمد على schema/leases/Queue arbiter وIANA tz database pinned في runtime.
- خطر tz database update: تسجل runtime tzdata version، ولا تعيد كتابة materialized occurrences تلقائيًا.
- خطر long track مع FINISH_CURRENT: schedule قد يبدأ متأخرًا؛ preview يعرض worst-case والواجهة تحذر.
- خطر clock skew: NTP alert + DB time + monotonic timers.

## 10. Acceptance Criteria والاختبارات

- unit/property tests لكل نوع عبر 20+ timezones.
- duplicate ticks/restart لا ينشئان occurrence إضافية.
- enable/disable/edit لا يشغل version قديمة.
- تعارضات متطابقة تعطي winner نفسه عبر 1000 permutations.
- missed/restart/DST لها expected events وأسباب skip.
- preview يطابق occurrences الفعلية byte-for-byte للمدخل نفسه.

## 11. Phase 6 implementation record

التنفيذ موجود في `services/radio-engine/src/scheduler.ts` و`scheduler-loop.ts`. يستخدم `Intl` مع IANA timezone دون Server Local Time. وقت DST غير الموجود ينتقل لأول دقيقة صالحة ويسجل `dst_shifted=true`؛ الوقت المكرر ينفذ مرة واحدة في fold 0. ONE_TIME/DAILY/WEEKLY تولد occurrence key versioned وفريدًا.

القيم الافتراضية القابلة للتهيئة: poll=5s، lookahead=120s، missed grace=120s. claim يستخدم DB time/fencing/`SKIP LOCKED`. exact-time conflicts يحسمها priority ثم schedule creation ثم UUID؛ الخاسر `SKIPPED/CONFLICT_LOST` ولا يشغل لاحقًا. الأقدم من grace يصبح `SKIPPED/MISSED` مع event. لا يتكرر occurrence مكتمل بعد restart.

الاختبارات الفعلية تشمل Asia/Aden، day/week boundaries، multiple weekdays، America/New_York spring gap/fall fold، disabled/future، grace boundary، SQL conflict/idempotency/fencing.
