import 'package:fadhkur_mobile/core/routing/external_deep_link_service.dart';
import 'package:fadhkur_mobile/core/routing/notification_deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// توحيد الروابط الخارجية قبل تمريرها عبر allowlist
/// `sanitizeNotificationRoute` (كل ما عداها يسقط على `/home`).
void main() {
  group('ExternalDeepLinkService.routeFromUri', () {
    test('fadhkur://radio (host فقط) -> /radio', () {
      expect(
        ExternalDeepLinkService.routeFromUri(Uri.parse('fadhkur://radio')),
        '/radio',
      );
    });

    test('fadhkur://quran/surah/18 -> /quran/surah/18', () {
      expect(
        ExternalDeepLinkService.routeFromUri(
            Uri.parse('fadhkur://quran/surah/18')),
        '/quran/surah/18',
      );
    });

    test('fadhkur:///radio (ثلاث شرطات) -> /radio', () {
      expect(
        ExternalDeepLinkService.routeFromUri(Uri.parse('fadhkur:///radio')),
        '/radio',
      );
    });

    test('fadhkur:// -> /', () {
      expect(
        ExternalDeepLinkService.routeFromUri(Uri.parse('fadhkur://')),
        '/',
      );
    });

    test('الاستعلام يُحفَظ', () {
      expect(
        ExternalDeepLinkService.routeFromUri(
            Uri.parse('fadhkur://quran?tab=reciters')),
        '/quran?tab=reciters',
      );
    });

    test('روابط https لا تُلحق الـ host بالمسار', () {
      expect(
        ExternalDeepLinkService.routeFromUri(
            Uri.parse('https://fadhkur.app/radio')),
        '/radio',
      );
    });
  });

  group('التكامل مع allowlist الإشعارات', () {
    test('مسار صالح يمرّ كما هو', () {
      final route =
          ExternalDeepLinkService.routeFromUri(Uri.parse('fadhkur://radio'));
      expect(sanitizeNotificationRoute(route), '/radio');
    });

    test('مسار خارج القائمة يسقط على /home', () {
      final route = ExternalDeepLinkService.routeFromUri(
          Uri.parse('fadhkur://evil'));
      expect(sanitizeNotificationRoute(route), '/home');
    });

    test('مسارات الميزات الجديدة في القائمة', () {
      for (final path in ['/tasbih', '/allah-names', '/daily-hadith', '/khatma']) {
        expect(sanitizeNotificationRoute(path), path);
      }
    });
  });
}
