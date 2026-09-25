import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fadhkur_mobile/features/video/video_channel_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  VideoChannelRepository repository(http.Client client, {String key = 'test-key'}) =>
      VideoChannelRepository(
        client: client,
        baseUrl: 'https://example.supabase.co',
        publishableKey: key,
      );

  final row = '[{"id":"channel-1","name_ar":"البث","stream_url":"https://example.com/live.m3u8","is_active":true}]';

  test('successful empty response differs from connection failure', () async {
    final empty = repository(MockClient((request) async {
      expect(request.headers['apikey'], 'test-key');
      expect(request.headers['Accept-Profile'], 'app');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('[]', 200);
    }));
    expect((await empty.loadResult()).channels, isEmpty);
    empty.dispose();

    final offline = repository(MockClient((request) async {
      throw const http.ClientException('offline');
    }));
    await expectLater(offline.loadResult(), throwsA(
      isA<VideoCatalogException>().having(
        (e) => e.failure, 'failure', VideoCatalogFailure.network,
      ),
    ));
    offline.dispose();
  });

  test('network failure uses previously cached channels with warning', () async {
    final online = repository(MockClient((request) async => http.Response(row, 200)));
    expect((await online.loadResult()).channels, hasLength(1));
    online.dispose();

    final offline = repository(MockClient((request) async {
      throw const http.ClientException('offline');
    }));
    final result = await offline.loadResult();
    expect(result.channels, hasLength(1));
    expect(result.isCached, isTrue);
    expect(result.warning?.failure, VideoCatalogFailure.network);
    offline.dispose();
  });

  test('permission and configuration failures never appear as empty results', () async {
    final denied = repository(MockClient((request) async => http.Response('forbidden', 403)));
    await expectLater(denied.loadResult(), throwsA(
      isA<VideoCatalogException>().having(
        (e) => e.failure, 'failure', VideoCatalogFailure.authorization,
      ),
    ));
    denied.dispose();
    final unconfigured = repository(
      MockClient((request) async => http.Response(row, 200)), key: '',
    );
    await expectLater(unconfigured.loadResult(), throwsA(
      isA<VideoCatalogException>().having(
        (e) => e.failure, 'failure', VideoCatalogFailure.configuration,
      ),
    ));
    unconfigured.dispose();
  });

  test('invalid JSON is reported as malformed', () async {
    final invalid = repository(MockClient((request) async => http.Response('{', 200)));
    await expectLater(invalid.loadResult(), throwsA(
      isA<VideoCatalogException>().having(
        (e) => e.failure, 'failure', VideoCatalogFailure.malformed,
      ),
    ));
    invalid.dispose();
  });
}
