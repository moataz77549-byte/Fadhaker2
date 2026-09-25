import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/prayer/domain/prayer_times.dart';

void main() {
  group('PrayerTimes', () {
    test('computes ordered prayer times for Makkah', () {
      final times = PrayerTimes.forDate(
        date: DateTime(2026, 3, 21),
        coordinates: GeoCoordinates.makkah,
        utcOffset: const Duration(hours: 3),
      );

      final fajr = times[Prayer.fajr];
      final sunrise = times[Prayer.sunrise];
      final dhuhr = times[Prayer.dhuhr];
      final asr = times[Prayer.asr];
      final maghrib = times[Prayer.maghrib];
      final isha = times[Prayer.isha];

      expect(fajr.isBefore(sunrise), isTrue);
      expect(sunrise.isBefore(dhuhr), isTrue);
      expect(dhuhr.isBefore(asr), isTrue);
      expect(asr.isBefore(maghrib), isTrue);
      expect(maghrib.isBefore(isha), isTrue);
    });

    test('Makkah equinox timings land in the expected windows', () {
      final times = PrayerTimes.forDate(
        date: DateTime(2026, 3, 21),
        coordinates: GeoCoordinates.makkah,
        utcOffset: const Duration(hours: 3),
      );

      expect(times[Prayer.fajr].hour, inInclusiveRange(4, 5));
      expect(times[Prayer.dhuhr].hour, inInclusiveRange(12, 12));
      expect(times[Prayer.maghrib].hour, inInclusiveRange(18, 18));
    });

    test('Umm al-Qura puts Isha 90 minutes after Maghrib', () {
      final times = PrayerTimes.forDate(
        date: DateTime(2026, 6, 1),
        coordinates: GeoCoordinates.makkah,
        method: PrayerCalculationMethod.ummAlQura,
        utcOffset: const Duration(hours: 3),
      );

      expect(
        times[Prayer.isha].difference(times[Prayer.maghrib]).inMinutes,
        90,
      );
    });

    test('Hanafi Asr is later than the standard Asr', () {
      DateTime asrFor(bool hanafi) => PrayerTimes.forDate(
            date: DateTime(2026, 6, 1),
            coordinates: GeoCoordinates.makkah,
            hanafiAsr: hanafi,
            utcOffset: const Duration(hours: 3),
          )[Prayer.asr];

      expect(asrFor(true).isAfter(asrFor(false)), isTrue);
    });

    test('nextAfter skips sunrise and past prayers', () {
      final date = DateTime(2026, 3, 21);
      final times = PrayerTimes.forDate(
        date: date,
        coordinates: GeoCoordinates.makkah,
        utcOffset: const Duration(hours: 3),
      );

      final next = times.nextAfter(times[Prayer.fajr]);
      expect(next, isNotNull);
      expect(next!.key, Prayer.dhuhr);
      expect(times.nextAfter(times[Prayer.isha]), isNull);
    });

    test('method ids resolve with a safe fallback', () {
      expect(PrayerCalculationMethod.fromId('karachi').fajrAngle, 18);
      expect(
        PrayerCalculationMethod.fromId('unknown').id,
        PrayerCalculationMethod.ummAlQura.id,
      );
    });
  });
}
