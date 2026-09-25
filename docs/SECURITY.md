# Fadhkur (فذكر) — Security Policy & Guidelines

## 1. Secrets Management Rules
- **Strict Client-Side Exclusion**: Neither the Flutter mobile apps (`apps/mobile`, `apps/admin_mobile`) nor the Next.js frontend bundle may contain:
  - Supabase `service_role` key
  - Icecast admin/source passwords
  - Cloud storage master write keys
  - Firebase Private Key or service account JSON
- **Client-Safe Credentials**:
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY` (Publishable key with strict PostgreSQL RLS policies applied)

## 2. Administrative Security & RBAC
- **Next.js Admin Console**:
  - Session cookies MUST use `HttpOnly`, `SameSite=Lax`, and `Secure` flags.
  - Mutations are guarded by role-based access control (Admin vs Editor).
  - All write operations produce immutable entries in the `audit_logs` database table.

## 3. Remote Config Constraints
- Remote configuration responses are strictly restricted to structured data schemas.
- Under NO circumstance may Remote Config execute dynamic scripts, JavaScript, or Dart code remotely.
- Notification navigation routes are validated against an immutable client-side allow-list.

## 4. Audio Processing Isolation
- `services/audio-worker` executes FFmpeg operations in sandboxed containers with limited filesystem access and non-root user permissions.
