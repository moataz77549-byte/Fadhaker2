import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import '../config/supabase_config.dart';
import '../routing/notification_deep_links.dart';
import 'app_version_service.dart';

// Re-exported so existing imports of sanitizeNotificationRoute /
// routeForPushData keep working; the canonical definitions live in
// core/routing/notification_deep_links.dart.
export '../routing/notification_deep_links.dart'
    show sanitizeNotificationRoute, routeForPushData;

/// Ensures Firebase is initialized exactly once per isolate, BEFORE any
/// Firebase/FCM usage (called from main() ahead of Supabase and AppServices).
///
/// [isInitialized] / [initializer] are test seams; production uses the
/// defaults ([Firebase.apps] guard + [Firebase.initializeApp] with the
/// env-driven [DefaultFirebaseOptions]).
Future<void> ensureFirebaseInitialized({
  bool Function()? isInitialized,
  Future<void> Function()? initializer,
}) async {
  final alreadyInitialized = isInitialized ?? () => Firebase.apps.isNotEmpty;
  if (alreadyInitialized()) return;
  final init = initializer ??
      () => Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
  await init();
}

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await ensureFirebaseInitialized();
  debugPrint('Handling background FCM message');
}

/// Canonical notification preference key → FCM topic.
///
/// Preference keys double as SharedPreferences suffixes (`fcm_pref_<key>`)
/// and as keys inside the `preferences` JSON sent to Supabase on register.
/// Defaults are always opt-in = false: no topic is ever subscribed
/// automatically; subscription happens only after explicit user consent.
///
/// All deep-link routing lives in `core/routing/notification_deep_links.dart`;
/// this class owns ONLY the topic taxonomy.
class NotificationPreferences {
  NotificationPreferences._();

  static const String consentKey = 'fcm_user_consent';
  static const String _keyPrefix = 'fcm_pref_';

  static const Map<String, String> topics = {
    'morning_athkar': 'morning_athkar',
    'evening_athkar': 'evening_athkar',
    'sleep_athkar': 'sleep_athkar',
    'friday_kahf': 'friday_kahf',
    'live_radio': 'live_radio',
    'general': 'general',
    'prayer_fajr': 'prayer_fajr',
    'prayer_dhuhr': 'prayer_dhuhr',
    'prayer_asr': 'prayer_asr',
    'prayer_maghrib': 'prayer_maghrib',
    'prayer_isha': 'prayer_isha',
  };

  /// Topics used by older builds; unsubscribed on revoke/restore for hygiene.
  static const Set<String> legacyTopics = {
    'daily_content',
    'app_announcements',
  };

  /// Arabic display labels for the settings screen toggles.
  static const Map<String, String> labelsAr = {
    'morning_athkar': 'أذكار الصباح',
    'evening_athkar': 'أذكار المساء',
    'sleep_athkar': 'أذكار النوم',
    'friday_kahf': 'تذكير سورة الكهف (الجمعة)',
    'live_radio': 'تنبيهات البث المباشر',
    'general': 'إشعارات عامة',
    'prayer_fajr': 'تنبيه صلاة الفجر (سحابي)',
    'prayer_dhuhr': 'تنبيه صلاة الظهر (سحابي)',
    'prayer_asr': 'تنبيه صلاة العصر (سحابي)',
    'prayer_maghrib': 'تنبيه صلاة المغرب (سحابي)',
    'prayer_isha': 'تنبيه صلاة العشاء (سحابي)',
  };

  /// Grouping for the settings screen: group title → preference keys.
  static const Map<String, List<String>> groupsAr = {
    'الأذكار اليومية': ['morning_athkar', 'evening_athkar', 'sleep_athkar'],
    'تنبيهات الصلاة السحابية': [
      'prayer_fajr',
      'prayer_dhuhr',
      'prayer_asr',
      'prayer_maghrib',
      'prayer_isha',
    ],
    'البث والإشعارات العامة': ['live_radio', 'friday_kahf', 'general'],
  };

  static String storageKey(String preferenceKey) => '$_keyPrefix$preferenceKey';
}

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._internal();
  PushNotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _currentInstallationId;

  /// Initialize Firebase & Local Notifications plugin.
  ///
  /// Covers every delivery path:
  /// - terminated (cold start): [FirebaseMessaging.getInitialMessage]
  /// - background: [FirebaseMessaging.onMessageOpenedApp]
  /// - foreground: [FirebaseMessaging.onMessage] → local notification → tap
  /// - notification tap always routes through [sanitizeNotificationRoute];
  ///   when the navigator isn't ready yet, [onNavigateToRoute] stashes the
  ///   route as `pendingNotificationRoute` (see main.dart).
  Future<void> initialize({
    required Function(String route) onNavigateToRoute,
  }) async {
    // 1. Initialize Firebase Core (idempotent; main() already did it).
    await ensureFirebaseInitialized();

    // 2. Set Background Handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 3. Setup Flutter Local Notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          final targetRoute = sanitizeNotificationRoute(response.payload);
          onNavigateToRoute(targetRoute);
        }
      },
    );

    // Create Android Notification Channel
    const androidChannel = AndroidNotificationChannel(
      'fadhkur_fcm_channel',
      'إشعارات فذكر',
      description: 'إشعارات البث المباشر والتذكيرات اليومية',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // 4. Foreground Message Handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotification(message);
    });

    // 5. App Opened from Background Notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      onNavigateToRoute(routeForPushData(message.data));
    });

    // 6. App Launched from Terminated Notification (cold start)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      onNavigateToRoute(routeForPushData(initialMessage.data));
    }

    // 7. Token Refresh Handler (Idempotence: Updates existing installation)
    _listenToTokenRefresh();
    await _retryPendingRevocation();
    await _restoreApprovedSubscription();
  }

  Future<void> _restoreApprovedSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(NotificationPreferences.consentKey) != true) return;

    var settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    }
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerOrUpdateSupabaseInstallation(token);
      await _applyStoredPreferences();
    }
  }

  /// Subscribes ONLY to topics the user explicitly enabled in
  /// SharedPreferences. Never subscribes to the full topic set.
  /// Also unsubscribes legacy topics from older builds for hygiene.
  Future<void> _applyStoredPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(NotificationPreferences.consentKey) != true) return;
      if (!await _isAuthorized()) return;
      for (final entry in NotificationPreferences.topics.entries) {
        final enabled =
            prefs.getBool(NotificationPreferences.storageKey(entry.key)) ?? false;
        if (enabled) {
          await FirebaseMessaging.instance.subscribeToTopic(entry.value);
        }
      }
      for (final legacy in NotificationPreferences.legacyTopics) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(legacy);
      }
    } catch (_) {
      debugPrint('FCM topic sync unavailable');
    }
  }

  Future<bool> _isAuthorized() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Reads every notification preference (defaults to false = opt-in).
  Future<Map<String, bool>> readNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in NotificationPreferences.topics.keys)
        key: prefs.getBool(NotificationPreferences.storageKey(key)) ?? false,
    };
  }

  /// Enables/disables one notification preference:
  /// persists it, subscribes/unsubscribes the linked FCM topic
  /// (only after user consent + OS permission), and syncs to Supabase.
  Future<void> setNotificationPreference(String key, bool enabled) async {
    final topic = NotificationPreferences.topics[key];
    if (topic == null) {
      debugPrint('Unknown notification preference ignored: $key');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NotificationPreferences.storageKey(key), enabled);
    if (prefs.getBool(NotificationPreferences.consentKey) != true) return;
    try {
      if (enabled) {
        if (await _isAuthorized()) {
          await FirebaseMessaging.instance.subscribeToTopic(topic);
        }
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      }
    } catch (_) {
      debugPrint('FCM topic toggle unavailable');
    }
    await _syncPreferencesToSupabase();
  }

  /// Re-registers the current installation so Supabase holds the latest
  /// preference map (upsert on installation_id — no duplicates).
  Future<void> _syncPreferencesToSupabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(NotificationPreferences.consentKey) != true) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _registerOrUpdateSupabaseInstallation(token);
    } catch (_) {
      debugPrint('Notification preference sync unavailable');
    }
  }

  /// In-App Consent Flow: Show custom dialog BEFORE requesting OS permissions
  Future<bool> requestConsentAndRegisterDevice(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final bool alreadyConsented =
        prefs.getBool(NotificationPreferences.consentKey) ?? false;

    bool userApproved = alreadyConsented;

    if (!alreadyConsented) {
      userApproved = await _showInAppConsentDialog(context);
      if (!userApproved) return false;
    }

    // Request OS permission only after the in-app consent step.
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) {
      await prefs.setBool(NotificationPreferences.consentKey, false);
      return false;
    }

    await prefs.setBool(NotificationPreferences.consentKey, true);
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) return false;

    await _registerOrUpdateSupabaseInstallation(fcmToken);
    await _applyStoredPreferences();
    return true;
  }

  Future<void> revokeConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NotificationPreferences.consentKey, false);

    final topics = <String>[
      ...NotificationPreferences.topics.values,
      ...NotificationPreferences.legacyTopics,
    ];
    for (final topic in topics) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      } catch (_) {}
    }

    final revoked = await _revokeSupabaseInstallation();
    if (!revoked) {
      await prefs.setBool('fcm_pending_server_revoke', true);
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  /// Show In-App Consent Dialog
  Future<bool> _showInAppConsentDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تفعيل إشعارات فذكر'),
        content: const Text(
          'هل ترغب في استقبال إشعارات البث المباشر، التلاوات اليومية والتنبيهات الخاصة للتطبيق؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ليس الآن'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('موافق وتفعيل'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show local notification when FCM push arrives in foreground
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'فذكر';
    final body = notification?.body ?? message.data['body'] ?? '';
    final route = routeForPushData(message.data);
    final deliveryId = message.data['delivery_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

    const androidDetails = AndroidNotificationDetails(
      'fadhkur_fcm_channel',
      'إشعارات فذكر',
      channelDescription: 'إشعارات البث المباشر والتذكيرات اليومية',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      deliveryId.hashCode,
      title,
      body,
      details,
      payload: route,
    );
  }

  /// Token Refresh Listener
  void _listenToTokenRefresh() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(NotificationPreferences.consentKey) != true) return;
      await _registerOrUpdateSupabaseInstallation(newToken);
      await _applyStoredPreferences();
    });
  }

  /// Register or update installation in Supabase (idempotent: the Edge
  /// Function upserts on installation_id, so a token refresh updates the
  /// existing row instead of creating a duplicate).
  Future<void> _registerOrUpdateSupabaseInstallation(String fcmToken) async {
    try {
      if (!SupabaseConfig.isConfigured) return;
      final prefs = await SharedPreferences.getInstance();
      _currentInstallationId ??= prefs.getString('supabase_installation_id');
      final installationSecret = prefs.getString('supabase_installation_secret') ?? _newSecret();
      await prefs.setString('supabase_installation_secret', installationSecret);

      if (_currentInstallationId == null) {
        _currentInstallationId = _newUuidV4();
        await prefs.setString('supabase_installation_id', _currentInstallationId!);
      }

      final hashedSecret = sha256.convert(utf8.encode(installationSecret)).toString();
      final stored = await readNotificationPreferences();
      final endpoint = Uri.parse('${SupabaseConfig.url}/functions/v1/quran-yutla-api/notifications/register');
      final response = await http.post(
        endpoint,
        headers: {
          'apikey': SupabaseConfig.publishableKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'installationId': _currentInstallationId,
          'hashedSecret': hashedSecret,
          'fcmToken': fcmToken,
          'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web'),
          // Read from the app itself via package_info_plus — never hardcoded.
          'appVersion': (await appVersionService.read()).display,
          'consentVersion': '1',
          'preferences': _preferencesPayload(stored),
        }),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Installation registration failed (${response.statusCode})');
      }

      await prefs.setBool('fcm_pending_server_revoke', false);
      debugPrint('Supabase notification installation synced successfully');
    } catch (_) {
      debugPrint('Notification registration unavailable');
    }
  }

  /// Builds the preferences JSON for Supabase: the granular per-topic map
  /// plus the legacy keys (derived) kept for backend/admin compatibility.
  Map<String, bool> _preferencesPayload(Map<String, bool> stored) {
    final prayerEnabled = stored['prayer_fajr']! ||
        stored['prayer_dhuhr']! ||
        stored['prayer_asr']! ||
        stored['prayer_maghrib']! ||
        stored['prayer_isha']!;
    return {
      ...stored,
      'prayer_alerts': prayerEnabled,
      'daily_verse': stored['morning_athkar']! ||
          stored['evening_athkar']! ||
          stored['sleep_athkar']!,
      'live_radio_alerts': stored['live_radio']!,
    };
  }

  Future<bool> _revokeSupabaseInstallation() async {
    try {
      if (!SupabaseConfig.isConfigured) return true;
      final prefs = await SharedPreferences.getInstance();
      final installationId = prefs.getString('supabase_installation_id');
      final secret = prefs.getString('supabase_installation_secret');
      if (installationId == null || secret == null) return true;

      final hashedSecret = sha256.convert(utf8.encode(secret)).toString();
      final response = await http
          .post(
            Uri.parse(
              '${SupabaseConfig.url}/functions/v1/quran-yutla-api/notifications/revoke',
            ),
            headers: {
              'apikey': SupabaseConfig.publishableKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'installationId': installationId,
              'hashedSecret': hashedSecret,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      await prefs.remove('supabase_installation_id');
      await prefs.remove('supabase_installation_secret');
      await prefs.setBool('fcm_pending_server_revoke', false);
      _currentInstallationId = null;
      return true;
    } catch (_) {
      debugPrint('Notification revoke unavailable');
      return false;
    }
  }

  Future<void> _retryPendingRevocation() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('fcm_pending_server_revoke') != true) return;
    final revoked = await _revokeSupabaseInstallation();
    if (revoked) {
      await prefs.setBool('fcm_pending_server_revoke', false);
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }

  String _newSecret() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
