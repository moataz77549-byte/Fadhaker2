# quran-yutla-api — Quran Foundation Proxy

Supabase Edge Function تعمل كـ **proxy آمن** بين تطبيق Flutter و Quran Foundation API.

## القاعدة الأمنية

**لا أسرار في Flutter أبدًا.** كل credentials الخاصة بـ Quran Foundation
(OAuth2 Client Credentials) تُحفظ في **Edge Function Secrets** فقط،
والتطبيق ينادي مسارات `/quran/*` هنا دون أن يرى أي سر.

## الـ Secrets المطلوبة

| الاسم | الوصف | مثال |
|---|---|---|
| `QF_CLIENT_ID` | OAuth2 Client ID من Quran Foundation Developer Console | `xxxx-xxxx` |
| `QF_CLIENT_SECRET` | OAuth2 Client Secret (يُعرض مرة واحدة عند الإنشاء) | `yyyy-yyyy` |
| `QF_ENV` | `production` أو `prelive` (افتراضي: `production`) | `production` |
| `SUPABASE_URL` | (موجود مسبقًا) | — |
| `SUPABASE_ANON_KEY` | (موجود مسبقًا) | — |
| `SUPABASE_SERVICE_ROLE_KEY` | (موجود مسبقًا) | — |

التعيين (من جذر مشروع Supabase المرتبط):

```bash
supabase secrets set QF_CLIENT_ID="<client-id>"
supabase secrets set QF_CLIENT_SECRET="<client-secret>"
supabase secrets set QF_ENV="production"
supabase functions deploy quran-yutla-api
```

> إنشاء الـ credentials: من Quran Foundation Developer Console أنشئ تطبيقًا
> (backend/confidential) واحصل على `client_id` + `client_secret` لمرة واحدة.
> المرجع: https://api-docs.quran.foundation/docs/quickstart/

## كيف تعمل المصادقة

1. عند أول طلب `/quran/*` تطلب الـ Function رمز وصول:
   `POST {auth_base}/oauth2/token` بترويسة `Authorization: Basic base64(id:secret)`
   وجسم `grant_type=client_credentials&scope=content`.
2. يُخزَّن الرمز في ذاكرة الـ Function حتى قبل انتهائه بدقيقة
   (`expires_in ≈ 3600` ثانية، بلا refresh token — يُعاد الطلب).
3. كل استدعاء للمحتوى يحمل الترويستين المطلوبتين:
   `x-auth-token: <access_token>` و `x-client-id: <client_id>`.
4. بيئات Quran Foundation:
   - production: `https://oauth2.quran.foundation` → `https://apis.quran.foundation`
   - prelive: `https://prelive-oauth2.quran.foundation` → `https://apis-prelive.quran.foundation`

## المسارات الجديدة

| المسار | الوصف | المصدر |
|---|---|---|
| `GET /quran/config` | إعدادات وقت التشغيل: الروايات، الخطوط، التفاسير (بلا أسرار) | `app.app_config` + احتياطي مضمّن |
| `GET /quran/page?riwaya=hafs&page=293` | نص صفحة (uthmani + tajweed) مع اسم السورة | QF `GET /verses/by_page/{page}` |
| `GET /quran/lookup?chapter=18&verse=1` | رقم صفحة آية | QF `GET /pages/lookup` |
| `GET /quran/tafsirs` | فهرس التفاسير العربية | QF `GET /resources/tafsirs` |
| `GET /quran/tafsir/{id}/ayah/{c}/{v}` | تفسير آية (كائن `tafsir` المفرد) | QF `GET /tafsirs/{id}/by_ayah/{key}` |

معرّفات التفاسير العربية (من فهرس QF الحي):
`16` التفسير الميسر، `14` تفسير ابن كثير، `91` تفسير السعدي، `90` تفسير القرطبي.

## مفاتيح `app.app_config` (عامة، `is_public = true`)

| المفتاح | القيمة | الاحتياطي |
|---|---|---|
| `quran.riwayat_registry` | مصفوفة JSON لكائنات الرواية (`id`, `nameAr`, `narratorAr`, `totalPages` أو null، `pageImageTemplate` أو null، `qfMushafId` أو null، `textAvailable`) | حفص 604 + 3 روايات بلا تخطيط موثّق |
| `quran.font_options` | مصفوفة JSON (`id`, `nameAr`, `fontFamily`, `lineHeight`, `licenseNoteAr`) | 4 خطوط |
| `quran.tafsir_sources` | مصفوفة JSON (`resourceId`, `nameAr`, `slug`) | التفاسير الأربعة |

مثال (يُنفَّذ مرة واحدة من لوحة Supabase — SQL):

```sql
insert into app.app_config (key, value, is_public)
values ('quran.riwayat_registry', '[
  {"id":"hafs","nameAr":"حفص عن عاصم","narratorAr":"عاصم بن أبي النجود الكوفي",
   "totalPages":604,
   "pageImageTemplate":"https://cdn.example.com/mushaf/hafs/{page}.webp",
   "qfMushafId":1,"textAvailable":true,"notesAr":"المصحف المدني"}
]'::jsonb, true)
on conflict (key) do update set value = excluded.value;
```

> `{page}` يُستبدل برقم الصفحة من 3 خانات (001..604).
> ضع هنا رابط مجموعة الصور المرخّصة فعليًا وقت النشر.

## رموز الأخطاء

| الرمز | المعنى | HTTP |
|---|---|---|
| `QF_NOT_CONFIGURED` | الـ Secrets غير مضبوطة | 503 |
| `QF_TOKEN_FAILED` | فشل طلب الرمز من QF | 500/502 |
| `UNKNOWN_RIWAYA` | رواية غير معروفة | 400 |
| `TEXT_UNAVAILABLE` | نص الرواية غير متوفّر بعد | 404 |
| `UPSTREAM_ERROR` | خطأ من Quran Foundation | 502 |
| `TAFSIR_NOT_FOUND` | لا تفسير لهذه الآية في المصدر | 404 |
| `RATE_LIMITED` | تجاوز الحد (120/دقيقة/IP) | 429 |

## ملاحظات تشغيلية

- التخزين المؤقت داخل الـ Function: الإعدادات 5 دقائق، فهرس التفاسير ساعة، أسماء السور 24 ساعة.
- عند غياب `QF_CLIENT_ID/SECRET` تُرجع مسارات `/quran/*` خطأ `503` واضحًا بدل الفشل الصامت.
- لا تُعَد تشغيل أي migration مطبّق مسبقًا؛ هذه المسارات لا تحتاج جداول جديدة
  (تقرأ `app.app_config` الموجود فقط).
