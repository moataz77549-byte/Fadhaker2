# ميزة القرآن (Quran Feature)

> تحديث 2026-09-26: الأقسام القديمة أدناه توثق مسار الصور السابق ولا تصف
> وضع القارئ الافتراضي في `1.0.69-beta.5`. القارئ الحالي يستخدم
> `QuranUnifiedPageView` بأوضاع المدينة والتجويد والموضوعي والنص، ويشارك
> `QuranLocation` والعلامات وآخر قراءة. تُجلب كلمات QCF وخط صفحتها عند
> توافر المصدر؛ وإلا يعرض النص العثماني. مصدر الموضوعات هو Quranpedia
> ويُحفظ محليًا بعد أول مزامنة. راجع `docs/QURAN_BETA3_AUDIT.md` وملفات
> `quran_unified_page_view.dart` و`quran_reading_state_repository.dart`.

## البنية

```
lib/features/quran/
├── domain/
│   ├── riwaya.dart            # سجل الروايات (حفص/ورش/قالون/الدوري) + تخطيط الصفحات
│   ├── mushaf_edition.dart    # إصدارات المصحف المصوّر (عادي/تجويد ملوّن — 604 صفحات)
│   ├── quran_font.dart        # خيارات الخطوط (عثماني/KFGQPC/QCF/Vector)
│   ├── tafsir_source.dart     # مصادر التفاسير (معرّفات QF الحقيقية) — بلا نصوص مضمّنة
│   ├── quran_navigation.dart  # منطق التنقل الخالص (مفاتيح الآيات، نطاقات الصفحات)
│   └── mushaf_page.dart       # نموذج صفحة المصحف
├── data/
│   ├── quran_config_repository.dart        # إعدادات وقت التشغيل من Edge Function (+ تخزين 24h)
│   ├── quran_api_repository.dart           # بوابة المحتوى عبر Edge Function (بلا أسرار)
│   ├── quran_reading_state_repository.dart # الإعدادات المحلية (رواية/نسخة مصحف/خط/حجم/وضع/آخر صفحة)
│   ├── quran_font_loader.dart              # تحميل الخطوط عند أول استخدام + تخزين على القرص
│   └── mushaf_repository.dart              # صفحات النص + تخزين sqflite بمفتاح (رواية:صفحة)
└── presentation/
    ├── mushaf_reader_screen.dart  # القارئ: وضع مصوّر + وضع نص + تفسير + انتقال للآية
    ├── quran_settings_sheet.dart  # ورقة الإعدادات (تشمل منتقي نسخة المصحف)
    └── quran_home_screen.dart     # فهرس السور + بطاقة آخر موضع (بيانات فعلية)
```

## تدفق البيانات

```
Flutter → Supabase Edge Function (quran-yutla-api/quran/*)
            → Quran Foundation API (OAuth2 Client Credentials من Secrets)
```

لا يتصل التطبيق بـ Quran Foundation مباشرة، ولا يحمل أي credentials.

## الروايات

`RiwayaRegistry`: حفص عن عاصم، ورش عن نافع، قالون عن نافع، الدوري عن أبي عمرو.
كل رواية تحمل `totalPages` (قد يكون `null` = غير موثّق) و`pageImageTemplate`
(قالب رابط الصور من الـ Backend). **لا يُفترض 604 صفحة لغير حفص.**

## نسخ المصحف المصوّر

`MushafEditionRegistry`: نسختان موثّقتان للمصحف المدني (حفص — **604 صفحات** فقط):
«المصحف المدني (عادي)» و«المصحف الملوّن بالتجويد»، وكلتاهما من مستودع
`QuranHub/quran-pages-images` (تحقّق حي 2026-09-23 — راجع `docs/MUSHAF_SOURCES.md`).

- تُختار النسخة من ورقة الإعدادات (تظهر لرواية حفص فقط) وتُحفظ محليًا
  (`quran.mushaf_edition_id`).
- القالب يستخدم `{page}` بلا تبطين (`pagePadWidth = 0`) لأن ملفات المصدر
  `1.jpg` … `604.jpg`.
- الوضع المصوّر متاح فقط عندما تدعم النسخة المختارة الصفحات
  (`supportsPages` = تخطيط 604 + قالب صالح)؛ وإلا يُجبَر الوضع على النص
  مع Empty State صادق.
- الصور تُبنى كسولًا عبر `PageView.builder` مع `CachedNetworkImage`
  (تخزين قرص + ذاكرة) — لا تُحمَّل الصفحات الـ 604 في الذاكرة.
- قابلة للتغيير من الـ Backend عبر `quran.mushaf_editions` (تُدمج فوق المضمّنة).

## الخطوط (وضع النص)

الخيارات: العثماني — حفص، KFGQPC — حفص، QCF، العثماني المتجه.
كل خط يحمل `lineHeight` الموصى به لمنع تداخل الحروف والتشكيل (≥ 2.0)،
ويُعرض النص باتجاه RTL دون ضبط (justify) الذي يسبب التداخل.

### التحميل عند أول استخدام (لا تضمين في الحزمة)

لا تُضمَّن ملفات الخطوط في `assets` ولا في `pubspec.yaml`.
`QuranFontLoader.ensureLoaded` ينزّل ملف الخط من `downloadUrl` الموثّق
عند أول اختيار له فقط، ويخزّنه في مجلد دعم التطبيق
(`quran_fonts/<id>.ttf`) ثم يسجّله عبر `FontLoader`.

- الخطان الموثّقان حاليًا: `uthmanic-hafs` (QPC Hafs V22 عبر QUL/Tarteel)
  و`kfgqpc-hafs` (KFGQPC Uthmanic Hafs v1.8 عبر مرآة jsDelivr) —
  تحقّق حي 2026-09-23، راجع `docs/MUSHAF_SOURCES.md`.
- `qcf`: لا يوجد ملف نصي واحد موثّق (QCF ملفٌ لكل صفحة) — بلا رابط تحميل.
- `uthmanic-vector`: لم يُعثر على مصدر موثّق — بلا رابط تحميل.
- عند غياب الرابط أو فشل التنزيل يُستخدم **خط النظام** مع ملاحظة صادقة
  في الإعدادات (لا mock/demo).

## الاعتماديات (موجودة في pubspec.yaml)

```yaml
dependencies:
  http: ^1.2.2                       # تنزيل ملفات الخطوط + إعدادات الـ Backend
  path_provider: ^2.1.2              # مجلد تخزين الخطوط على القرص
  cached_network_image: ^3.3.1       # تخزين صور صفحات المصحف مؤقتًا
  share_plus: ^10.1.2                # مشاركة الآيات
```

## التفاسير

لكل آية: الميسر (16)، ابن كثير (14)، السعدي (91)، القرطبي (90) —
معرّفات حقيقية من فهرس Quran Foundation.
النص يُجلب من الـ Backend عند الطلب فقط، ويُعرض بعد تجريد HTML.
**ممنوع لصق أي نص تفسير في ملفات Dart** — يُراجَع ذلك في الاختبارات
(الاختبارات تستخدم هياكل JSON اصطناعية وليست محتوى حقيقيًا).

## مصادر المحتوى القابلة للتغيير من الـ Backend

| المصدر | المفتاح | أين |
|---|---|---|
| سجل الروايات + قوالب صور الصفحات | `quran.riwayat_registry` | `app.app_config` عبر `/quran/config` |
| إصدارات المصحف المصوّر (عادي/تجويد) | `quran.mushaf_editions` | نفس المسار |
| خيارات الخطوط | `quran.font_options` | نفس المسار |
| مصادر التفاسير | `quran.tafsir_sources` | نفس المسار |
| نصوص الصفحات/الآيات/التفاسير | مسارات `/quran/*` | Edge Function → Quran Foundation |

لا روابط صور ولا endpoints ثابتة في كود Flutter.

## الاختبارات

- `test/features/quran/quran_navigation_test.dart` — مفاتيح الآيات، نطاقات الصفحات لكل رواية، ربط الفهارس RTL.
- `test/features/quran/quran_repository_test.dart` — المستودعات مع `MockClient` (mocks في الاختبارات فقط): بناء الروابط، غياب الترويسات السرّية، التخزين المؤقت، حالات الفشل.
- `test/features/quran/mushaf_page_test.dart` — تحليل نموذج الصفحة (محدّث لدعم `riwayaId`).
