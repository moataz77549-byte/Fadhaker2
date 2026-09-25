# Engineering Review

## 1. نتائج المراجعة والإصلاحات المطبقة

| الخطر | السيناريو | الإصلاح في التصميم | الخطر المتبقي / الاختبار |
|---|---|---|---|
| Duplicate command | API retry أو Engine crash بعد effect قبل ACK | idempotency key، claim lease، correlation، reconcile، no-op current guard | fault injection عند كل boundary |
| Dual leaders | network partition وlease expiry | DB time + fencing token يرفض القديم | adapter يجب أن يفرض token فعليًا |
| Schedule duplicate | ticks/restart/lookahead overlap | unique occurrence key + ON CONFLICT + version | property tests/DST fixtures |
| Schedule conflict | حدثان نفس الوقت/priority | total-order tuple حتى UUID | policy UX يوضح loser/defer |
| Timezone drift | تغيير timezone المحطة يعيد تفسير القديم | timezone snapshot per schedule + UTC occurrence | migration UI لتغيير مقصود |
| DST missing/repeated | 02:30 غير موجود أو مرتين | shift-forward + fold=0 موثق | مناطق DST متعددة في tests |
| Midnight/restart | next run يفقد/يتكرر | materialized horizon + late grace + ledger | clock jump/long downtime tests |
| Audio gap | process per track يسقط source | persistent encoder/source + prebuffer N+1 | waveform target يحتاج اعتماد |
| Failed next track | switch قبل اكتشاف corruption | preflight/decode-ready قبل cut | corrupt mid-file يحتاج emergency switch |
| DB outage | Engine لا يجد التالي | local signed snapshot + emergency cache | طول outage مقابل cache capacity |
| Storage outage | processed object غير متاح | local prefetch + skip/default/cache | cache eviction policy بالقياس |
| Icecast SPOF | host/mount crash | dual target موصى به + fallback URL | budget decision مفتوح |
| API/Admin failure | التحكم غير متاح | playout plane مستقل | لا commands جديدة أثناء outage |
| Stale Now Playing | DB update قبل الصوت | update بعد playout ACK + monotonic revision | polling latency |
| Cross-station reference | schedule في A يشغل playlist B | composite FKs + service validation | DB tests |
| Non-READY media | item تغير/فشل بعد الجدولة | validation عند create وعند resolve | archive أثناء play يستمر current ثم يمنع next |
| Reorder race | مشرفان يعدلان playlist | optimistic version + transaction positions | UI conflict recovery |
| Role staleness | صلاحية أزيلت لكن JWT حي | DB authorization/cache invalidation + revoke session | TTL window للقراءات غير الحساسة |
| Public data exposure | Supabase auto-grants/RLS omission | dedicated API schema/revoke defaults/no anon grants | migration security tests/advisors |
| Upload abuse | extension spoof/FFmpeg exploit | signature/probe/sandbox/limits/pinning | fuzz/corpus + patch cadence |
| Restart storm | watchdog يرى symptom متكرر | restart budget/circuit/escalation | chaos tests |
| Silent-but-HTTP-200 | mount متصل بصمت | external decode/audio-energy probe | false positive في هدوء مقصود |
| Log leakage | signed URLs/tokens in errors | structured allowlist + redaction | automated secret scan |
| Unbounded history | logs/metrics تكبر | retention/partition/aggregation | thresholds بعد traffic baseline |
| Provider sync deletes catalog | upstream omits/fails page | last_seen + successful-run evidence؛ never blind delete | missing policy simulation |
| Provider schema drift | MP3Quran casing/shape changes | adapter fixtures + schema validation + partial run | v3/legacy/unknown fields |
| External SSRF | Admin/provider URL resolves داخليًا أو redirects | DNS/IP revalidation، redirect/byte/time limits، sandbox | rebinding/metadata/private-IP corpus |
| False health | HTTP 200 returns HTML/silence/stale HLS | protocol parse + bounded frame decode + playlist freshness | HTTP-200-no-audio fixtures |
| Health thundering herd | provider-wide outage | jitter، per-provider concurrency/circuit، separate pool | bulk 1k station fault test |
| Rights leak | station flag true رغم provider restricted | effective provider∩station policy، deny-by-default، audit | production projection/role tests |
| External outage impacts owned radio | shared pool/alerts starve Engine | no radio.* writes، separate pool/budget/alerts، direct playback | total provider outage chaos test |

## 2. Single Points of Failure

### مقبولة مؤقتًا فقط في development/staging

- Supabase project واحد.
- Engine/playout host واحد.
- Icecast واحد في local compose.
- Nginx edge واحد.

### Production recommendation

- Managed DB backups/PITR؛ قرار read replica ليس ضروريًا للـMVP لأن playout cache أهم من read scale.
- Engine active/standby مع per-station fencing، لا active/active playout.
- Icecast A/B يتلقيان المصدر نفسه؛ health-aware endpoints.
- external monitoring خارج failure domain.

Supabase نفسه يبقى managed dependency؛ الاستمرار المؤقت يتحقق محليًا، أما admin/control writes فتتوقف بأمان حتى عودته.

## 3. Scaling Review

- **Listeners:** يتوسع Icecast/relay أفقيًا؛ لا يزيد حمل API/DB لكل audio byte.
- **Stations:** partition ownership حسب station leases؛ process/adapter لكل محطة أو pool مع isolation. لا shared global queue.
- **Uploads:** workers أفقيًا مع `SKIP LOCKED` وjob heartbeats؛ object keys idempotent.
- **API:** stateless replicas، shared DB/cache اختياري، pools bounded.
- **History:** aggregates/partitions/retention؛ لا query raw logs للDashboard.
- **Storage/CDN:** on-demand عبر CDN؛ live لا يخرج من Storage لكل listener.
- **External catalog:** sync/health workers scale independently؛ provider outage لا يزيد listener traffic على خوادمنا لأن playback direct.

حدود يجب قياسها قبل التوسع: encoder CPU لكل محطة، upload CPU-minute/hour، Icecast bandwidth/connections، DB occurrence/command rate، storage egress.

## 4. Security Review Summary

- Public surface allowlisted projections فقط.
- Admin authentication لا يكفي؛ permission لكل action وRLS/grants defense.
- command creation وexecution هويتان منفصلتان؛ Engine credential لا يملك إدارة admins.
- audio worker يملك prefixes لازمة فقط؛ لا يملك radio commands.
- Icecast source credentials منفصلة لكل station/environment وقابلة للدوران.
- audit للعملية الحساسة، من دون secrets أو raw personal data.

## 5. قرارات غير محسومة لا يجوز افتراضها

1. Liquidsoap أم custom FFmpeg playout.
2. production region وstation timezone.
3. audio codec/profile/loudness final values.
4. Supabase Storage أم S3-compatible production target بعد MVP.
5. single-host risk acceptance أم HA من أول production.
6. SLO/RPO/RTO/retention والقيم المالية المرتبطة بها.
7. emergency behavior أثناء live source في Phase 2؛ MVP يمنع التعارض.
8. من يملك Rights approval، وما evidence/renewal policy المطلوبة لكل Provider/Station.
9. health thresholds والإخفاء/fallback policy للمحطات الخارجية.

## 6. Design Review Acceptance

التصميم صالح للانتقال فقط إذا تحولت القرارات السبعة إلى ADRs، وأثبت Phase 5 Spike هدف audio gaps/failover، وأثبت Phase 2 schema tests أن cross-station/RLS/idempotency invariants مفروضة لا موثقة فقط.
