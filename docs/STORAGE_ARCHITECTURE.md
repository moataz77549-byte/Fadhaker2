# Storage Architecture & Policies — Fadhkur (فذكر)

| Bucket Name | Access | Allowed MIME Types | File Size Limit |
| :--- | :--- | :--- | :--- |
| `quran-mushaf` | Public Read | `image/webp`, `application/json` | 50 MB |
| `reciter-artwork` | Public Read | `image/webp`, `image/jpeg`, `image/png` | 10 MB |
| `station-artwork` | Public Read | `image/webp`, `image/jpeg`, `image/png` | 10 MB |
| `app-content` | Public Read | `application/json`, `text/plain` | 50 MB |
| `media-source-private` | Strict Private | `audio/mpeg`, `audio/wav`, `audio/flac` | 500 MB |
| `media-processed-private` | Strict Private | `audio/mpeg`, `application/json` | 500 MB |
| `admin-uploads-private` | Strict Private | `audio/mpeg`, `application/json`, `image/webp` | 500 MB |
| `exports-private` | Strict Private | `application/json`, `text/csv`, `application/zip` | 100 MB |
