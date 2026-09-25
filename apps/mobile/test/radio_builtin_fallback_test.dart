import 'dart:convert';

import 'package:fadhkur_mobile/core/services/radio_catalog_service.dart';
import 'package:fadhkur_mobile/features/radio/radio_station.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _stationJson({
  required String id,
  required String nameAr,
  required String streamUrl,
}) =>
    RadioStation(
      id: id,
      nameAr: nameAr,
      streamUrl: streamUrl,
      kind: StationKind.reciter,
    ).toJson();

/// يبني خدمة بكاش SharedPreferences مُهيأ مسبقًا وعميل شبكة يفشل دائمًا
/// (Supabase غير مُعد في بيئة الاختبار — وهذا هو المطلوب اختباره).
RadioCatalogService _offlineService({Map<String, Object> prefs = const {}}) {
  SharedPreferences.setMockInitialValues(prefs);
  final client = MockClient((_) async => throw http.ClientException('offline'));
  return RadioCatalogService(client: client);
}

void main() {
  group('RadioCatalogService offline-first', () {
    test('المحطات المضمّنة الأربع موجودة وروابطها حقيقية الشكل', () {
      expect(builtinRadioStations, hasLength(4));
      for (final s in builtinRadioStations) {
        expect(s.streamUrl, startsWith('https://backup.qurango.net/radio/'));
        expect(s.id, startsWith('builtin-'));
        expect(s.nameAr, isNotEmpty);
      }
      expect(
        builtinRadioStations.map((s) => s.streamUrl).toSet(),
        hasLength(4),
      );
    });

    test('دون شبكة ودون كاش: تُرجع المضمّنة فقط (لا قائمة فارغة)', () async {
      final service = _offlineService();
      final stations = await service.load();
      expect(stations.map((s) => s.id).toList(),
          builtinRadioStations.map((s) => s.id).toList());
      service.dispose();
    });

    test('الكاش يُدمج فوقه المضمّنة بلا تكرار', () async {
      final cachedRemote = _stationJson(
        id: 'remote-1',
        nameAr: 'محطة الإدارة',
        streamUrl: 'https://example.com/admin.mp3',
      );
      final duplicateOfBuiltin = _stationJson(
        id: 'remote-dup',
        nameAr: 'نسخة إدارة',
        streamUrl: 'https://backup.qurango.net/radio/maher',
      );
      final service = _offlineService(prefs: {
        'fadhkur.radio_catalog.v2': jsonEncode([cachedRemote, duplicateOfBuiltin]),
      });

      final stations = await service.load();

      // محطة الإدارة أولًا.
      expect(stations.first.id, 'remote-1');
      // بلا تكرار لرابط البث: رابط ماهر موجود مرة واحدة فقط.
      final urls = stations.map((s) => s.streamUrl).toList();
      expect(urls.toSet(), hasLength(urls.length));
      expect(
        urls.where((u) => u == 'https://backup.qurango.net/radio/maher'),
        hasLength(1),
      );
      // محطتا الكاش + 3 مضمّنة غير مكررة.
      expect(stations, hasLength(5));
      service.dispose();
    });

    test('الكاش الفاسد لا يقتل القائمة: المضمّنة تنقذ الموقف', () async {
      final service = _offlineService(prefs: {
        'fadhkur.radio_catalog.v2': 'ليس-json-صالحًا{{{',
      });
      final stations = await service.load();
      expect(stations, hasLength(4));
      service.dispose();
    });
  });
}
