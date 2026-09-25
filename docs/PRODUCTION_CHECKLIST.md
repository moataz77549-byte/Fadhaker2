# Production Readiness Checklist — Fadhkur (فذكر)

> **آخر تحديث:** 2026-09-23 · إصدار `1.0.64` (build `64`).
> لا توقّع على الإنتاج قبل إكمال كل البوابات. هذا الملف لا يحتوي أي secret —
> فقط أسماء الأسرار والخطوات.

## البوابات الحرجة (Blockers)

- [ ] **تثبيت الجيل المرجعي للـ migrations**: قاعدة الإنتاج مبنية على جيل واحد
      فقط (القديم `202601–202603` أو الجديد `20260830*`)، والجيل الآخر مجمّد/
      مُستبعد من مسار التطبيق. (`docs/DEPLOYMENT.md` — التحذير الحرج)
- [ ] **تطبيق الـ migrations اليدوية**: `20260830040500` … `20260830040800`
      (منها `20260830040700_video_channels_table.sql`) مطبَّقة يدويًا من مالك
      قاعدة البيانات بالترتيب الرقمي.
- [ ] **Firebase Admin SDK**: `FIREBASE_CLIENT_EMAIL` و`FIREBASE_PRIVATE_KEY`
      مضبوطان كـ Supabase Secrets لدالة `notifications`؛ ملف JSON الأصلي
      **خارج الريبو** ولم يدخله أبدًا.
- [ ] **GitHub Secrets** مكتملة للإصدار: `FIREBASE_PROJECT_ID`،
      `FIREBASE_API_KEY`، `FIREBASE_ANDROID_APP_ID`،
      `FIREBASE_MESSAGING_SENDER_ID`، `FIREBASE_STORAGE_BUCKET`،
      `FIREBASE_GOOGLE_SERVICES_JSON_BASE64`، `SUPABASE_PUBLISHABLE_KEY`،
      `ANDROID_KEYSTORE_BASE64`، `ANDROID_KEY_ALIAS`، `ANDROID_KEY_PASSWORD`،
      `ANDROID_STORE_PASSWORD`.
- [ ] **سلامة النص القرآني**: `./scripts/validate-checksums.sh` يمر (بوابة fail-closed).
- [ ] **تدوير أسرار Icecast**: الـ workflows (`phase5b-real-icecast.yml`،
      `phase6-radio-automation.yml`) تحتوي قيم `<redacted>` مثبتة — تُستبدل
      بتوليد ديناميكي لبيانات اعتماد مؤقتة قبل أي تشغيل حقيقي.

## بوابات البناء والجودة

- [ ] `flutter pub get` → `flutter analyze` (صفر أخطاء) → `flutter test` (الكل ناجح)
      → `flutter build apk --release` في `apps/mobile`.
- [ ] `npm run build` في `apps/admin` ينجح (18 صفحة، منها `/dashboard/video-channels`).
- [ ] `minSdk = 26` و`versionCode = 64` و`versionName = "1.0.64"` مؤكدة في
      `apps/mobile/android/app/build.gradle.kts`.
- [ ] لا mock data ظاهرة في الواجهات (تحقق 2026-09-23: نظيف).
- [ ] Edge Functions منشورة: `notifications`، `quran-yutla-api`،
      `managed-radio`، `provider-sync`، `radio-schedule`، `audio-metadata`، `health`.

## بوابات الأمان والخصوصية

- [ ] الفحص الأمني الدوري (2026-09-23): لا private keys / لا JWT حقيقية /
      لا `sb_secret_*` / لا service account JSON في الشجرة أو تاريخ git.
- [ ] `google-services.json` غير متعقَّد (gitignored) ويُحقن وقت البناء فقط.
- [ ] RLS مفعّل على كل جداول `app` و`radio`؛ الكتابة الإدارية عبر
      `app.has_permission(...)` فقط.
- [ ] الإشعارات opt-in فقط: لا اشتراك topic قبل الموافقة، والسحب الفوري
      يستبدل الرمز بـ `'REVOKED'`.
- [ ] `FCM_SERVER_KEY` وأي مفاتيح خادم أخرى **ليست** في حزم العميل.

## بوابات التشغيل

- [ ] Supabase Secrets مضبوطة للإنتاج (`SUPABASE_URL`، `SUPABASE_SERVICE_ROLE_KEY`،
      أسرار Firebase الثلاثة لدالة `notifications`).
- [ ] لوحة الإدارة منشورة ومحمية بـ RBAC + سجل تدقيق append-only.
- [ ] محرك الإذاعة (Liquidsoap 2.2 + Icecast 2) يعمل مع EBU R128 (-16 LUFS).
- [ ] النسخ الاحتياطي لقاعدة البيانات وسياسة الاسترداد موثقة ومختبرة.

## ملاحظات مفتوحة (غير حاجبة للإصدار الحالي لكنها للمتابعة)

- تعارض جيلي الـ migrations يحتاج قرار مالك قاعدة البيانات (أعلاه).
- `firestore.rules` / `firebase.json` موجودان لكن Firestore غير مستخدم فعليًا
  حاليًا — يُراجع عند الحاجة.
