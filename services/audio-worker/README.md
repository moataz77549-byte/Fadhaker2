# @fadhkur/audio-worker

Audio processing background worker utilizing FFmpeg/ffprobe for the **Fadhkur (فذكر)** platform.

## Key Capabilities
- **Loudness Normalization**: Enforces strict EBU R128 (-16 LUFS) standards for balanced recitation playback across all reciters.
- **Waveform Extraction**: Generates 100-point normalized JSON vectors for client-side audio visualizers.
- **Verification**: Generates SHA-256 integrity checksums saved to PostgreSQL `audio_tracks`.
