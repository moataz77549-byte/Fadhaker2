#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/cloud/health-check.sh
# Purpose: Comprehensive Cloud Health Check for Fadhkur
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo " Fadhkur (فذكر) — Cloud Health Check"
echo "=========================================================="

# 1. Quran Integrity Verification
echo "1. Validating Quran Integrity..."
./scripts/validate-checksums.sh

# 2. Database Migration & RLS Audit
echo "2. Auditing Database Schemas and RLS..."
./scripts/cloud/verify_rls.sh

# 3. Storage Buckets Audit
echo "3. Auditing Storage Buckets Access..."
./scripts/cloud/verify_storage.sh

# 4. Firebase Verification
echo "4. Checking Firebase Environment..."
./scripts/cloud/verify_firebase.sh

echo "=========================================================="
echo "✅ Cloud Health Check Completed."
echo "=========================================================="
