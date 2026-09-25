import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

enum PlaybackMode {
  radio,
  quranAudio,
  offlineFile,
}

class PlaybackState {
  final bool isPlaying;
  final PlaybackMode mode;
  final String currentTitle;
  final String currentSubtitle;
  final String currentUri;
  final Duration position;
  final Duration duration;
  final int bitrateKbps;
  final int? sleepTimerMinutes;
  final bool isMuted;
  final double speed;

  const PlaybackState({
    this.isPlaying = false,
    this.mode = PlaybackMode.radio,
    this.currentTitle = '',
    this.currentSubtitle = '',
    this.currentUri = '',
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bitrateKbps = 0,
    this.sleepTimerMinutes,
    this.isMuted = false,
    this.speed = 1.0,
  });

  PlaybackState copyWith({
    bool? isPlaying,
    PlaybackMode? mode,
    String? currentTitle,
    String? currentSubtitle,
    String? currentUri,
    Duration? position,
    Duration? duration,
    int? bitrateKbps,
    Object? sleepTimerMinutes = _noChange,
    bool? isMuted,
    double? speed,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      mode: mode ?? this.mode,
      currentTitle: currentTitle ?? this.currentTitle,
      currentSubtitle: currentSubtitle ?? this.currentSubtitle,
      currentUri: currentUri ?? this.currentUri,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sleepTimerMinutes: identical(sleepTimerMinutes, _noChange)
          ? this.sleepTimerMinutes
          : sleepTimerMinutes as int?,
      isMuted: isMuted ?? this.isMuted,
      speed: speed ?? this.speed,
    );
  }
}

const _noChange = Object();

FadhkurAudioHandler? _audioHandler;

/// Initializes the Android media session/foreground playback service.
///
/// The app is Android-only for the current product scope, so no Apple platform
/// configuration is touched here. In unit/widget tests the provider can still
/// create an in-process handler without registering the Android service.
Future<void> initializeAndroidAudioService() async {
  if (defaultTargetPlatform != TargetPlatform.android || _audioHandler != null) {
    return;
  }
  final handler = FadhkurAudioHandler();
  await audio_service.AudioService.init(
    builder: () => handler,
    config: const audio_service.AudioServiceConfig(
      androidNotificationChannelId: 'app.fadhkur.audio.playback',
      androidNotificationChannelName: 'تشغيل القرآن والإذاعة',
      androidNotificationChannelDescription:
          'التحكم في تشغيل التلاوات وإذاعات القرآن من شاشة القفل والإشعارات',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );
  _audioHandler = handler;
}

FadhkurAudioHandler _resolveAudioHandler() {
  return _audioHandler ??= FadhkurAudioHandler();
}

/// Single source of truth for Android media playback.
///
/// It owns [just_audio.AudioPlayer], publishes MediaSession state for Android's
/// notification/lock screen/headset controls, and performs one automatic radio
/// failover from the primary URL to the configured fallback URL.
class FadhkurAudioHandler extends audio_service.BaseAudioHandler
    with audio_service.SeekHandler {
  FadhkurAudioHandler() {
    _eventSubscription = _player.playbackEventStream.listen(
      (event) => playbackState.add(_transformEvent(event)),
      onError: (Object error, StackTrace stack) {
        unawaited(_recoverRadioFromError());
      },
    );
    _durationSubscription = _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (item == null || _isLive || duration == null) return;
      if (item.duration != duration) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  StreamSubscription<just_audio.PlaybackEvent>? _eventSubscription;
  StreamSubscription<Duration?>? _durationSubscription;

  bool _isLive = false;
  bool _fallbackUsed = false;
  bool _failoverInProgress = false;
  String? _fallbackUri;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<just_audio.PlayerState> get playerStateStream =>
      _player.playerStateStream;
  bool get playing => _player.playing;

  Future<void> loadAndPlay({
    required PlaybackMode mode,
    required String title,
    required String subtitle,
    required String logicalUri,
    required Duration fallbackDuration,
    String? fallbackUri,
    bool isFile = false,
  }) async {
    if (logicalUri.trim().isEmpty) {
      throw ArgumentError('Audio URI must not be empty');
    }

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _isLive = mode == PlaybackMode.radio;
    _fallbackUri = _cleanFallback(logicalUri, fallbackUri);
    _fallbackUsed = false;
    _failoverInProgress = false;

    final item = audio_service.MediaItem(
      id: logicalUri,
      album: mode == PlaybackMode.radio ? 'إذاعات فذكر' : 'القرآن الكريم',
      title: title,
      artist: subtitle.isEmpty ? null : subtitle,
      duration: _isLive ? null : fallbackDuration,
      extras: {
        'mode': mode.name,
        'fallback_uri': _fallbackUri,
        'is_live': _isLive,
      },
    );
    mediaItem.add(item);

    try {
      await _setSource(logicalUri, isFile: isFile);
    } catch (_) {
      final fallback = _fallbackUri;
      if (!_isLive || fallback == null) rethrow;
      _fallbackUsed = true;
      await _setSource(fallback, isFile: false);
    }

    // Do not await play(): for a live radio stream the returned Future may
    // remain pending until playback stops. Source preparation is already
    // complete, so start playback and return control to the caller so smart
    // scheduling, UI updates and retry timers can continue immediately.
    unawaited(_player.play());
  }

  String? _cleanFallback(String primary, String? fallback) {
    final value = fallback?.trim();
    if (value == null || value.isEmpty || value == primary.trim()) return null;
    return value;
  }

  Future<void> _setSource(String uri, {required bool isFile}) async {
    await _player.setAudioSource(
      isFile
          ? just_audio.AudioSource.file(uri)
          : just_audio.AudioSource.uri(Uri.parse(uri)),
    );
  }

  Future<void> _recoverRadioFromError() async {
    final fallback = _fallbackUri;
    if (!_isLive ||
        fallback == null ||
        _fallbackUsed ||
        _failoverInProgress) {
      return;
    }
    _failoverInProgress = true;
    final shouldResume = _player.playing;
    try {
      _fallbackUsed = true;
      await _setSource(fallback, isFile: false);
      if (shouldResume) unawaited(_player.play());
    } catch (_) {
      await _player.stop();
    } finally {
      _failoverInProgress = false;
    }
  }

  @override
  Future<void> play() async {
    // just_audio's play Future may stay pending for the lifetime of a live
    // stream. MediaSession commands should acknowledge immediately.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    await _player.setSpeed(speed);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: audio_service.AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      ),
    );
  }

  audio_service.PlaybackState _transformEvent(
    just_audio.PlaybackEvent event,
  ) {
    final processingState = switch (_player.processingState) {
      just_audio.ProcessingState.idle =>
        audio_service.AudioProcessingState.idle,
      just_audio.ProcessingState.loading =>
        audio_service.AudioProcessingState.loading,
      just_audio.ProcessingState.buffering =>
        audio_service.AudioProcessingState.buffering,
      just_audio.ProcessingState.ready =>
        audio_service.AudioProcessingState.ready,
      just_audio.ProcessingState.completed =>
        audio_service.AudioProcessingState.completed,
    };

    return audio_service.PlaybackState(
      controls: [
        if (_player.playing)
          audio_service.MediaControl.pause
        else
          audio_service.MediaControl.play,
        audio_service.MediaControl.stop,
      ],
      systemActions: _isLive
          ? const {}
          : const {
              audio_service.MediaAction.seek,
              audio_service.MediaAction.seekForward,
              audio_service.MediaAction.seekBackward,
            },
      androidCompactActionIndices: const [0, 1],
      processingState: processingState,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  Future<void> disposeHandler() async {
    await _eventSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _player.dispose();
  }
}

class FadhkurAudioNotifier extends StateNotifier<PlaybackState> {
  FadhkurAudioNotifier()
      : _handler = _resolveAudioHandler(),
        super(const PlaybackState()) {
    _subscriptions.add(
      _handler.positionStream.listen((position) {
        state = state.copyWith(position: position);
      }),
    );
    _subscriptions.add(
      _handler.durationStream.listen((duration) {
        if (duration != null) state = state.copyWith(duration: duration);
      }),
    );
    _subscriptions.add(
      _handler.playerStateStream.listen((playerState) {
        state = state.copyWith(
          isPlaying: playerState.playing &&
              playerState.processingState !=
                  just_audio.ProcessingState.completed,
        );
      }),
    );
  }

  final FadhkurAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _sleepTimer;

  Future<void> playRadio(
    String stationName,
    String trackName,
    String streamUrl, {
    String? fallbackUrl,
    int bitrateKbps = 0,
  }) async {
    state = state.copyWith(bitrateKbps: bitrateKbps);
    await _play(
      mode: PlaybackMode.radio,
      title: stationName,
      subtitle: trackName,
      uri: streamUrl,
      fallbackUri: fallbackUrl,
      fallbackDuration: Duration.zero,
    );
  }

  Future<void> playQuranTrack(
    String surahName,
    String reciterName,
    String audioUrl, {
    Duration? duration,
  }) async {
    await _play(
      mode: PlaybackMode.quranAudio,
      title: surahName,
      subtitle: reciterName,
      uri: audioUrl,
      fallbackDuration: duration ?? const Duration(minutes: 20),
    );
  }

  Future<void> playOfflineTrack(
    String surahName,
    String reciterName,
    String localPath,
  ) async {
    await _play(
      mode: PlaybackMode.offlineFile,
      title: '$surahName (تنزيل محلي)',
      subtitle: reciterName,
      uri: localPath,
      fallbackDuration: const Duration(minutes: 20),
      isFile: true,
    );
  }

  Future<void> _play({
    required PlaybackMode mode,
    required String title,
    required String subtitle,
    required String uri,
    required Duration fallbackDuration,
    String? fallbackUri,
    bool isFile = false,
  }) async {
    state = state.copyWith(
      isPlaying: false,
      mode: mode,
      currentTitle: title,
      currentSubtitle: subtitle,
      currentUri: uri,
      position: Duration.zero,
      duration: fallbackDuration,
    );
    try {
      await _handler.loadAndPlay(
        mode: mode,
        title: title,
        subtitle: subtitle,
        logicalUri: uri,
        fallbackDuration: fallbackDuration,
        fallbackUri: fallbackUri,
        isFile: isFile,
      );
    } catch (_) {
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> togglePlayPause() async {
    if (_handler.playing) {
      await _handler.pause();
    } else if (state.currentUri.isNotEmpty) {
      try {
        await _handler.play();
      } catch (_) {
        state = state.copyWith(isPlaying: false);
      }
    }
  }

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> stop() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    await _handler.stop();
    state = state.copyWith(
      isPlaying: false,
      position: Duration.zero,
      sleepTimerMinutes: null,
    );
  }

  void setSleepTimer(int? minutes) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(sleepTimerMinutes: null);
    if (minutes != null && minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), stop);
      state = state.copyWith(sleepTimerMinutes: minutes);
    }
  }

  Future<void> setSpeed(double speed) async {
    if (speed <= 0) return;
    try {
      await _handler.setSpeed(speed);
      state = state.copyWith(speed: speed);
    } catch (_) {}
  }

  Future<void> resetSpeed() => setSpeed(1.0);

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

final audioPlaybackProvider =
    StateNotifierProvider<FadhkurAudioNotifier, PlaybackState>((ref) {
  return FadhkurAudioNotifier();
});
