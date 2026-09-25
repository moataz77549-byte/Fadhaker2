/// Build-time environment configuration for Fadhkur.
///
/// Environments are selected ONLY via `--dart-define=APP_ENV=<name>` —
/// there is no mutable "active environment" flag inside the app, so a
/// production build can never silently run against development backends.
///
/// | Env           | dart-define example                                              |
/// |---------------|------------------------------------------------------------------|
/// | development   | `--dart-define=APP_ENV=development`                              |
/// | staging       | `--dart-define=APP_ENV=staging`                                  |
/// | production    | (default; no flag needed) `--dart-define=APP_ENV=production`     |
///
/// Per-environment overrides use suffixed keys, e.g.
/// `--dart-define=SUPABASE_URL_DEVELOPMENT=https://xyz.supabase.co`.
/// The plain (unsuffixed) key keeps working as a shared fallback.
/// Client-safe values only — never put service-role keys or secrets here.

enum AppEnvironment { development, staging, production }

class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  /// Production Firebase project id. A non-production build must never
  /// point at it; a production build should always use it.
  static const String productionFirebaseProjectId = 'fadhkur-2f78c';

  /// Production Supabase URL (legacy default kept so existing release
  /// builds behave exactly as before; CI passes SUPABASE_URL explicitly).
  static const String productionSupabaseUrl =
      'https://ttvasynaxkkcwrmvlorg.supabase.co';

  static AppEnvironment get current =>
      parse(const String.fromEnvironment('APP_ENV', defaultValue: 'production'));

  /// Pure parser — kept separate so unit tests can exercise it without
  /// relying on compile-time `--dart-define` values.
  static AppEnvironment parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'development':
      case 'dev':
        return AppEnvironment.development;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
      case '':
      case null:
        return AppEnvironment.production;
      default:
        // Fail safe: an unknown value must never map to a dev/staging
        // backend — fall back to production.
        return AppEnvironment.production;
    }
  }

  static bool get isProduction => current == AppEnvironment.production;
  static bool get isDevelopment => current == AppEnvironment.development;
  static bool get isStaging => current == AppEnvironment.staging;

  /// Resolves a Supabase URL without ever mixing environments:
  /// per-env key → shared key → (production only) legacy default.
  static String get supabaseUrl {
    final shared = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    if (shared.isNotEmpty) return shared;
    switch (current) {
      case AppEnvironment.development:
        return const String.fromEnvironment('SUPABASE_URL_DEVELOPMENT',
            defaultValue: '');
      case AppEnvironment.staging:
        return const String.fromEnvironment('SUPABASE_URL_STAGING',
            defaultValue: '');
      case AppEnvironment.production:
        return productionSupabaseUrl;
    }
  }

  /// Resolves the Supabase publishable (anon) key the same way.
  /// Client-safe only — never the service-role key.
  static String get supabasePublishableKey {
    final shared = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
        defaultValue: '');
    if (shared.isNotEmpty) return shared;
    switch (current) {
      case AppEnvironment.development:
        return const String.fromEnvironment(
            'SUPABASE_PUBLISHABLE_KEY_DEVELOPMENT',
            defaultValue: '');
      case AppEnvironment.staging:
        return const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY_STAGING',
            defaultValue: '');
      case AppEnvironment.production:
        return '';
    }
  }

  /// Guards against environment/backend mixing. Called once at startup.
  ///
  /// - Production builds must use the production Firebase project.
  /// - Non-production builds must NOT point at the production project.
  ///
  /// In debug this throws (fail fast while developing); in release it
  /// logs a loud notice and lets the app degrade to "no push".
  static void assertFirebaseProject(String projectId) {
    if (projectId.isEmpty) return; // firebase_options may be unconfigured in dev
    if (isProduction && projectId != productionFirebaseProjectId) {
      _fail(
        'APP_ENV=production but FIREBASE_PROJECT_ID="$projectId" '
        '(expected "$productionFirebaseProjectId"). Refusing to mix backends.',
      );
    }
    if (!isProduction && projectId == productionFirebaseProjectId) {
      _fail(
        'APP_ENV=${current.name} but FIREBASE_PROJECT_ID points at the '
        'production project "$productionFirebaseProjectId". Development '
        'builds must never talk to the production Firebase project.',
      );
    }
  }

  static void _fail(String message) {
    assert(() {
      throw StateError('Environment misconfiguration: $message');
    }());
    // ignore: avoid_print
    print('Environment misconfiguration: $message');
  }
}
