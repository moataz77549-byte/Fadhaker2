import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fadhkur_mobile/features/recitations/data/reciter_catalog_service.dart';

void main() {
  ReciterCatalogService service(http.Client client, {String key = 'test-key'}) =>
      ReciterCatalogService(
        client: client,
        baseUrl: 'https://example.supabase.co',
        publishableKey: key,
      );

  test('reads reciters and tracks from app schema without bearer publishable key', () async {
    final catalog = service(MockClient((request) async {
      expect(request.headers['apikey'], 'test-key');
      expect(request.headers['Accept-Profile'], 'app');
      expect(request.headers.containsKey('Authorization'), isFalse);
      if (request.url.path.endsWith('/reciter_tracks')) {
        expect(request.url.queryParameters['reciter_id'], 'eq.reciter-1');
        return http.Response(
          '[{"surah_id":1,"audio_url":"https://example.com/001.mp3","quality":"high"}]',
          200,
        );
      }
      return http.Response(
        '[{"id":"reciter-1","name_ar":"قارئ موثق","default_riwayah":"حفص"}]',
        200,
      );
    }));
    final reciters = await catalog.load();
    expect(reciters, hasLength(1));
    expect(reciters.single.id, 'reciter-1');
    expect((await catalog.loadTracks(reciters.single.id)).single.surahNumber, 1);
    catalog.dispose();
  });

  test('empty success and authorization error remain distinct', () async {
    final empty = service(MockClient((request) async => http.Response('[]', 200)));
    expect(await empty.load(), isEmpty);
    empty.dispose();
    final denied = service(MockClient((request) async => http.Response('forbidden', 403)));
    await expectLater(denied.load(), throwsA(
      isA<ReciterCatalogException>().having(
        (e) => e.failure, 'failure', ReciterCatalogFailure.permission,
      ),
    ));
    denied.dispose();
  });

  test('configuration, network and malformed JSON surface typed failures', () async {
    final badConfig = service(
      MockClient((request) async => http.Response('[]', 200)), key: '',
    );
    await expectLater(badConfig.load(), throwsA(isA<ReciterCatalogException>()
        .having((e) => e.failure, 'failure', ReciterCatalogFailure.configuration)));
    badConfig.dispose();
    final offline = service(MockClient((request) async {
      throw http.ClientException('offline');
    }));
    await expectLater(offline.loadTracks('reciter-1'), throwsA(
      isA<ReciterCatalogException>().having(
        (e) => e.failure, 'failure', ReciterCatalogFailure.network,
      ),
    ));
    offline.dispose();
    final malformed = service(MockClient((request) async => http.Response('{', 200)));
    await expectLater(malformed.load(), throwsA(isA<ReciterCatalogException>()
        .having((e) => e.failure, 'failure', ReciterCatalogFailure.malformed)));
    malformed.dispose();
  });
}
