package app.fadhkur.model

data class RadioStation(
  val id: String,
  val nameAr: String,
  val streamUrl: String,
  val currentTrack: String,
  val bitrateKbps: Int = 128,
  val isFeatured: Boolean = false,
  val listenerCount: Int = 0,
  val fallbackUrl: String? = null
)

data class ReciterProfile(
  val id: String,
  val nameAr: String,
  val riwaya: String,
  val surahsCount: Int = 114,
  val bio: String = "",
  val provider: String = "King Fahd Complex / Fadhkur CDN",
  val audioQuality: String = "192 kbps • MP3"
)

data class PlaylistItem(
  val id: String,
  val title: String,
  val subtitle: String,
  val audioUrl: String,
  val surahNumber: Int,
  val reciterId: String
)

data class Playlist(
  val id: String,
  val name: String,
  val items: List<PlaylistItem> = emptyList(),
  val createdAt: Long = System.currentTimeMillis()
)

data class DownloadTask(
  val id: String,
  val surahNumber: Int,
  val surahNameAr: String,
  val reciterNameAr: String,
  val expectedSha256: String,
  val progressPercent: Int = 0,
  val status: DownloadStatus = DownloadStatus.QUEUED,
  val localPath: String? = null,
  val totalBytes: Long = 0L,
  val downloadedBytes: Long = 0L
)

enum class DownloadStatus {
  QUEUED,
  DOWNLOADING,
  PAUSED,
  FAILED,
  COMPLETED
}

data class PrayerTimesData(
  val city: String = "الرياض",
  val fajr: String = "04:32",
  val sunrise: String = "05:51",
  val dhuhr: String = "11:58",
  val asr: String = "15:24",
  val maghrib: String = "18:05",
  val isha: String = "19:35",
  val nextPrayerName: String = "المغرب",
  val nextPrayerRemaining: String = "01:12:45"
)

data class DhikrItem(
  val id: String,
  val title: String,
  val text: String,
  val targetCount: Int,
  val currentCount: Int = 0,
  val reward: String = ""
)

data class MemorizationPlan(
  val id: String,
  val title: String,
  val targetSurah: String,
  val currentVerse: Int,
  val targetVerse: Int,
  val completedPercent: Int,
  val dueReviewDays: Int
)

data class RemoteFeatureFlags(
  val radioEnabled: Boolean = true,
  val offlineDownloadsEnabled: Boolean = true,
  val prayerTimesEnabled: Boolean = true,
  val adhkarEnabled: Boolean = true,
  val learningEnabled: Boolean = true,
  val announcementsEnabled: Boolean = true,
  val maintenanceMode: Boolean = false,
  val minSupportedVersion: String = "1.0.0",
  val homeSectionsOrder: List<String> = listOf("featured", "prayer", "memorization", "stations", "reciters", "offline")
)
