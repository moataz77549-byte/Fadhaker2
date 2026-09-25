# Fadhkur (فذكر) — Brand and Cloud Migration

The product identity is now **فذكر / Fadhkur**. The Android application uses the new package identifier `app.fadhkur`; the Flutter client, admin console, API services, Supabase migrations, radio engine, and shared brand tokens use the same public brand vocabulary.

## Cloud configuration status

The repository contains the complete Supabase schema, Edge Functions, Firebase client integration points, Firestore rules, notification flow, radio engine, and API contracts. Production credentials are intentionally not committed. To activate a new Supabase project, apply `supabase/migrations` and configure the variables in `.env.example`. To activate Firebase, register Android package `app.fadhkur` and replace the ignored `app/google-services.json` with the downloaded file.

The existing API routes, database contracts, station records, audio pipeline, and RLS boundaries were preserved. Only public identity and client identifiers were changed.
