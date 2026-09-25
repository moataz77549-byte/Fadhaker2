# ADR 0001: Default Production API via Supabase Edge Functions with Optional Elysia BFF

- **Status**: Accepted
- **Date**: 2026-09-16
- **Context**: The Fadhkur (فذكر) ecosystem requires a robust, secure, and low-latency API layer for the Flutter mobile application, admin console, and radio broadcast schedulers. Two candidate paths were evaluated:
  1. Direct Supabase Edge Functions (Deno/TypeScript) coupled with Postgres Row Level Security (RLS).
  2. A dedicated microservice/BFF written in Bun/Elysia (`services/fadhkur-api-elysia`).

## Decision
1. **Primary Production Default**: **Supabase Edge Functions** is the official default production API path.
   - All critical user journeys (fetching reciter lists, audio track URLs, radio schedules, remote maintenance config) run through Supabase Edge Functions and RLS-protected PostgreSQL.
   - Requires no extra server hosting or reverse proxy maintenance for initial and core deployments.
2. **Elysia API Layer**: Kept as an **optional, non-blocking service** (`services/fadhkur-api-elysia`).
   - The Elysia layer can be deployed in the future as a dedicated BFF for custom high-volume caching or specialized transcoding orchestration once fully mature and benchmarked.
   - Neither the Flutter mobile client nor the Next.js admin app strictly depend on the Elysia server to function.

## Consequences
- **Positive**: Zero operational overhead during initial deployments; robust global edge distribution via Supabase; unified authentication and RBAC.
- **Controlled Risk**: The Bun/Elysia service can be iterated on independently without risking downtime for the mobile app or radio broadcast.
