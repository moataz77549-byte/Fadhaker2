# Security Boundaries & Zero-Surveillance Architecture

## 1. Zero Secrets in Client Applications
- Android and web clients receive only public client configuration and a Supabase publishable key.
- Supabase `service_role` / secret keys, database administrative credentials, Firebase service-account private keys, and signing keys must never be bundled into clients or committed to Git.
- Server-only Firebase credentials are stored in the backend secret manager and read only at runtime.
- Any service-account key that is pasted into chat, tickets, logs, or other non-secret channels must be treated as compromised and revoked in Google Cloud IAM.

## 2. Row Level Security (RLS) Policy
- Direct anonymous writes to database tables are forbidden unless explicitly designed and reviewed.
- Public reads are limited to explicitly published/active content.
- Administrative operations require verified role membership through `app.administrators` and `app.has_permission(required_perm)`.
- Internal tables may intentionally have RLS enabled with no client policy; this means they are server-only and is not by itself an error.
- Administrative read/write policies are split by SQL action to avoid overlapping permissive policies while preserving least-privilege behavior.

## 3. Legacy Schema Boundary
- `app.*` is the active application schema.
- Legacy `public.*` catalog tables remain locked down until dependency analysis is complete.
- Do not delete legacy tables merely because they are empty; removal requires checking functions, views, migrations, jobs, and external clients first.

## 4. Firebase / Notification Boundary
- FCM dispatch is server-side only.
- Firebase service-account credentials must be supplied to Supabase Edge Functions through runtime secrets.
- Client applications may register/revoke their installation token only through the approved application API.
- Raw FCM tokens and private keys must not be logged.

## 5. Privacy-First Notification Consent Architecture
1. **Explicit In-App Consent**: no notification registration until the user explicitly enables notifications.
2. **Installation Pseudonymization**: use an installation UUID and local secret rather than hardware identifiers.
3. **Immediate Revocation**: revocation must disable the installation and invalidate its usable FCM token server-side.
4. **Local Prayer Times**: prayer time calculation should remain on-device unless the user explicitly chooses a remote feature that needs location.

## 6. Secret-Rotation Checklist
1. Revoke exposed Google/Firebase service-account key.
2. Generate a new key only if the current backend integration requires one.
3. Store the replacement only in Supabase Secrets / approved secret manager.
4. Redeploy the affected Edge Functions.
5. Confirm notification delivery works.
6. Search Git history and CI artifacts for the old key fingerprint.
7. Never copy the replacement key into repository files.
