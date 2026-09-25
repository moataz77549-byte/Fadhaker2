# @fadhkur/api-elysia

Optional BFF (Backend-For-Frontend) caching and aggregation microservice built with **Bun** and **Elysia**.

> **Architectural Note (ADR 0001)**: The primary production API remains **Supabase Edge Functions**. This service is an optional accelerator for high-throughput edge caching and is not required for fundamental app operation.
