import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_environment.dart';
import 'push_notification_service.dart';
import 'local_reminder_service.dart';

/// AppServices Container & Composition Root
class AppServices {
  final bool isInitialized;
  final String activeEnvironment;
  final PushNotificationService pushService;

  AppServices({
    required this.isInitialized,
    required this.activeEnvironment,
    PushNotificationService? pushService,
  }) : pushService = pushService ?? PushNotificationService.instance;

  static Future<AppServices> init({
    required Function(String route) onNavigateToRoute,
  }) async {
    final pushService = PushNotificationService.instance;

    try {
      await pushService.initialize(onNavigateToRoute: onNavigateToRoute);
    } catch (_) {
      debugPrint("Firebase/FCM initialization unavailable");
    }

    try {
      await localReminderService.initialize();
    } catch (_) {
      debugPrint("Local reminder initialization unavailable");
    }

    return AppServices(
      isInitialized: true,
      // Build-time environment from --dart-define=APP_ENV (defaults to
      // production). Never hardcode 'development' here: release builds
      // must report the environment they were actually built for.
      activeEnvironment: AppEnvironmentConfig.current.name,
      pushService: pushService,
    );
  }
}

final appServicesProvider = Provider<AppServices>((ref) {
  throw UnimplementedError('AppServices must be initialized at bootstrap');
});
