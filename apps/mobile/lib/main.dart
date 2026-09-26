import 'dart:async';
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/brand_config.dart';
import 'core/config/supabase_config.dart';
import 'core/routing/app_router.dart';
import 'core/routing/external_deep_link_service.dart';
import 'core/services/app_services.dart';
import 'core/services/audio_playback_service.dart';
import 'core/services/app_version_service.dart';
import 'core/services/force_update_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/quran_download_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/local_reminder_service.dart';
import 'core/theme/fadhkur_theme.dart';
import 'features/reminders/data/personal_reminder_repository.dart';
import 'features/shell/presentation/root_shell.dart';
import 'firebase_options.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
String? pendingNotificationRoute;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard FIRST (before any Firebase use): the resolved Firebase project
  // must match the build environment — dev/staging builds must never talk
  // to the production project. Fails fast with a StateError in debug;
  // in release it logs a notice and the app degrades to "no push".
  DefaultFirebaseOptions.assertEnvironmentConsistent();

  // Start independent boot work in parallel. Firebase is the only hard
  // prerequisite for FCM / Crashlytics; Supabase, WorkManager and the Android
  // media session can initialize concurrently instead of extending cold start.
  final firebaseBootstrap = _bootstrapFirebase();
  final supabaseBootstrap = _bootstrapSupabase();
  final androidRuntimeBootstrap = _bootstrapAndroidRuntime();

  await firebaseBootstrap;

  // Once Firebase is ready, Crashlytics and the app service container can
  // initialize in parallel with the remaining platform/network bootstrap.
  final crashBootstrap = _initCrashReporting();
  final appServicesFuture = AppServices.init(
    onNavigateToRoute: (route) {
      debugPrint('Navigating to FCM target route: $route');
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        pendingNotificationRoute = route;
      } else {
        navigator.pushNamed(route);
      }
    },
  );

  final appServices = await appServicesFuture;
  await Future.wait<void>([
    supabaseBootstrap,
    androidRuntimeBootstrap,
    crashBootstrap,
  ]);

  // بوابة التحديث الإجباري: فحص غير حاجب عند بدء التشغيل —
  // يقرأ النسخة الدنيا المدعومة من app.app_config ويعرض حوارًا حاجبًا
  // فقط عندما يثبت الفحص الشبكي أن النسخة الحالية أدنى من الدنيا.
  // عند تعذّر الشبكة/الجدول تُستخدم آخر قيمة مخزّنة محليًا دون حجب المستخدم.
  unawaited(
    forceUpdateService.checkAtStartup(
      getContext: () => navigatorKey.currentContext,
    ),
  );

  // Re-arm exact alarms (prayer + personal reminders) after start or reboot.
  unawaited(
    PersonalReminderRepository().rescheduleAll().catchError((Object error) {
      debugPrint('Reminder reschedule notice: $error');
    }),
  );
  unawaited(localAlarmScheduler.restorePrayerAlarms().catchError((Object error) {
    debugPrint('Prayer alarm renewal notice: $error');
  }));
  unawaited(localReminderService.restoreMorningEvening().catchError((Object error) {
    debugPrint('Adhkar reminder renewal notice: $error');
  }));

  // الروابط الخارجية (custom scheme مثل fadhkur://): استماع غير حاجب —
  // كل رابط وارد يُوجَّه عبر نفس allowlist الروابط (أي مسار خارجها
  // يسقط على /home). لا يرمي استثناءات أبدًا.
  unawaited(
    ExternalDeepLinkService.instance.initialize(navigatorKey: navigatorKey),
  );

  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(appServices),
      ],
      child: const FadhkurApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final route = pendingNotificationRoute;
    pendingNotificationRoute = null;
    if (route != null) navigatorKey.currentState?.pushNamed(route);
    final externalRoute = pendingExternalRoute;
    pendingExternalRoute = null;
    if (externalRoute != null) {
      navigatorKey.currentState?.pushNamed(externalRoute);
    }
  });
}

Future<void> _bootstrapFirebase() async {
  try {
    await ensureFirebaseInitialized();
  } catch (e) {
    debugPrint('Firebase bootstrap notice: $e');
  }
}

Future<void> _bootstrapSupabase() async {
  SupabaseConfig.assertConfigured();
  if (!SupabaseConfig.isConfigured) return;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } catch (e) {
    debugPrint('Supabase bootstrap notice: $e');
  }
}

Future<void> _bootstrapAndroidRuntime() async {
  await Future.wait<void>([
    initializeAndroidDownloadRecovery().catchError((Object error) {
      debugPrint('Android download recovery init notice: $error');
    }),
    initializeAndroidAudioService().catchError((Object error) {
      debugPrint('Android audio service init notice: $error');
    }),
  ]);
}

/// Initializes Firebase Crashlytics with a privacy-safe configuration:
/// - no user identifiers, tokens, or location are ever attached;
/// - only the app version (from package metadata) is set as a custom key;
/// - collection is enabled in release builds only.
///
/// Never throws: crash reporting must never take the app down.
Future<void> _initCrashReporting() async {
  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    final version = await appVersionService.read();
    await FirebaseCrashlytics.instance
        .setCustomKey('app_version', version.display);
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crash reporting init notice: $e');
  }
}

class FadhkurApp extends StatelessWidget {
  const FadhkurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: BrandConfig.nameAr,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: FadhkurTheme.light(),
      darkTheme: FadhkurTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootShell(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
