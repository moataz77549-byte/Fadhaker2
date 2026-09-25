# Third-Party Notices & Attribution — Fadhkur (فذكر)

Fadhkur incorporates or interfaces with open-source software, institutional Waqf datasets, and public cultural broadcasts under their respective licenses and terms:

## 1. Quranic Text & Data Sources
- **King Fahd Glorious Quran Printing Complex (مجمع الملك فهد لطباعة المصحف الشريف)**:
  - Canonical Uthmanic Text according to the narration of Hafs from Asim (حفص عن عاصم).
  - Medina Mushaf page alignments (604 pages).
  - Page-image and font mirrors require per-asset rights review; attribution and URL availability alone do not grant redistribution or commercial rights. See `docs/MUSHAF_SOURCES.md`.

## 2. Audio Broadcasts & Provenance

- **MP3Quran**: the source and station catalog are recorded for review. Its rights status is `REVIEW_REQUIRED`; the owner has enabled linking to healthy stations returned by the official radio API. Other datasets remain blocked by `production_enabled=false`; no rehosting or commercial redistribution permission is asserted here.

- **Cairo Radio Archive (أرشيف إذاعة القرآن الكريم من القاهرة)**:
  - Public heritage recitations of Sheikh Abdulbasit Abdussamad, Sheikh Mohamed Siddiq El-Minshawi, and Sheikh Mahmoud Khalil Al-Hussary.
- **Haramain Recordings (تسجيلات الرئاسة العامة لشؤون الحرمين الشريفين)**:
  - Official recordings of the Two Holy Mosques in Mecca and Medina.

## 3. Open Source Software
- **Supabase**: Apache License 2.0.
- **ExoPlayer / AndroidX Media3**: Apache License 2.0.
- **Liquidsoap**: GPL-2.0.
- **Icecast**: GPL-2.0.
- **Next.js & React**: MIT License.

## 4. Translation and Hadith Reference Catalogs

- **QuranEnc**: official translation API at https://quranenc.com/ar/home/api . The
  integration retains edition, verse identity, source URL, version and hash.
  A seven-verse ingestion sample is unpublished while terms, translation-specific
  attribution and production rights are reviewed. The Arabic canonical text is
  never replaced by this source.
- **HadeethEnc**: official encyclopedia API at https://hadeethenc.com/ .
  A two-record Arabic ingestion sample retains original identifiers, references,
  source links and hashes; it is unpublished pending verification and rights
  review. The offline Nawawi collection is a separate curated fallback.
- **Tanzil**: https://tanzil.net/download/ is reserved for independent
  verification, not automated replacement or redistribution of canonical text.
- **IslamHouse**, **Dorar**, and **Hisn Al-Muslim**: no unverified bulk copy is
  published. Each resource needs a traceable source and applicable rights review.

See `docs/ISLAMIC_CONTENT_SOURCES.md` for current activation status. Linking a
third-party stream does not permit storing or rehosting its audio files.
