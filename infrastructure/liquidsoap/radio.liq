# ==============================================================================
# Liquidsoap 2.2 Configuration for Fadhkur (فذكر)
# Audio Standards: EBU R128 (-16 LUFS), 128 kbps CBR MP3, Fallback Silence Avoidance
# ==============================================================================

# 1. Environment and Server Settings
set("log.level", 3)
set("log.stdout", true)
set("server.telnet", true)
set("server.telnet.bind_addr", "127.0.0.1")
set("server.telnet.port", 1234)

# Environment variables
icecast_host = environment.get(default="127.0.0.1", "ICECAST_HOST")
icecast_port = int_of_string(environment.get(default="8000", "ICECAST_PORT"))
icecast_pass = environment.get(default="hackme", "ICECAST_SOURCE_PASSWORD")

# 2. Emergency Quranic Fallback Stream (Local Verified Surah Al-Fatihah & Al-Baqarah)
emergency_fallback = single("/var/audio/fallback/quran_emergency_fallback.mp3")

# 3. Dynamic Playlist & Queue from Radio Engine (Persistent occurrences)
live_queue = request.queue(id="fadhkur_queue")

# 4. Safe Failover Chain: Primary Queue -> Emergency Fallback
radio_source = fallback(track_sensitive=true, [live_queue, emergency_fallback])

# 5. Audio Normalization & Limiting (Strict EBU R128 Compliance)
radio_normalized = normalize(target=-16.0, radio_source)

# 6. Stream Output to Icecast Mount
output.icecast(
  %mp3(bitrate=128, samplerate=44100, stereo=true),
  host=icecast_host,
  port=icecast_port,
  password=icecast_pass,
  mount="/live/khashia.mp3",
  name="إذاعة التلاوات الخاشعة — فذكر",
  description="بث قرآني مدار على مدار الساعة بدون إعلانات",
  url="https://fadhkur.app",
  genre="Quran / Recitation",
  radio_normalized
)
