# Quran Text & Data Integrity Specification (Fail-Closed)

## 1. Canonical Dataset Definition
- **Standard**: Uthmanic Hafs 'an 'Asim text verified against the King Fahd Glorious Quran Printing Complex (مجمع الملك فهد لطباعة المصحف الشريف).
- **Total Surahs**: Exactly 114 Surahs.
- **Total Verses**: Exactly 6,236 Ayahs.
- **Total Mushaf Pages**: Exactly 604 Pages (Medina Mushaf Standard).

## 2. Integrity Verification & Fail-Closed Rule
The canonical dataset is stored in `data/quran/canonical/` alongside an immutable `manifest.json`.
Every build, migration, and pipeline run triggers `scripts/validate-checksums.sh`.

```bash
./scripts/validate-checksums.sh
```

### Fail-Closed Behavior
If any of the following conditions occur:
1. The record count is not exactly 114 Surahs.
2. The total sum of verses across all Surahs is not exactly 6,236.
3. The computed SHA-256 hash of `surahs.json` differs from the manifest.
4. Any surah order, verse count, or page boundaries are invalid.

Then:
- The script immediately exits with non-zero exit code (`exit 1`).
- The application runtime refuses to serve dynamic or mutable Quranic text.
- No live fallback to unverified third-party scraping APIs is permitted.
