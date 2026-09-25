import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fadhkur_mobile/core/services/radio_catalog_service.dart';
import 'package:fadhkur_mobile/features/radio/radio_station.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('requests only playable stations and relies on source-scoped RLS', () async {
    final catalog = RadioCatalogService(
      baseUrl: 'https://example.supabase.co',
      publishableKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.queryParameters['is_playable'], 'eq.true');
        expect(request.url.queryParameters.containsKey('production_enabled'), isFalse);
        expect(request.headers['apikey'], 'test-key');
        expect(request.headers['Accept-Profile'], 'app');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('[]', 200);
      }),
    );
    final stations = await catalog.load();
    expect(stations, isNotEmpty);
    expect(stations.length, lessThanOrEqualTo(builtinRadioStations.length));
    catalog.dispose();
  });

  test('offline and unauthorized requests retain verified built-in fallback', () async {
    for (final response in [403, 503]) {
      final catalog = RadioCatalogService(
        baseUrl: 'https://example.supabase.co',
        publishableKey: 'test-key',
        client: MockClient((request) async => http.Response('error', response)),
      );
      expect(await catalog.load(), isNotEmpty);
      catalog.dispose();
    }
  });
}
