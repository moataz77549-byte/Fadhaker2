# Provider Sync & Deployment Guide

## 1. Environment & Architecture Overview
Fadhkur deployments rely on a dual-layer strategy:
1. **Primary Production**: Supabase PostgreSQL 15+, Row Level Security (RLS), and Supabase Edge Functions (`fadhkur-api`, `notifications`).
2. **Streaming Cluster**: Icecast 2 relay nodes with Liquidsoap 2.2 automation engine for 24/7 seamless Quranic radio broadcasting.
3. **Optional BFF**: Bun / Elysia microservice for caching high-volume traffic.

## 2. Migration Execution Pattern
Migrations in `supabase/migrations/` are append-only.
- `20260101000000_fadhkur_init.sql`: Foundation tables and public baseline.
- `20260201000000_fadhkur_core_schemas.sql`: Domain schemas (`app`, `radio`), RBAC, notifications, and audit logging.

To apply migrations cleanly:
```bash
supabase db reset
supabase migration up
```

## 3. Dataset Verification Before Deployment
Every deployment pipeline must execute:
```bash
./scripts/validate-checksums.sh
```
If this command exits with any non-zero code, the deployment will immediately abort.
