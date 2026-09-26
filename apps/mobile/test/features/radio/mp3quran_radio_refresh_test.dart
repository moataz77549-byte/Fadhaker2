import 'package:fadhkur_mobile/core/services/radio_catalog_service.dart';
import 'package:fadhkur_mobile/features/listen/data/mp3quran_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('refreshes MP3Quran station by official external key', () async {
    final api = Mp3QuranApi(client: MockClient((request) async {
      expect(request.url.path, '/api/v3/radios');
      return http.Response('{"radios":[{"id":42,"name":"اختبار","url":"https://stream.example/new"}]}', 200);
    }));
    final catalog = RadioCatalogService(
      baseUrl: 'https://example.supabase.co', publishableKey: 'key',
      client: MockClient((_) async => http.Response(
        '[{"id":"station-1","name_ar":"محطة","stream_url":"https://stream.example/old",'
        '"external_key":"42","source_url":"https://www.mp3quran.net/api/v3/radios?language=ar"}]', 200)),
      mp3QuranApi: api,
    );
    expect((await catalog.refreshStation('station-1'))?.streamUrl,
        'https://stream.example/new');
    catalog.dispose();
  });
}
