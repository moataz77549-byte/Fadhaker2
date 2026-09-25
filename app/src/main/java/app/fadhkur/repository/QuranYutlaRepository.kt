package app.fadhkur.repository

import app.fadhkur.model.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class FadhkurRepository {

  // Remote config with safe local fallback
  private val _featureFlags = MutableStateFlow(RemoteFeatureFlags())
  val featureFlags: StateFlow<RemoteFeatureFlags> = _featureFlags.asStateFlow()

  // Favorites (reciters, stations, surahs)
  private val _favoriteIds = MutableStateFlow(mutableSetOf("station-1", "reciter-1", "surah-18"))
  val favoriteIds: StateFlow<Set<String>> = _favoriteIds.asStateFlow()

  // Playlists
  private val _playlists = MutableStateFlow(
    listOf(
      Playlist(
        id = "pl-1",
        name = "تلاوات الفجر الخاشعة",
        items = listOf(
          PlaylistItem("p1", "سورة الفاتحة", "الشيخ محمود خليل الحصري", "https://audio.fadhkur.app/001.mp3", 1, "reciter-3"),
          PlaylistItem("p2", "سورة الكهف", "الشيخ عبد الباسط عبد الصمد", "https://audio.fadhkur.app/018.mp3", 18, "reciter-1")
        )
      ),
      Playlist(
        id = "pl-2",
        name = "ورد النوم والسكينة",
        items = listOf(
          PlaylistItem("p3", "سورة الملك", "الشيخ محمد صديق المنشاوي", "https://audio.fadhkur.app/067.mp3", 67, "reciter-2")
        )
      )
    )
  )
  val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

  // Offline Downloads
  private val _downloads = MutableStateFlow(
    listOf(
      DownloadTask(
        id = "dl-1",
        surahNumber = 18,
        surahNameAr = "سورة الكهف",
        reciterNameAr = "الشيخ عبد الباسط عبد الصمد",
        expectedSha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        progressPercent = 100,
        status = DownloadStatus.COMPLETED,
        localPath = "/data/user/0/app.fadhkur/files/quran/018_abdulbasit.mp3",
        totalBytes = 28400000L,
        downloadedBytes = 28400000L
      ),
      DownloadTask(
        id = "dl-2",
        surahNumber = 36,
        surahNameAr = "سورة يس",
        reciterNameAr = "الشيخ محمد صديق المنشاوي",
        expectedSha256 = "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb",
        progressPercent = 65,
        status = DownloadStatus.DOWNLOADING,
        localPath = "/data/user/0/app.fadhkur/files/quran/036_minshawi.mp3.part",
        totalBytes = 16200000L,
        downloadedBytes = 10530000L
      )
    )
  )
  val downloads: StateFlow<List<DownloadTask>> = _downloads.asStateFlow()

  // Radio Stations
  val stations = listOf(
    RadioStation("station-1", "إذاعة التلاوات الخاشعة", "https://stream.fadhkur.app/live/khashia.mp3", "سورة مريم — الشيخ عبد الباسط عبد الصمد", 128, true, 1420),
    RadioStation("station-2", "إذاعة المصحف المرتل", "https://stream.fadhkur.app/live/murattal.mp3", "سورة البقرة — الشيخ محمود خليل الحصري", 128, true, 890),
    RadioStation("station-3", "إذاعة تلاوات الحرمين الشريفين", "https://stream.fadhkur.app/live/haramain.mp3", "تلاوات المسجد الحرام والمسجد النبوي", 128, false, 640),
    RadioStation("station-4", "إذاعة الشيخ محمد صديق المنشاوي", "https://stream.fadhkur.app/live/minshawi.mp3", "المصحف المجود والمرتل", 128, false, 510)
  )

  // Reciters
  val reciters = listOf(
    ReciterProfile("reciter-1", "الشيخ عبد الباسط عبد الصمد", "المصحف المجود • حفص عن عاصم", 114, "من كبار أعلام قراء القرآن الكريم في العالم الإسلامي.", "مجمع الملك فهد / أرشيف إذاعة القرآن", "192 kbps • MP3"),
    ReciterProfile("reciter-2", "الشيخ محمد صديق المنشاوي", "المصحف المرتل • حفص عن عاصم", 114, "تميز بنبرته الخاشعة الباكية وصوته الرخيم.", "مجمع الملك فهد / أرشيف القاهرة", "192 kbps • MP3"),
    ReciterProfile("reciter-3", "الشيخ محمود خليل الحصري", "المصحف المرتل • رواية ورش عن نافع", 114, "شيخ عموم المقارئ المصرية الأسبق وأول من سجل المصحف المرتل.", "مجمع الملك فهد", "192 kbps • MP3"),
    ReciterProfile("reciter-4", "الشيخ علي عبد الله جابر", "تلاوات الحرم المكي • حفص عن عاصم", 114, "إمام المسجد الحرام الأسبق رحمه الله.", "أرشيف الحرم المكي الشريف", "192 kbps • MP3")
  )

  // Prayer Times (Calculated offline / cached)
  val prayerTimes = PrayerTimesData()

  // Learning / Dhikr data
  val adhkarList = listOf(
    DhikrItem("d-1", "أذكار الصباح", "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لاَ إِلَـهَ إِلاَّ اللهُ وَحْدَهُ لاَ شَرِيكَ لَهُ...", 1, 1, "حفظ من الشرور حتى يمسي"),
    DhikrItem("d-2", "سيد الاستغفار", "اللَّهُمَّ أَنْتَ رَبِّي لاَ إِلَهَ إِلاَّ أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ...", 1, 0, "موجبة للجنة لمن قالها موقنا بها"),
    DhikrItem("d-3", "التسبيح والتحميد", "سُبْحَانَ اللهِ وَبِحَمْدِهِ", 100, 33, "حُطّت خطاياه وإن كانت مثل زبد البحر")
  )

  val memorizationPlans = listOf(
    MemorizationPlan("m-1", "خطة حفظ جزء عمّ", "سورة النبأ", 25, 40, 62, 0),
    MemorizationPlan("m-2", "مراجعة سورة الكهف الأسبوعية", "سورة الكهف", 110, 110, 100, 2)
  )

  fun toggleFavorite(id: String) {
    val current = _favoriteIds.value.toMutableSet()
    if (current.contains(id)) {
      current.remove(id)
    } else {
      current.add(id)
    }
    _favoriteIds.value = current
  }

  fun createPlaylist(name: String) {
    val newPl = Playlist(id = "pl-${System.currentTimeMillis()}", name = name, items = emptyList())
    _playlists.value = _playlists.value + newPl
  }

  fun deletePlaylist(playlistId: String) {
    _playlists.value = _playlists.value.filter { it.id != playlistId }
  }

  fun addDownload(surahNumber: Int, surahName: String, reciterName: String) {
    val newTask = DownloadTask(
      id = "dl-${System.currentTimeMillis()}",
      surahNumber = surahNumber,
      surahNameAr = surahName,
      reciterNameAr = reciterName,
      expectedSha256 = "verified_canonical_hash_sha256",
      progressPercent = 10,
      status = DownloadStatus.DOWNLOADING,
      totalBytes = 25000000L,
      downloadedBytes = 2500000L
    )
    _downloads.value = _downloads.value + newTask
  }

  fun deleteDownload(downloadId: String) {
    _downloads.value = _downloads.value.filter { it.id != downloadId }
  }
}
