/// Canonical notification deep-link routing for Fadhkur.
///
/// This is the SINGLE source of truth for every route a push notification
/// may open. All FCM lifecycle paths (terminated cold start, background
/// `onMessageOpenedApp`, foreground local-notification tap) MUST funnel
/// through [sanitizeNotificationRoute] / [routeForPushData] so a malicious
/// or malformed payload can never drive arbitrary navigation.
///
/// Supported forms:
/// - canonical allow-listed routes (e.g. `/radio`, `/adhkar`)
/// - `/quran/surah/[1-114]`
/// - aliases: `/azkar`→`/adhkar`, `/live`→`/radio`,
///   `/prayer`→`/prayer-times`, `/recitations`→`/reciters`
/// - legacy query form: `/quran?surah=18` → `/quran/surah/18`
///
/// Anything else falls back to `/home`.
///
/// Every route produced here MUST have a matching case in
/// [AppRouter.onGenerateRoute] (covered by notification_routing_test.dart).

/// Strict route allow-list — no arbitrary navigation from payloads.
const Set<String> kAllowedNotificationRoutes = {
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
  // '/video' is intentionally NOT push-routable: video playback must only
  // ever start from an explicit in-app user action.
};

/// Legacy / shorthand route aliases → canonical AppRouter routes.
const Map<String, String> kNotificationRouteAliases = {
  '/azkar': '/adhkar',
  '/live': '/radio',
  '/prayer': '/prayer-times',
  '/recitations': '/reciters',
};

/// Allowed query parameters per canonical route. Any parameter not listed
/// here is dropped (analytics/tracking params must never affect routing).
const Map<String, Set<String>> kAllowedNotificationQueryParams = {
  '/quran': {'surah'},
};

final RegExp kSurahRouteRegex =
    RegExp(r'^\/quran\/surah\/([1-9]|[1-9][0-9]|10[0-9]|11[0-4])$');

/// Resolves the navigation target for an FCM data payload.
///
/// Shared by the cold-start (`getInitialMessage`), background
/// (`onMessageOpenedApp`) and foreground paths. Accepts either
/// `targetRoute` (preferred) or the legacy `route` key.
String routeForPushData(Map<String, dynamic> data) {
  final raw = data['targetRoute'] ?? data['route'];
  return sanitizeNotificationRoute(raw?.toString());
}

/// Normalizes and sanitizes a notification deep-link route.
String sanitizeNotificationRoute(String? route) {
  if (route == null || route.isEmpty) return '/home';
  var path = route.trim();
  String? query;
  final queryIndex = path.indexOf('?');
  if (queryIndex >= 0) {
    query = path.substring(queryIndex + 1);
    path = path.substring(0, queryIndex);
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  // Legacy query form: /quran?surah=18 → /quran/surah/18.
  // Only the allow-listed query params for this route are honored;
  // everything else is ignored.
  if (path == '/quran' && query != null && query.isNotEmpty) {
    final params = Uri.splitQueryString(query);
    final allowed = kAllowedNotificationQueryParams['/quran'] ?? const {};
    String? surahParam;
    for (final key in allowed) {
      if (params.containsKey(key)) {
        surahParam = params[key];
        break;
      }
    }
    final surahId = int.tryParse(surahParam ?? '');
    if (surahId != null) {
      final candidate = '/quran/surah/$surahId';
      return kSurahRouteRegex.hasMatch(candidate) ? candidate : '/home';
    }
    return '/quran';
  }

  final canonical = kNotificationRouteAliases[path] ?? path;
  if (kAllowedNotificationRoutes.contains(canonical)) return canonical;
  if (kSurahRouteRegex.hasMatch(canonical)) return canonical;
  return '/home';
}
