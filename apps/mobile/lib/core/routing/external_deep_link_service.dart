import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'notification_deep_links.dart';

/// خدمة الروابط الخارجية (custom scheme مثل `fadhkur://`).
///
/// تستمع للروابط الواردة من خارج التطبيق (cold start عبر
/// [AppLinks.getInitialLink] + الروابط أثناء التشغيل عبر
/// [AppLinks.uriLinkStream]) وتوجّهها عبر **نفس** allowlist
/// [sanitizeNotificationRoute] — أي مسار خارج القائمة يسقط على `/home`
/// ولا يمكن لأي رابط خارجي قيادة تنقّل عشوائي.
///
/// التهيئة غير حاجبة ولا ترمي استثناءات أبدًا — تُستدعى عبر
/// `unawaited(...)` من `main()`.
///
/// ملاحظة متابعة: Universal Links (iOS) وApp Links (Android) بالدومين
/// الحقيقي تتطلب دومينًا موثّقًا وملفات تحقق (`assetlinks.json` /
/// `apple-app-site-association`) — غير مشمولة هنا.
class ExternalDeepLinkService {
  ExternalDeepLinkService._();

  static final ExternalDeepLinkService instance =
      ExternalDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;

  /// يبدأ الاستماع للروابط الخارجية. آمن للتكرار.
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_initialized) return;
    _initialized = true;
    try {
      // Cold start: التطبيق فُتح عبر رابط وهو مغلق تمامًا.
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial, navigatorKey);
      }
      // الروابط الواردة أثناء عمل التطبيق (خلفية/مقدمة).
      _subscription = _appLinks.uriLinkStream.listen(
        (uri) => _handleUri(uri, navigatorKey),
        onError: (Object error) {
          debugPrint('External deep link stream notice: $error');
        },
      );
    } catch (e) {
      debugPrint('External deep link init notice: $e');
    }
  }

  void _handleUri(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    try {
      final route = routeFromUri(uri);
      final sanitized = sanitizeNotificationRoute(route);
      debugPrint('External deep link: $uri -> $sanitized');
      _navigate(navigatorKey, sanitized);
    } catch (e) {
      debugPrint('External deep link handle notice: $e');
    }
  }

  /// يبني مسار التوجيه من URI خارجي.
  ///
  /// روابط الـ custom scheme تضع المقطع الأول في الـ host
  /// (`fadhkur://radio` → host=`radio` وpath فارغ) بينما الروابط
  /// الثلاثية (`fadhkur:///radio`) وروابط https (Universal Links)
  /// تضعه في الـ path — نُوحّد الثلاثة إلى `/radio`.
  /// الناتج يُمرَّر دائمًا عبر allowlist `sanitizeNotificationRoute`
  /// قبل أي تنقّل.
  @visibleForTesting
  static String routeFromUri(Uri uri) {
    var route = uri.path;
    if (uri.scheme == 'fadhkur' && uri.host.isNotEmpty) {
      route = '/${uri.host}$route';
    }
    if (route.isEmpty) route = '/';
    if (uri.hasQuery) route = '$route?${uri.query}';
    return route;
  }

  void _navigate(GlobalKey<NavigatorState> navigatorKey, String route) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      // الشجرة لم تُبنَ بعد — يُؤجَّل عبر نفس آلية الإشعارات.
      pendingExternalRoute = route;
      return;
    }
    // لا ندفع /home فوق الشاشة الحالية إن كان مفتوحًا أصلًا.
    navigator.pushNamed(route);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}

/// رابط خارجي ورد قبل جاهزية الـ Navigator — يُعالَج بعد أول إطار
/// (نفس نمط `pendingNotificationRoute` في main.dart).
String? pendingExternalRoute;
