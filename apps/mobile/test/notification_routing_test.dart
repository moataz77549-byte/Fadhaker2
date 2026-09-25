import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/routing/app_router.dart';
import 'package:fadhkur_mobile/core/services/push_notification_service.dart';

/// كل route يمرّ من الـ sanitizer يجب أن يكون له case فعلي في AppRouter
/// (لا يسقط في الـ default الذي يوجّه لـ /home).
String resolvedRouteName(String route) {
  final generated = AppRouter.onGenerateRoute(RouteSettings(name: route));
  return generated.settings.name ?? '/home';
}

void main() {
  group('notification route sanitization', () {
    test('allows supported feature routes', () {
      expect(sanitizeNotificationRoute('/quran'), '/quran');
      expect(sanitizeNotificationRoute('/radio'), '/radio');
      expect(sanitizeNotificationRoute('/prayer-times'), '/prayer-times');
      expect(sanitizeNotificationRoute('/adhkar'), '/adhkar');
      expect(sanitizeNotificationRoute('/custom-reminders'), '/custom-reminders');
      expect(sanitizeNotificationRoute('/learning'), '/learning');
      expect(sanitizeNotificationRoute('/favorites'), '/favorites');
      expect(sanitizeNotificationRoute('/tasbih'), '/tasbih');
      expect(sanitizeNotificationRoute('/allah-names'), '/allah-names');
      expect(sanitizeNotificationRoute('/daily-hadith'), '/daily-hadith');
      expect(sanitizeNotificationRoute('/khatma'), '/khatma');
      expect(sanitizeNotificationRoute('/reciters'), '/reciters');
      expect(sanitizeNotificationRoute('/library'), '/library');
      expect(sanitizeNotificationRoute('/'), '/');
      expect(sanitizeNotificationRoute('/home'), '/home');
    });

    test('allows a valid surah deep link only', () {
      expect(sanitizeNotificationRoute('/quran/surah/18'), '/quran/surah/18');
      expect(sanitizeNotificationRoute('/quran/surah/1'), '/quran/surah/1');
      expect(sanitizeNotificationRoute('/quran/surah/114'), '/quran/surah/114');
      expect(sanitizeNotificationRoute('/quran/surah/0'), '/home');
      expect(sanitizeNotificationRoute('/quran/surah/115'), '/home');
    });

    test('maps legacy aliases to canonical routes', () {
      expect(sanitizeNotificationRoute('/azkar'), '/adhkar');
      expect(sanitizeNotificationRoute('/live'), '/radio');
      expect(sanitizeNotificationRoute('/prayer'), '/prayer-times');
      expect(sanitizeNotificationRoute('/recitations'), '/reciters');
    });

    test('maps legacy query form /quran?surah=N to /quran/surah/N', () {
      expect(sanitizeNotificationRoute('/quran?surah=18'), '/quran/surah/18');
      expect(sanitizeNotificationRoute('/quran?surah=1'), '/quran/surah/1');
      expect(sanitizeNotificationRoute('/quran?surah=114'), '/quran/surah/114');
      expect(
        sanitizeNotificationRoute('/quran?surah=18&utm_source=push'),
        '/quran/surah/18',
      );
      expect(sanitizeNotificationRoute('/quran?surah=0'), '/home');
      expect(sanitizeNotificationRoute('/quran?surah=115'), '/home');
      expect(sanitizeNotificationRoute('/quran?surah=abc'), '/quran');
      expect(sanitizeNotificationRoute('/quran?foo=bar'), '/quran');
    });

    test('tolerates trailing slashes and surrounding whitespace', () {
      expect(sanitizeNotificationRoute('/radio/'), '/radio');
      expect(sanitizeNotificationRoute('/quran/surah/18/'), '/quran/surah/18');
      expect(sanitizeNotificationRoute('/live/'), '/radio');
      expect(sanitizeNotificationRoute('  /adhkar  '), '/adhkar');
    });

    test('falls back safely for empty or unknown routes', () {
      expect(sanitizeNotificationRoute(null), '/home');
      expect(sanitizeNotificationRoute(''), '/home');
      expect(sanitizeNotificationRoute('/admin/delete-all'), '/home');
      expect(sanitizeNotificationRoute('/admin/delete-all?x=1'), '/home');
      expect(sanitizeNotificationRoute('/quran/surah/18/extra'), '/home');
      expect(sanitizeNotificationRoute('javascript:alert(1)'), '/home');
      expect(sanitizeNotificationRoute('/QURAN'), '/home');
    });

    test('every sanitizer-allowed route resolves in AppRouter (no silent fallback)', () {
      const allowedRoutes = [
        '/',
        '/home',
        '/radio',
        '/quran',
        '/reciters',
        '/library',
        '/prayer-times',
        '/adhkar',
        '/custom-reminders',
        '/learning',
        '/favorites',
        '/tasbih',
        '/allah-names',
        '/daily-hadith',
        '/khatma',
        '/quran/surah/1',
        '/quran/surah/18',
        '/quran/surah/114',
      ];
      for (final route in allowedRoutes) {
        expect(sanitizeNotificationRoute(route), route, reason: 'sanitizer: $route');
        expect(resolvedRouteName(route), route, reason: 'router: $route');
      }
    });

    test('sanitizer output for aliases and query forms resolves in AppRouter', () {
      const inputs = [
        '/azkar',
        '/live',
        '/prayer',
        '/recitations',
        '/quran?surah=18',
        '/quran?surah=1',
        '/quran?surah=114',
      ];
      for (final input in inputs) {
        final sanitized = sanitizeNotificationRoute(input);
        expect(sanitized, isNot('/home'), reason: 'sanitizer: $input');
        expect(
          resolvedRouteName(sanitized),
          sanitized,
          reason: 'router: $input -> $sanitized',
        );
      }
    });

    test('unknown routes do not crash and fall back to home', () {
      expect(resolvedRouteName('/nope'), '/home');
      expect(resolvedRouteName('/quran/surah/999'), '/home');
    });
  });
}
