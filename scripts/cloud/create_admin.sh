#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/cloud/create_admin.sh
# Purpose: Grant Super Admin permissions to an authenticated user safely
# ==============================================================================
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <user_id_uuid> <display_name>"
    echo "Example: $0 550e8400-e29b-41d4-a716-446655440000 \"المدير العام\""
    exit 1
fi

USER_ID="$1"
DISPLAY_NAME="$2"

echo "Provisioning administrator for User ID: $USER_ID ($DISPLAY_NAME)..."

cat <<EOF
-- Run this query inside Supabase SQL Editor:
INSERT INTO app.administrators (user_id, display_name, is_active)
VALUES ('$USER_ID', '$DISPLAY_NAME', true)
ON CONFLICT (user_id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO app.administrator_roles (administrator_id, role_id)
SELECT id, 'super_admin'
FROM app.administrators
WHERE user_id = '$USER_ID'
ON CONFLICT DO NOTHING;
EOF

echo "✓ Administrator SQL grant generated successfully."
