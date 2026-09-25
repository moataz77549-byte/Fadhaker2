#!/usr/bin/env bash
# ==============================================================================
# Fadhkur — Canonical Quran Integrity & Checksum Validator
# Fail-Closed: If any file checksum, record count, or schema structure differs,
# the process exits with code 1 and aborts deployment.
# ==============================================================================
set -euo pipefail

MANIFEST="data/quran/canonical/manifest.json"
DATA_DIR="data/quran/canonical"

echo "=========================================================="
echo " Fadhkur (فذكر) — Canonical Quran Integrity Check"
echo "=========================================================="

if [ ! -f "$MANIFEST" ]; then
  echo "❌ CRITICAL: Canonical manifest missing at $MANIFEST"
  exit 1
fi

echo "✓ Manifest loaded: $MANIFEST"

# Check surahs.json exists
SURAHS_FILE="$DATA_DIR/surahs.json"
if [ ! -f "$SURAHS_FILE" ]; then
  echo "❌ CRITICAL: surahs.json missing at $SURAHS_FILE"
  exit 1
fi

# Verify record count is exactly 114
COUNT=$(node -e '
  const data = JSON.parse(require("fs").readFileSync("'$SURAHS_FILE'", "utf8"));
  console.log(data.length);
')

if [ "$COUNT" -ne 114 ]; then
  echo "❌ CRITICAL: Surahs count mismatch! Expected 114, found $COUNT"
  exit 1
fi
echo "✓ Surahs count verified: 114 surahs"

# Verify SHA-256
ACTUAL_SHA=$(sha256sum "$SURAHS_FILE" | awk '{print $1}')
EXPECTED_SHA=$(node -e '
  const manifest = JSON.parse(require("fs").readFileSync("'$MANIFEST'", "utf8"));
  const f = manifest.canonicalFiles.find(x => x.filename === "surahs.json");
  console.log(f.sha256);
')

if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "❌ CRITICAL CHECKSUM DRIFT:"
  echo "   Expected: $EXPECTED_SHA"
  echo "   Actual:   $ACTUAL_SHA"
  exit 1
fi
echo "✓ SHA-256 Checksum verified: $ACTUAL_SHA"

# Schema validation: Ensure all surahs have number, names, pages, and verse count
node -e '
  const data = JSON.parse(require("fs").readFileSync("'$SURAHS_FILE'", "utf8"));
  let totalVerses = 0;
  for (let i = 0; i < 114; i++) {
    const s = data[i];
    if (s.number !== i + 1) throw new Error(`Surah ordering invalid at index ${i}`);
    if (!s.nameArabic || !s.nameEnglish) throw new Error(`Missing names in Surah ${s.number}`);
    if (s.ayahCount <= 0) throw new Error(`Invalid verse count in Surah ${s.number}`);
    if (s.startPage < 1 || s.endPage > 604) throw new Error(`Page out of bounds in Surah ${s.number}`);
    totalVerses += s.ayahCount;
  }
  if (totalVerses !== 6236) {
    throw new Error(`Total ayah count mismatch: Expected 6236, got ${totalVerses}`);
  }
  console.log(`✓ Total canonical Quran Ayahs verified: ${totalVerses}`);
'

echo "=========================================================="
echo " ✅ Canonical Quran Dataset Integrity Verified (100% PASS)"
echo "=========================================================="
