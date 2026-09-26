import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/supabase_config.dart';
import '../listen/data/mp3quran_api.dart';
import 'video_channel.dart';

enum VideoCatalogFailure { configuration, network, authorization, server, malformed }

class VideoCatalogException implements Exception {
  const VideoCatalogException(this.failure, {this.statusCode});
  final VideoCatalogFailure failure;
  final int? statusCode;

  String get userMessage => switch (failure) {
        VideoCatalogFailure.configuration =>
          'إعداد الاتصال بالخادم غير مكتمل. جرّب نسخة التطبيق المحدّثة.',
        VideoCatalogFailure.network =>
          'تعذّر الاتصال بالخادم. تحقق من الإنترنت ثم حاول مجددًا.',
        VideoCatalogFailure.authorization =>
          'تعذّر الوصول إلى القنوات. يرجى تحديث التطبيق أو المحاولة لاحقًا.',
        VideoCatalogFailure.server =>
          'خدمة القنوات غير متاحة مؤقتًا. حاول لاحقًا.',
        VideoCatalogFailure.malformed =>
          'وصلت بيانات قنوات غير صالحة. حاول مجددًا لاحقًا.',
      };

  @override
  String toString() => 'VideoCatalogException($failure, statusCode: $statusCode)';
}

class VideoCatalogResult {
  const VideoCatalogResult(this.channels, {this.isCached = false, this.warning});
  final List<VideoChannel> channels;
  final bool isCached;
  final VideoCatalogException? warning;
}

/// Reads app.video_channels. A successful empty response is different from a
/// failed request; a previously cached catalog remains usable while offline.
class VideoChannelRepository {
  VideoChannelRepository({
    http.Client? client,
    Future<SharedPreferences> Function()? prefsProvider,
    String? baseUrl,
    String? publishableKey,
    Mp3QuranApi? mp3QuranApi,
  })  : _client = client ?? http.Client(),
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _baseUrl = baseUrl ?? SupabaseConfig.url,
        _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
        _mp3QuranApi = mp3QuranApi ?? Mp3QuranApi();

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefsProvider;
  final String _baseUrl;
  final String _publishableKey;
  final Mp3QuranApi _mp3QuranApi;
  bool get _useOfficialCatalog => _baseUrl == SupabaseConfig.url;

  static const _cacheKey = 'fadhkur.video_channels.v1';
  static const _cacheSavedAtKey = 'fadhkur.video_channels.saved_at.v1';
  static const _cacheTtl = Duration(days: 7);

  Future<VideoCatalogResult> loadResult({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final channels = await _fetchRemote(timeout: timeout);
      await _saveCache(channels);
      return VideoCatalogResult(channels);
    } on VideoCatalogException catch (error) {
      if (error.failure == VideoCatalogFailure.configuration ||
          error.failure == VideoCatalogFailure.authorization) rethrow;
      final cached = await _loadCache();
      if (cached.isNotEmpty) {
        return VideoCatalogResult(cached, isCached: true, warning: error);
      }
      rethrow;
    }
  }

  Future<List<VideoChannel>> load({
    Duration timeout = const Duration(seconds: 8),
  }) async => (await loadResult(timeout: timeout)).channels;

  Future<List<VideoChannel>> refresh({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final channels = await _fetchRemote(timeout: timeout);
    await _saveCache(channels);
    return channels;
  }

  /// Always resolve a live channel again before playback. The API owns the
  /// current HLS link, which may expire or change independently of our cache.
  Future<VideoChannel> resolveForPlayback(VideoChannel channel) async {
    if (!channel.id.startsWith('mp3quran:')) return channel;
    final id = channel.id.substring('mp3quran:'.length);
    final official = await _mp3QuranApi.liveTv();
    final fresh = _officialChannels(official);
    for (final item in fresh) {
      if (item.id == 'mp3quran:$id') return item;
    }
    throw const VideoCatalogException(VideoCatalogFailure.network);
  }

  List<VideoChannel> _officialChannels(List<Map<String, dynamic>> rows) =>
      rows.map((row) {
        final uri = Uri.tryParse('${row['url'] ?? ''}'.trim());
        if (uri == null || uri.scheme != 'https' ||
            !uri.path.toLowerCase().endsWith('.m3u8')) return null;
        return VideoChannel(
          id: 'mp3quran:${row['id']}',
          nameAr: '${row['name'] ?? ''}'.trim(),
          streamUrl: uri.toString(),
          sourceType: VideoSourceType.hls,
        );
      }).whereType<VideoChannel>()
          .where((channel) => channel.nameAr.isNotEmpty)
          .toList(growable: false);

  Future<List<VideoChannel>> _fetchRemote({required Duration timeout}) async {
    if (!_baseUrl.startsWith('https://') || _publishableKey.isEmpty) {
      throw const VideoCatalogException(VideoCatalogFailure.configuration);
    }
    final uri = Uri.parse('$_baseUrl/rest/v1/video_channels').replace(
      queryParameters: {
        'select': 'id,name_ar,name_en,stream_url,logo_url,is_active,sort_order,metadata',
        'is_active': 'eq.true',
        'order': 'sort_order.asc,name_ar.asc',
      },
    );
    late http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'apikey': _publishableKey,
        'Accept-Profile': 'app',
      }).timeout(timeout);
    } on TimeoutException {
      throw const VideoCatalogException(VideoCatalogFailure.network);
    } on SocketException {
      throw const VideoCatalogException(VideoCatalogFailure.network);
    } on http.ClientException {
      throw const VideoCatalogException(VideoCatalogFailure.network);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw VideoCatalogException(VideoCatalogFailure.authorization,
          statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VideoCatalogException(VideoCatalogFailure.server,
          statusCode: response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const VideoCatalogException(VideoCatalogFailure.malformed);
      }
      final curated = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          // Legacy hand-entered HLS and YouTube entries have no verifiable
          // official API identity; keep them out of this live catalog.
          .where((row) {
            final metadata = row['metadata'];
            final provider = metadata is Map ? '${metadata['provider']}' : '';
            return provider != 'user_configured' && provider != 'YouTube';
          })
          .map(VideoChannel.fromSupabase)
          .where((c) =>
              c.streamUrl.isNotEmpty &&
              (c.sourceType != VideoSourceType.youtube ||
                  c.youtubeVideoId != null))
          .toList(growable: false);
      if (!_useOfficialCatalog) return curated;
      try {
        final official = _officialChannels(await _mp3QuranApi.liveTv());
        final ids = official.map((c) => c.streamUrl).toSet();
        return [...official, ...curated.where((c) => !ids.contains(c.streamUrl))];
      } catch (_) {
        if (curated.isNotEmpty) return curated;
        throw const VideoCatalogException(VideoCatalogFailure.network);
      }
    } on FormatException {
      throw const VideoCatalogException(VideoCatalogFailure.malformed);
    } on TypeError {
      throw const VideoCatalogException(VideoCatalogFailure.malformed);
    }
  }

  Future<void> _saveCache(List<VideoChannel> channels) async {
    try {
      final prefs = await _prefsProvider();
      await prefs.setString(
        _cacheKey,
        jsonEncode(channels.map((c) => c.toJson()).toList()),
      );
      await prefs.setInt(_cacheSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Caching must not turn a valid network response into an error.
    }
  }

  Future<List<VideoChannel>> _loadCache() async {
    try {
      final prefs = await _prefsProvider();
      final raw = prefs.getString(_cacheKey);
      final savedAt = prefs.getInt(_cacheSavedAtKey);
      if (raw == null || savedAt == null ||
          DateTime.now().millisecondsSinceEpoch - savedAt > _cacheTtl.inMilliseconds) {
        return const [];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(VideoChannel.fromJson)
          .where((c) => c.streamUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _client.close();
    _mp3QuranApi.dispose();
  }
}

final videoChannelRepository = VideoChannelRepository();
