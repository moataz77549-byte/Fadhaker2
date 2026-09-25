package app.fadhkur.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.fadhkur.model.DownloadStatus
import app.fadhkur.model.DownloadTask
import app.fadhkur.model.PlaylistItem
import app.fadhkur.model.Playlist
import app.fadhkur.repository.FirebaseAuthRepository
import app.fadhkur.repository.FirestoreRepository
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.service.PlaybackState
import app.fadhkur.service.FadhkurAudioHandler
import com.google.firebase.auth.FirebaseUser
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainViewModel(
    val repository: FadhkurRepository = FadhkurRepository(),
    val authRepository: FirebaseAuthRepository = FirebaseAuthRepository(),
    val firestoreRepository: FirestoreRepository = FirestoreRepository()
) : ViewModel() {

    val currentUser: StateFlow<FirebaseUser?> = authRepository.currentUserState
    val playbackState: StateFlow<PlaybackState> = FadhkurAudioHandler.playbackState

    private val _favorites = MutableStateFlow<Set<String>>(setOf("station_makkah_live", "reciter_minshawi"))
    val favorites: StateFlow<Set<String>> = _favorites.asStateFlow()

    private val _downloads = MutableStateFlow<List<DownloadTask>>(repository.downloads)
    val downloads: StateFlow<List<DownloadTask>> = _downloads.asStateFlow()

    private val _playlists = MutableStateFlow<List<Playlist>>(repository.playlists)
    val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

    private var favoritesJob: Job? = null

    init {
        // Observe auth state and sync favorites with Firestore if user is authenticated
        viewModelScope.launch {
            authRepository.currentUserState.collect { user ->
                favoritesJob?.cancel()
                if (user != null) {
                    favoritesJob = launch {
                        firestoreRepository.observeFavorites(user.uid).collect { remoteFavs ->
                            if (remoteFavs.isNotEmpty()) {
                                _favorites.value = remoteFavs
                            }
                        }
                    }
                }
            }
        }
    }

    fun toggleFavorite(id: String) {
        val current = _favorites.value.toMutableSet()
        if (current.contains(id)) {
            current.remove(id)
        } else {
            current.add(id)
        }
        _favorites.value = current

        val user = authRepository.currentUser
        if (user != null) {
            firestoreRepository.syncFavorites(user.uid, current)
        }
    }

    fun playSurah(surahNumber: Int, surahName: String) {
        val paddedNumber = surahNumber.toString().padStart(3, '0')
        val url = "https://audio.fadhkur.app/$paddedNumber.mp3"
        FadhkurAudioHandler.playQuranTrack(surahName, "الشيخ محمد صديق المنشاوي", url)
    }

    fun playTrack(title: String, subtitle: String, url: String) {
        FadhkurAudioHandler.playQuranTrack(title, subtitle, url)
    }

    fun playStation(name: String, streamUrl: String) {
        FadhkurAudioHandler.playRadioStream(name, streamUrl)
    }

    fun togglePlayPause() {
        FadhkurAudioHandler.togglePlayPause()
    }

    fun startDownload(surahNumber: Int, surahName: String) {
        val id = "dl_${System.currentTimeMillis()}"
        val reciter = "الشيخ محمد صديق المنشاوي"
        val hash = app.fadhkur.service.DownloadVerifier.generateDeterministicChecksum(surahNumber, reciter)
        val newTask = DownloadTask(
            id = id,
            surahNumber = surahNumber,
            surahNameAr = surahName,
            reciterNameAr = reciter,
            expectedSha256 = hash,
            progressPercent = 100,
            status = DownloadStatus.COMPLETED,
            localPath = "/data/user/0/app.fadhkur/files/quran/${surahNumber.toString().padStart(3, '0')}.mp3",
            totalBytes = 28400000L,
            downloadedBytes = 28400000L
        )
        _downloads.value = listOf(newTask) + _downloads.value
    }

    fun deleteDownload(id: String) {
        _downloads.value = _downloads.value.filter { it.id != id }
    }

    fun createPlaylist(name: String) {
        val id = "pl_${System.currentTimeMillis()}"
        val newPl = Playlist(
            id = id,
            name = name,
            items = listOf(
                PlaylistItem("pi_1", "سورة الفاتحة", "المنشاوي - ترتيل", "https://audio.fadhkur.app/001.mp3", 1),
                PlaylistItem("pi_2", "سورة الكهف", "المنشاوي - تجويد", "https://audio.fadhkur.app/018.mp3", 18)
            )
        )
        _playlists.value = _playlists.value + newPl
    }

    fun deletePlaylist(id: String) {
        _playlists.value = _playlists.value.filter { it.id != id }
    }
}
