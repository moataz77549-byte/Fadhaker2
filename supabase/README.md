# Supabase Configuration & Migrations

Provides PostgreSQL database schemas, Row Level Security (RLS) rules, Edge Functions, and storage configurations for **Fadhkur (فذكر)**.

## Commands
```bash
# Start local Supabase instance
supabase start

# Apply migrations
supabase db reset

# Deploy edge functions
supabase functions deploy radio-schedule
supabase functions deploy audio-metadata
```

## Security Note
`SUPABASE_SERVICE_ROLE_KEY` is strictly reserved for backend workers and administrative server-side operations. Client apps consume the `anon` key only with Postgres RLS enabled on all tables.
