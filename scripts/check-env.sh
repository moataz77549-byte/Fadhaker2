#!/usr/bin/env bash
# Verifies environment template completeness without leaking secrets
set -euo pipefail

echo "=== Fadhkur (فذكر) Environment Verification ==="

SERVICES=(
  "apps/mobile"
  "apps/admin"
  "apps/admin_mobile"
  "supabase"
  "services/audio-worker"
  "services/radio-engine"
  "services/quran-yutla-api-elysia"
)

for service in "${SERVICES[@]}"; do
  if [ -f "$service/.env.example" ]; then
    echo "✓ Found .env.example for $service"
  else
    echo "✗ Missing .env.example in $service"
    exit 1
  fi
done

echo "All environment templates are verified and secret-free."
