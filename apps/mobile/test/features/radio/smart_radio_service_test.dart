import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fadhkur_mobile/features/radio/smart_radio_service.dart';

Map<String, dynamic> resolutionJson({
  String streamUrl = 'https://example.com/live.mp3',
  int refreshSeconds = 300,
}) => {
      'channel': {
        'slug': 'fadhkur-smart',
        'name': 'إذاعة فذكر الذكية',
        'description': 'اختبار',
      },
      'program': {
        'key': 'morning',
        'title': 'تلاوات الصباح',
        'sourceType': 'LIVE_STATION',
        'sourceId': 'source-1',
        'sourceName': 'قارئ',
        'streamUrl': streamUrl,
        'fallbackUrl': null,
        'bitrateKbps': 128,
        'refreshAfterSeconds': refreshSeconds,
        'transitionPolicy': 'SOFT_DEADLINE',
        'override': false,
        'fallbackMode': false,
      },
      'next': {
        'title': 'تلاوة قبل الظهر',
        'startsAt': '2026-09-25T11:45:00',
      },
      'timezone': 'Asia/Aden',
      'generatedAt': '2026-09-25T08:00:00Z',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses a valid HTTPS smart-radio resolution', () {
    final result = SmartRadioResolution.fromJson(resolutionJson());

    expect(result.channelSlug, 'fadhkur-smart');
    expect(result.program.streamUrl, 'https://example.com/live.mp3');
    expect(result.program.refreshAfterSeconds, 300);
    expect(result.program.bitrateKbps, 128);
    expect(result.next?.title, 'تلاوة قبل الظهر');
    expect(result.nowLabel, contains('تلاوات الصباح'));
  });

  test('rejects non-HTTPS playback source', () {
    expect(
      () => SmartRadioResolution.fromJson(
        resolutionJson(streamUrl: 'http://example.com/live.mp3'),
      ),
      throwsA(
        isA<SmartRadioException>()
            .having((e) => e.code, 'code', 'invalid_source'),
      ),
    );
  });

  test('refresh interval is clamped to safe limits', () {
    expect(
      SmartRadioResolution.fromJson(
        resolutionJson(refreshSeconds: 1),
      ).program.refreshAfterSeconds,
      60,
    );
    expect(
      SmartRadioResolution.fromJson(
        resolutionJson(refreshSeconds: 99999),
      ).program.refreshAfterSeconds,
      7200,
    );
  });

  test('loads a recent cached decision as fallback', () async {
    final raw = resolutionJson();
    SharedPreferences.setMockInitialValues({
      'fadhkur.smart_radio.resolution.v1': jsonEncode({
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'resolution': raw,
      }),
    });

    final cached = await SmartRadioService().loadCached();

    expect(cached, isNotNull);
    expect(cached!.cachedFallback, isTrue);
    expect(cached.program.sourceId, 'source-1');
  });

  test('rejects a stale cached decision older than 15 minutes', () async {
    SharedPreferences.setMockInitialValues({
      'fadhkur.smart_radio.resolution.v1': jsonEncode({
        'cached_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 16))
            .toIso8601String(),
        'resolution': resolutionJson(),
      }),
    });

    expect(await SmartRadioService().loadCached(), isNull);
  });

  test('malformed cached payload fails closed', () async {
    SharedPreferences.setMockInitialValues({
      'fadhkur.smart_radio.resolution.v1': '{',
    });

    expect(await SmartRadioService().loadCached(), isNull);
  });
}
