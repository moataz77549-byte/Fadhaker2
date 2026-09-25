#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT_REF:?Set PROJECT_REF to the target Supabase project ref}"

output_path="${1:-packages/api-types/src/database.types.ts}"
mkdir -p "$(dirname "$output_path")"
npx supabase gen types typescript \
  --project-id "$PROJECT_REF" \
  --schema app \
  --schema radio \
  > "$output_path"

echo "Generated $output_path"
