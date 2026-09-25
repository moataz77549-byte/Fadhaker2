#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/cloud/verify_firebase.sh
# Purpose: Check Firebase project credentials and FCM configuration
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo " Fadhkur — Firebase & FCM Integration Status"
echo "=========================================================="

FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}"
FIREBASE_CLIENT_EMAIL="${FIREBASE_CLIENT_EMAIL:-}"
FIREBASE_PRIVATE_KEY="${FIREBASE_PRIVATE_KEY:-}"

if [ -n "$FIREBASE_PROJECT_ID" ] && [ -n "$FIREBASE_CLIENT_EMAIL" ] && [ -n "$FIREBASE_PRIVATE_KEY" ]; then
    echo "✓ Firebase Service Account: CONFIGURED"
    echo "  - Project ID: $FIREBASE_PROJECT_ID"
    echo "  - Client Email: $FIREBASE_CLIENT_EMAIL"
    echo "✅ Firebase Production Status: READY"
else
    echo "⚠️ Firebase Production Secrets currently not set in environment."
    echo "  - Status: NOT VERIFIED (Dry-run mode enabled in Edge Functions)"
    echo "  - Action required: Provide FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY."
fi
