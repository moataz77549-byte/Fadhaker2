import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/radio/radio_station.dart';

void main() {
  group('stationKindFrom', () {
    test('maps RECITER category to reciter kind', () {
      expect(stationKindFrom(categorySlug: 'RECITER'), StationKind.reciter);
    });

    test('maps TAFSEER category to tafsir kind', () {
      expect(stationKindFrom(categorySlug: 'TAFSEER'), StationKind.tafsir);
    });

    test('maps lesson categories to lesson kind', () {
      for (final slug in ['HADITH', 'SEERAH', 'SAHABAH', 'FATWA', 'ADHKAR']) {
        expect(stationKindFrom(categorySlug: slug), StationKind.lesson,
            reason: 'slug $slug');
      }
    });

    test('defaults to continuous for general categories and null', () {
      expect(stationKindFrom(categorySlug: 'QURAN_GENERAL'), StationKind.continuous);
      expect(stationKindFrom(categorySlug: 'QURAN_SURAH'), StationKind.continuous);
      expect(stationKindFrom(), StationKind.continuous);
    });

    test('metadata station_kind override wins over category', () {
      expect(
        stationKindFrom(
            categorySlug: 'RECITER', metadata: {'station_kind': 'tafsir'}),
        StationKind.tafsir,
      );
    });

    test('metadata private_project flag maps to privateProject', () {
      expect(
        stationKindFrom(metadata: {'private_project': true}),
        StationKind.privateProject,
      );
    });
  });

  group('RadioStation.fromSupabase', () {
    test('parses a full row', () {
      final station = RadioStation.fromSupabase({
        'id': 'abc-123',
        'name_ar': 'إذاعة القرآن الكريم',
        'name_en': 'Quran Radio',
        'stream_url': 'https://example.com/stream',
        'fallback_stream_url': 'https://example.com/fallback',
        'logo_url': 'https://example.com/logo.png',
        'stream_type': 'shoutcast',
        'is_featured': true,
        'sort_order': 5,
        'metadata': {'bitrate_kbps': 128},
        'categories': {'slug': 'RECITER'},
      });
      expect(station.id, 'abc-123');
      expect(station.nameAr, 'إذاعة القرآن الكريم');
      expect(station.streamUrl, 'https://example.com/stream');
      expect(station.fallbackUrl, 'https://example.com/fallback');
      expect(station.logoUrl, 'https://example.com/logo.png');
      expect(station.streamType, 'SHOUTCAST');
      expect(station.kind, StationKind.reciter);
      expect(station.isFeatured, isTrue);
      expect(station.sortOrder, 5);
      expect(station.bitrateKbps, 128);
    });

    test('tolerates embedded categories as a list (PostgREST shape)', () {
      final station = RadioStation.fromSupabase({
        'id': 'x',
        'name_ar': 'تفسير',
        'stream_url': 'https://example.com/t',
        'categories': [
          {'slug': 'TAFSEER'}
        ],
      });
      expect(station.kind, StationKind.tafsir);
    });

    test('falls back to defaults on sparse rows', () {
      final station = RadioStation.fromSupabase({'id': 'y'});
      expect(station.nameAr, isNotEmpty);
      expect(station.streamUrl, isEmpty);
      expect(station.kind, StationKind.continuous);
      expect(station.logoUrl, isNull);
    });
  });

  group('RadioStation json round-trip', () {
    test('toJson/fromJson preserves fields', () {
      const original = RadioStation(
        id: 'id-1',
        nameAr: 'محطة',
        streamUrl: 'https://example.com/s',
        streamType: 'AAC',
        kind: StationKind.lesson,
        isFeatured: true,
        sortOrder: 3,
        bitrateKbps: 64,
      );
      final restored = RadioStation.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.nameAr, original.nameAr);
      expect(restored.kind, StationKind.lesson);
      expect(restored.bitrateKbps, 64);
    });
  });

  test('stationKindLabel returns Arabic labels', () {
    expect(stationKindLabel(StationKind.continuous), 'بث متواصل');
    expect(stationKindLabel(StationKind.reciter), 'قارئ');
    expect(stationKindLabel(StationKind.tafsir), 'تفسير');
    expect(stationKindLabel(StationKind.lesson), 'دروس');
    expect(stationKindLabel(StationKind.privateProject), 'مشروع خاص');
  });
}
