import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/routing/notification_deep_links.dart';

/// FCM lifecycle routing: every delivery path funnels through
/// [routeForPushData] → [sanitizeNotificationRoute], so these tests pin the
/// routing decision for cold start, background, foreground and tap payloads
/// without touching platform channels.
void main() {
  group('cold start (getInitialMessage data)', () {
    test('routes to the requested feature screen', () {
      expect(routeForPushData({'targetRoute': '/radio'}), '/radio');
      expect(routeForPushData({'targetRoute': '/adhkar'}), '/adhkar');
      expect(routeForPushData({'targetRoute': '/prayer-times'}), '/prayer-times');
    });

    test('supports legacy query deep links', () {
      expect(routeForPushData({'targetRoute': '/quran?surah=18'}), '/quran/surah/18');
    });

    test('supports legacy route aliases', () {
      expect(routeForPushData({'targetRoute': '/live'}), '/radio');
      expect(routeForPushData({'targetRoute': '/azkar'}), '/adhkar');
      expect(routeForPushData({'targetRoute': '/prayer'}), '/prayer-times');
      expect(routeForPushData({'targetRoute': '/recitations'}), '/reciters');
    });

    test('missing or empty payload falls back to home', () {
      expect(routeForPushData({}), '/home');
      expect(routeForPushData({'targetRoute': ''}), '/home');
      expect(routeForPushData({'targetRoute': null}), '/home');
    });
  });

  group('background (onMessageOpenedApp data)', () {
    test('prefers targetRoute over the legacy route key', () {
      expect(
        routeForPushData({'targetRoute': '/radio', 'route': '/quran'}),
        '/radio',
      );
    });

    test('falls back to the legacy route key when targetRoute is absent', () {
      expect(routeForPushData({'route': '/live'}), '/radio');
    });

    test('surah deep links stay bounded to 1..114', () {
      expect(routeForPushData({'route': '/quran/surah/114'}), '/quran/surah/114');
      expect(routeForPushData({'route': '/quran/surah/115'}), '/home');
      expect(routeForPushData({'route': '/quran/surah/0'}), '/home');
    });
  });

  group('foreground (local notification payload)', () {
    test('payload produced for the foreground notification is sanitized', () {
      // _showForegroundNotification stores routeForPushData(message.data)
      // as the local-notification payload.
      expect(routeForPushData({'route': '/quran?surah=1'}), '/quran/surah/1');
      expect(routeForPushData({'targetRoute': '/admin'}), '/home');
    });
  });

  group('notification tap payloads', () {
    test('arbitrary or malicious payloads never drive navigation', () {
      const attacks = [
        '/admin/delete-all',
        '/admin/delete-all?x=1',
        'javascript:alert(1)',
        '/quran/surah/18/extra',
        '/QURAN',
        '..%2f..%2fetc%2fpasswd',
        'https://evil.example/phish',
      ];
      for (final payload in attacks) {
        expect(sanitizeNotificationRoute(payload), '/home',
            reason: 'payload: $payload');
        expect(routeForPushData({'targetRoute': payload}), '/home',
            reason: 'payload: $payload');
      }
    });

    test('only allow-listed query params are honored', () {
      // 'surah' is the only permitted query param (on /quran).
      expect(sanitizeNotificationRoute('/quran?surah=18'), '/quran/surah/18');
      expect(
        sanitizeNotificationRoute('/quran?surah=18&utm_source=push&x=1'),
        '/quran/surah/18',
      );
      // Unknown params are dropped, never executed.
      expect(sanitizeNotificationRoute('/quran?foo=bar'), '/quran');
      expect(sanitizeNotificationRoute('/quran?surah=abc'), '/quran');
      expect(sanitizeNotificationRoute('/radio?autoplay=1'), '/radio');
    });
  });
}
