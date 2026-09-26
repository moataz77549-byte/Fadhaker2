import 'package:fadhkur_mobile/features/listen/data/audio_url_builder.dart';
import 'package:fadhkur_mobile/features/listen/data/mp3quran_api.dart';
import 'package:fadhkur_mobile/features/recitations/data/reciter_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('only advertised surahs get zero-padded official URLs', () {
    final available = AudioUrlBuilder.availableSurahs('1,2,18,114,114,0,115');
    expect(available, {1, 2, 18, 114});
    expect(AudioUrlBuilder.forMp3Quran('https://server6.mp3quran.net/akdr/', 1,
        available).toString(), 'https://server6.mp3quran.net/akdr/001.mp3');
    expect(AudioUrlBuilder.forMp3Quran('https://server6.mp3quran.net/akdr/', 3,
        available), isNull);
    expect(AudioUrlBuilder.forMp3Quran('https://untrusted.example/audio/', 1,
        available), isNull);
  });

  test('official moshafs share an existing canonical reciter identity', () async {
    final api = Mp3QuranApi(client: MockClient((request) async {
      expect(request.url.path, '/api/v3/reciters');
      return http.Response('{"reciters":[{"id":7,"name":"أحمد العجمي",'
        '"moshaf":[{"id":80,"name":"حفص","server":"https://server6.mp3quran.net/ajm/",'
        '"surah_list":"1,2"},{"id":81,"name":"ورش",'
        '"server":"https://server7.mp3quran.net/ajm/","surah_list":"18"}]}]}', 200);
    }));
    final service = ReciterCatalogService(
      baseUrl: 'https://example.supabase.co', publishableKey: 'test-key',
      useOfficialCatalog: true, mp3QuranApi: api,
      client: MockClient((request) async => http.Response(
        '[{"id":"canonical-1","name_ar":"احمد العجمي",'
        '"default_riwayah":"حفص"}]', 200)),
    );
    final reciters = await service.load();
    expect(reciters, hasLength(1));
    expect(reciters.single.id, 'canonical-1');
    final tracks = await service.loadTracks('canonical-1');
    expect(tracks, hasLength(3));
    expect(tracks.map((track) => track.moshafId).toSet(), {'80', '81'});
    expect(tracks.last.audioUrl, endsWith('/018.mp3'));
    service.dispose();
  });
}
