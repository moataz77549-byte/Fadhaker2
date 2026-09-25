# Fadhkur (فذكر) — Architecture Overview

## 1. Vision & Identity
«فذكر» is an independent, production-grade platform dedicated to high-fidelity Holy Quran recitations, scheduled 24/7 radio broadcasting, and reading experiences. It provides an Arabic-first user experience designed around reverence, clarity, performance, and accessibility.

## 2. Monorepo Topology
```
.
├── apps/
│   ├── mobile/                  # Flutter end-user application (Riverpod, just_audio, M3)
│   ├── admin/                   # Next.js admin management console (RTL, Auth, RBAC)
│   └── admin_mobile/           # Lightweight Flutter operations app
├── supabase/
│   ├── migrations/              # PostgreSQL schema, RLS, audit logs
│   ├── functions/               # Supabase Edge Functions (Default Production API)
│   └── config.toml              # Local development configuration
├── services/
│   ├── audio-worker/            # FFmpeg/ffprobe audio loudness (-16 LUFS) & waveform worker
│   ├── radio-engine/            # 24/7 stream orchestration & playlist scheduler
│   └── fadhkur-api-elysia/  # Optional Bun/Elysia BFF layer (Non-blocking)
├── packages/
│   ├── api-types/               # Shared TypeScript schemas and DTO contracts
│   └── brand-config/            # Centralized brand tokens, colors, and identifiers
├── infrastructure/
│   ├── icecast/                 # Icecast streaming server configuration
│   └── liquidsoap/              # Liquidsoap dynamic audio routing & failover
├── data/
│   └── quran/canonical/         # Canonical surahs, ayahs, manifest, and checksums
└── docs/
    ├── ADR/                     # Architectural Decision Records
    ├── BRAND_IDENTITY.md        # Design system, brand mark, and tokens
    └── SECURITY.md              # Secrets policies, RBAC, and safe configs
```

## 3. Core Architectural Boundaries & Data Flow
1. **End-User Flow**:
   - `apps/mobile` connects directly to **Supabase Edge Functions** for live radio status, reciter listings, and playlist queries.
   - Streaming audio flows directly from CDN/Icecast (`infrastructure/icecast`) or Supabase Storage buckets.
   - Remote config updates are processed asynchronously without blocking the user interface.
2. **Audio Processing Pipeline**:
   - Master files uploaded via `apps/admin` trigger `services/audio-worker`.
   - FFmpeg analyzes peaks, performs EBU R128 (-16 LUFS) normalization, extracts metadata, computes SHA-256 checksums, and renders waveforms.
   - Validated metadata is saved into Supabase PostgreSQL.
3. **Continuous Radio Broadcasting**:
   - `services/radio-engine` maintains playback schedule queues.
   - `infrastructure/liquidsoap` receives feeds, executes seamless crossfades, and streams to `infrastructure/icecast`.
   - In case of network interruption, Liquidsoap falls back to local continuous recitation loops.

## 4. Production API Path Strategy
- **Default Production Path**: Supabase Edge Functions + PostgreSQL + Storage.
- **Optional BFF**: `services/fadhkur-api-elysia` remains an optional, non-blocking accelerator and is not required for primary operation (see `docs/ADR/0001-default-production-api-supabase-edge.md`).
