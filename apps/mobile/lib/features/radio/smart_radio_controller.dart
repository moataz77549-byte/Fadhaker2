import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_models.dart';
import '../../core/services/audio_playback_service.dart';
import '../../core/services/prayer_times_service.dart';
import 'radio_station.dart';
import 'smart_radio_service.dart';

class SmartRadioState {
  const SmartRadioState({
    this.active = false,
    this.loading = false,
    this.usingFallback = false,
    this.resolution,
    this.message,
  });

  final bool active;
  final bool loading;
  final bool usingFallback;
  final SmartRadioResolution? resolution;
  final String? message;

  SmartRadioState copyWith({
    bool? active,
    bool? loading,
    bool? usingFallback,
    SmartRadioResolution? resolution,
    String? message,
    bool clearMessage = false,
  }) {
    return SmartRadioState(
      active: active ?? this.active,
      loading: loading ?? this.loading,
      usingFallback: usingFallback ?? this.usingFallback,
      resolution: resolution ?? this.resolution,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class SmartRadioController extends StateNotifier<SmartRadioState> {
  SmartRadioController(this.ref) : super(const SmartRadioState());

  final Ref ref;
  Timer? _refreshTimer;
  PrayerTimesModel? _prayerTimes;
  DateTime? _prayerTimesLoadedAt;
  int _session = 0;

  Future<void> start() async {
    final session = ++_session;
    _refreshTimer?.cancel();
    state = state.copyWith(
      active: true,
      loading: true,
      clearMessage: true,
    );

    final cached = await smartRadioService.loadCached();
    if (session != _session || !state.active) return;
    if (cached != null) {
      await _playResolution(cached);
      if (session != _session || !state.active) return;
      state = state.copyWith(
        resolution: cached,
        usingFallback: true,
      );
    }

    try {
      await _loadPrayerTimes(force: true);
      if (session != _session || !state.active) return;
      await _resolveAndApply(session, allowTakeover: true);
    } catch (_) {
      if (session != _session || !state.active) return;
      if (cached == null) {
        await _playBuiltinFallback();
      }
      state = state.copyWith(
        loading: false,
        usingFallback: true,
        message: 'يتم تشغيل الوضع الاحتياطي حتى تتوفر الخدمة الذكية.',
      );
      _scheduleRetry(const Duration(minutes: 10), session);
    }
  }

  /// Stops automatic source switching without stopping the audio itself.
  /// Called before the user explicitly selects a normal station.
  void deactivate() {
    _session++;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    state = state.copyWith(
      active: false,
      loading: false,
      clearMessage: true,
    );
  }

  Future<void> refreshNow() async {
    if (!state.active) return;
    final session = _session;

    // Respect any playback the user selected outside Smart Radio. A scheduled
    // refresh must never steal audio focus back from a Qur'an track, download
    // or normal radio station.
    final expectedUri = state.resolution?.program.streamUrl;
    final playback = ref.read(audioPlaybackProvider);
    if (expectedUri != null &&
        (playback.mode != PlaybackMode.radio ||
            playback.currentUri != expectedUri)) {
      deactivate();
      return;
    }

    try {
      await _loadPrayerTimes(force: false);
      if (session != _session || !state.active) return;
      await _resolveAndApply(session, allowTakeover: false);
    } catch (_) {
      if (session != _session || !state.active) return;
      state = state.copyWith(
        loading: false,
        usingFallback: true,
        message: 'تعذّر تحديث البرنامج الآن؛ يستمر المصدر الحالي.',
      );
      _scheduleRetry(const Duration(minutes: 10), session);
    }
  }

  Future<void> _loadPrayerTimes({required bool force}) async {
    final loadedAt = _prayerTimesLoadedAt;
    if (!force &&
        _prayerTimes != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(hours: 4)) {
      return;
    }
    _prayerTimes = await prayerTimesService.loadToday();
    _prayerTimesLoadedAt = DateTime.now();
  }

  Future<void> _resolveAndApply(
    int session, {
    required bool allowTakeover,
  }) async {
    final prayers = _prayerTimes;
    if (prayers == null) return;
    state = state.copyWith(loading: true, clearMessage: true);

    final ownedBefore = state.resolution?.program.streamUrl;
    final resolution = await smartRadioService.resolve(prayers);
    if (session != _session || !state.active) return;

    final playback = ref.read(audioPlaybackProvider);
    if (!allowTakeover &&
        ownedBefore != null &&
        (playback.mode != PlaybackMode.radio ||
            playback.currentUri != ownedBefore)) {
      deactivate();
      return;
    }

    final currentUri = playback.currentUri;
    if (currentUri != resolution.program.streamUrl) {
      await _playResolution(resolution);
      if (session != _session || !state.active) return;
    }

    final fallback =
        resolution.cachedFallback || resolution.program.fallbackMode;
    state = state.copyWith(
      loading: false,
      resolution: resolution,
      usingFallback: fallback,
      message: fallback ? 'يتم تشغيل آخر برنامج محفوظ مؤقتًا.' : null,
      clearMessage: !fallback,
    );

    final seconds =
        resolution.program.refreshAfterSeconds.clamp(60, 7200).toInt();
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(refreshNow()),
    );
  }

  Future<void> _playResolution(SmartRadioResolution resolution) {
    return ref.read(audioPlaybackProvider.notifier).playRadio(
          resolution.channelName,
          resolution.nowLabel,
          resolution.program.streamUrl,
          fallbackUrl: resolution.program.fallbackUrl,
          bitrateKbps: resolution.program.bitrateKbps,
        );
  }

  Future<void> _playBuiltinFallback() async {
    if (builtinRadioStations.isEmpty) return;
    final index = DateTime.now().hour % builtinRadioStations.length;
    final station = builtinRadioStations[index];
    await ref.read(audioPlaybackProvider.notifier).playRadio(
          'إذاعة فذكر الذكية',
          'الوضع الاحتياطي • ${station.nameAr}',
          station.streamUrl,
          fallbackUrl: station.fallbackUrl,
          bitrateKbps: station.bitrateKbps,
        );
    // Treat the builtin fallback as Smart Radio-owned playback. This lets
    // refreshNow retry the resolver without mistaking our own fallback for a
    // manual station selection, while still respecting later user takeovers.
    state = state.copyWith(
      resolution: _builtinFallbackResolution(station),
      usingFallback: true,
    );
  }

  SmartRadioResolution _builtinFallbackResolution(RadioStation station) {
    return SmartRadioResolution(
      channelName: 'إذاعة فذكر الذكية',
      channelSlug: 'fadhkur-smart',
      program: SmartRadioProgram(
        key: 'builtin_fallback',
        title: 'الوضع الاحتياطي',
        sourceType: 'LIVE_STATION',
        sourceId: 'builtin:${station.id}',
        sourceName: station.nameAr,
        streamUrl: station.streamUrl,
        fallbackUrl: station.fallbackUrl,
        bitrateKbps: station.bitrateKbps,
        refreshAfterSeconds: 600,
        transitionPolicy: 'SOFT_DEADLINE',
        fallbackMode: true,
      ),
      timezone: _prayerTimes?.timezone ?? '',
      generatedAt: DateTime.now().toUtc(),
      cachedFallback: true,
    );
  }

  void _scheduleRetry(Duration delay, int session) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(delay, () {
      if (session == _session && state.active) {
        unawaited(refreshNow());
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final smartRadioProvider =
    StateNotifierProvider<SmartRadioController, SmartRadioState>(
  (ref) => SmartRadioController(ref),
);
