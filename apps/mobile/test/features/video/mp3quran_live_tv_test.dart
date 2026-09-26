import 'dart:convert';

import 'package:fadhkur_mobile/features/listen/data/mp3quran_api.dart';
import 'package:fadhkur_mobile/features/video/video_channel.dart';
import 'package:fadhkur_mobile/features/video/video_channel_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('official live TV endpoint supplies fresh HLS URL, not embedded links', () async {
    final api = Mp3QuranApi(client: MockClient((request) async {
      expect(request.url.path, '/api/v3/live-tv');
      expect(request.url.queryParameters['language'], 'ar');
      return http.Response.bytes(utf8.encode(
        '{"livetv":[{"id":3,"name":"قناة القرآن","url":"https://stream.example/live/new.m3u8"}]}',
      ), 200);
    }));
    final repository = VideoChannelRepository(
      baseUrl: 'https://example.supabase.co', publishableKey: 'test-key',
      client: MockClient((_) async => http.Response('[]', 200)),
      mp3QuranApi: api,
    );
    final fresh = await repository.resolveForPlayback(const VideoChannel(
      id: 'mp3quran:3', nameAr: 'قناة القرآن',
      streamUrl: 'https://stream.example/live/expired.m3u8',
    ));
    expect(fresh.sourceType, VideoSourceType.hls);
    expect(fresh.streamUrl, 'https://stream.example/live/new.m3u8');
    repository.dispose();
  });

  test('malformed official API response fails closed', () async {
    final api = Mp3QuranApi(client: MockClient((_) async => http.Response('{}', 200)));
    await expectLater(api.liveTv(), throwsFormatException);
    api.dispose();
  });
}
