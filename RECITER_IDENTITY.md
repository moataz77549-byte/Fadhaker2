# Reciter Identity Normalization & Provenance Standards

## Problem Statement
Third-party APIs (MP3Quran, EveryAyah, AlQuran Cloud, etc.) use inconsistent naming conventions, transliterations, and IDs for the same Quran reciter. This often results in:
- Duplicate entries.
- Missing biographical details.
- Accidental playback of tracks from the wrong reciter.

## Fadhkur Normalization Contract
Every reciter in Fadhkur has a fixed canonical slug and unified database record:

| Canonical Slug | Name (Arabic) | Name (English) | Default Riwayah | Primary Provider |
| :--- | :--- | :--- | :--- | :--- |
| `abdulbasit-abdussamad` | الشيخ عبد الباسط عبد الصمد | Sheikh Abdulbasit Abdussamad | المصحف المجود • حفص عن عاصم | مجمع الملك فهد / أرشيف إذاعة القرآن |
| `mohamed-siddiq-el-minshawi` | الشيخ محمد صديق المنشاوي | Sheikh Mohamed Siddiq El-Minshawi | المصحف المرتل • حفص عن عاصم | مجمع الملك فهد / أرشيف القاهرة |
| `mahmoud-khalil-al-hussary` | الشيخ محمود خليل الحصري | Sheikh Mahmoud Khalil Al-Hussary | المصحف المرتل • رواية ورش عن نافع | مجمع الملك فهد |
| `ali-abdullah-jaber` | الشيخ علي عبد الله جابر | Sheikh Ali Abdullah Jaber | تلاوات الحرم المكي • حفص عن عاصم | تسجيلات الحرمين الشريفين |

### Identity Protection Rules
1. **No Mixed Audio Returns**: When a user selects a specific reciter, the API is forbidden from returning tracks attributed to any other reciter.
2. **Provider Transparency**: The originating provider, bitrate, and Loudness level (-16 LUFS) must always be specified in the track metadata.
3. **No Unlicensed Re-hosting**: Audio tracks hosted directly on official Waqf CDN servers are played directly via origin URLs, avoiding unauthorized third-party redistribution.
