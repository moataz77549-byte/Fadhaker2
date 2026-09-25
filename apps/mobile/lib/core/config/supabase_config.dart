import 'package:flutter/foundation.dart';

import 'app_environment.dart';

/// Client-safe Supabase configuration. Never place service-role credentials
/// here — only the public URL and the publishable (anon) key.
///
/// Both values resolve per build environment via [AppEnvironmentConfig]
/// (`--dart-define=APP_ENV=...` plus optional per-env `..._DEVELOPMENT` /
/// `..._STAGING` keys). Development builds never inherit production
/// defaults; a development build without explicit Supabase keys reports
/// [isConfigured] == false and Supabase-backed features degrade gracefully.
class SupabaseConfig {
  static String get url => AppEnvironmentConfig.supabaseUrl;

  static String get publishableKey =>
      AppEnvironmentConfig.supabasePublishableKey;

  static bool get isConfigured =>
      url.startsWith('https://') && publishableKey.isNotEmpty;

  static void assertConfigured() {
    if (!isConfigured) {
      debugPrint(
        'Supabase is not configured for ${AppEnvironmentConfig.current.name}. '
        'Pass SUPABASE_URL(_<ENV>) and SUPABASE_PUBLISHABLE_KEY(_<ENV>) at build time.',
      );
    }
  }
}
