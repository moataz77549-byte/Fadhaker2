# قنوات الفيديو — app.video_channels

> **الحالة (محدّث 2026-09-23):** الجدول موجود الآن في
> `supabase/migrations/20260830040700_video_channels_table.sql` **لكن لم يُطبَّق بعد**
> على قاعدة البيانات — التطبيق يتطلب تطبيقًا يدويًا من مالك قاعدة البيانات
> (انظر التحذير الحرج في `docs/DEPLOYMENT.md`).
> مستودع التطبيق (`VideoChannelRepository`) يتعامل مع غياب الجدول بقائمة فارغة
> (empty state) — لا بيانات تجريبية في الواجهة.

## الـ schema المطلوب

```sql
create table app.video_channels (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name_ar text not null,
  name_en text,
  stream_url text not null,
  logo_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- قراءة عامة للقنوات المفعّلة (للوصول من التطبيق بالمفتاح العام)
alter table app.video_channels enable row level security;
create policy "Public read active video channels"
  on app.video_channels for select using (is_active = true);

-- إدارة المشرفين (حسب نظام الصلاحيات القائم: app.has_permission / admin_has_permission)
create policy "Admins manage video channels"
  on app.video_channels for all using (app.admin_has_permission('stations.write'));
```

## كيف يقرأ التطبيق القنوات

- `VideoChannelRepository.load()` يستعلم `GET /rest/v1/video_channels` مع
  `Accept-Profile: app` (السكيمة مكشوفة في `supabase/config.toml`)، بمرشح
  `is_active=eq.true` وترتيب `sort_order`.
- أي خطأ (بما فيه غياب الجدول: 404/PGRST205) → قائمة فارغة + empty state.
- آخر كتالوج ناجح يُحفظ في `SharedPreferences` للعمل دون اتصال.
- نوع المصدر يُشتق من الرابط: `.m3u8` → HLS، روابط يوتيوب → YouTube، `.mp4` → MP4.

## المشغّل والاعتماديات

**مضافة** في `apps/mobile/pubspec.yaml` (اعتبارًا من إصدار البناء الحالي):

```yaml
video_player: ^2.8.0
chewie: ^1.8.0
youtube_player_flutter: ^9.0.0
```

- HLS/MP4: `video_player` + `chewie` (ملء الشاشة، تدوير تلقائي عند ملء الشاشة).
- يوتيوب: `youtube_player_flutter`.
- كل المتحكمات تُحرَّر في `dispose()` لتقليل استهلاك الذاكرة.

## ملاحظات المنصة

- رابط الاختبار الأول يعمل عبر `http://` (غير مشفّر). على Android يتطلب
  `android:usesCleartextTraffic="true"` في الـ manifest أو ملف
  Network Security Config — للإنتاج يُفضَّل روابط `https://` فقط.
- `minSdk 26` متوافق مع الحزم الثلاث.

## الربط في التطبيق (خارج نطاق ميزة الفيديو)

- `VideoScreen.routeName == '/video'` — أضف تبويبًا في `RootShell` أو مسارًا
  في `AppRouter` يشير إلى `VideoScreen`.
- روابط الاختبار الحالية في `supabase/seed/07_video_channels.sql` مُعلَّمة
  بوضوح بأنها للاختبار وليست دائمة — تُستبدل من قاعدة البيانات مباشرة.

## إدارة المحتوى

القنوات تُدار من Supabase مباشرة (إدراج/تفعيل/تعطيل/ترتيب عبر
`is_active` و`sort_order`) وتظهر في التطبيق فورًا دون تحديث إجباري.
