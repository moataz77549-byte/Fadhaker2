# إعداد فذكر خارج جلسة Manus

## القيم العامة

| الخدمة | القيمة |
|---|---|
| Supabase URL | `https://ttvasynaxkkcwrmvlorg.supabase.co` |
| Firebase project ID | `fadhkur-2f78c` |
| Firebase project number / sender ID | `512347419509` |
| Android package | `app.fadhkur` |
| Firebase Android App ID | `1:512347419509:android:2cad141a837c31c6f9193c` |
| Android application label | `فذكر` |

## GitHub Actions Secrets المطلوبة

- `SUPABASE_PUBLISHABLE_KEY` — المفتاح publishable/anon من Supabase فقط.
- `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` — ملف `google-services.json` العام لتطبيق Android، مشفراً Base64.
- `FIREBASE_API_KEY` — مفتاح Firebase العميل العام.
- `FIREBASE_ANDROID_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_STORAGE_BUCKET`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

## أسرار Supabase Edge Functions

يجب أن تبقى هذه القيم داخل Supabase Secrets فقط، ولا تُضاف إلى Git أو التطبيق:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

## تحذير أمني

لا تستخدم Supabase `service_role` key أو Firebase Admin private key داخل APK أو GitHub repository أو ملفات Flutter. كما يجب تدوير كلمة مرور Google ورمز GitHub PAT اللذين تم إرسالُهما في المحادثة، ثم تحديث الأسرار الجديدة فقط. هذا الملف لا يحتوي على أي مفتاح خاص أو كلمة مرور.
