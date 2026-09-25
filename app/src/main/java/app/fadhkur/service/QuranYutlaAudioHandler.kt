package app.fadhkur.service

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class PlaybackMode {
  RADIO,
  QURAN_AUDIO,
  OFFLINE_FILE
}

data class PlaybackState(
  val isPlaying: Boolean = false,
  val mode: PlaybackMode = PlaybackMode.RADIO,
  val currentTitle: String = "إذاعة التلاوات الخاشعة",
  val currentSubtitle: String = "سورة مريم — الشيخ عبد الباسط عبد الصمد",
  val currentUri: String = "https://stream.fadhkur.app/live/khashia.mp3",
  val currentPositionMs: Long = 0L,
  val durationMs: Long = 1800000L, // 30 mins example
  val bitrateKbps: Int = 128,
  val sleepTimerMinutes: Int? = null,
  val isMuted: Boolean = false
)

/**
 * Single centralized Playback Controller (PlaybackPort)
 * Enforces one active audio stream across Radio, Quran recitations, and Offline downloads.
 */
object FadhkurAudioHandler {
  private val _state = MutableStateFlow(PlaybackState(isPlaying = true))
  val state: StateFlow<PlaybackState> = _state.asStateFlow()

  fun playRadio(stationName: String, trackName: String, streamUrl: String) {
    _state.value = _state.value.copy(
      isPlaying = true,
      mode = PlaybackMode.RADIO,
      currentTitle = stationName,
      currentSubtitle = trackName,
      currentUri = streamUrl,
      currentPositionMs = 0L,
      durationMs = 0L
    )
  }

  fun playQuranTrack(surahName: String, reciterName: String, audioUrl: String, durationMs: Long = 1200000L) {
    _state.value = _state.value.copy(
      isPlaying = true,
      mode = PlaybackMode.QURAN_AUDIO,
      currentTitle = surahName,
      currentSubtitle = reciterName,
      currentUri = audioUrl,
      currentPositionMs = 0L,
      durationMs = durationMs
    )
  }

  fun playOfflineTrack(surahName: String, reciterName: String, localPath: String) {
    _state.value = _state.value.copy(
      isPlaying = true,
      mode = PlaybackMode.OFFLINE_FILE,
      currentTitle = "$surahName (تنزيل محلي)",
      currentSubtitle = reciterName,
      currentUri = localPath,
      currentPositionMs = 0L,
      durationMs = 1200000L
    )
  }

  fun togglePlayPause() {
    _state.value = _state.value.copy(isPlaying = !_state.value.isPlaying)
  }

  fun seekTo(positionMs: Long) {
    _state.value = _state.value.copy(currentPositionMs = positionMs)
  }

  fun stop() {
    _state.value = _state.value.copy(isPlaying = false, currentPositionMs = 0L)
  }

  fun setSleepTimer(minutes: Int?) {
    _state.value = _state.value.copy(sleepTimerMinutes = minutes)
  }
}
