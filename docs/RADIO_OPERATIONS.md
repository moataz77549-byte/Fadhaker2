# Radio Operations & Playout Guide — Fadhkur (فذكر)

## 1. Managed Playout Topology
```
[Database Radio Schedules]
       │
       ▼
[Radio Engine Scheduler] (services/radio-engine)
       │ (Lease & Fencing Token Check)
       ▼
[Persistent Playout Queue] (Anti-Double-Play)
       │ (UNIX Socket / Telnet)
       ▼
[Liquidsoap 2.2] (infrastructure/liquidsoap/radio.liq)
       │ (Normalize -16.0 LUFS EBU R128 + Limiter)
       ▼
[Icecast 2 Cluster] (infrastructure/icecast/icecast.xml)
       ├── Mount /live/khashia.mp3 (128 kbps CBR MP3)
       └── Mount /live/murattal.mp3 (128 kbps CBR MP3)
       │
       ▼
[End Listeners (Web / Android Apps)]
```

## 2. Emergency Quranic Fallback (Zero-Silence Policy)
If the upstream queue exhausts or connection to the scheduling database is temporarily interrupted:
- Liquidsoap automatically falls back to `/var/audio/fallback/quran_emergency_fallback.mp3` (verified recitation of Surah Al-Fatihah and Surah Al-Baqarah).
- Listeners experience continuous recitation without hearing dead air, clicks, or unhandled errors.

## 3. Separation of Managed vs. External Virtual Radio
- **Managed Radio**: Internal playout controlled via our Liquidsoap and Icecast cluster where track selection, loudness, and reciter metadata are orchestrated directly.
- **External Virtual Radio**: Curated public cultural stations (e.g. Cairo Radio, Mecca Voice of Islam) streamed directly by the client from official authorized streaming endpoints. These stations are never re-encoded or run through the internal radio engine.
