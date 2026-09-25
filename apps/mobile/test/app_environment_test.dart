import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/config/app_environment.dart';

/// Build-time environment selection must be deterministic and fail-safe:
/// an unknown or missing APP_ENV value must never resolve to a
/// development/staging backend by accident.
void main() {
  group('AppEnvironmentConfig.parse', () {
    test('parses all supported names', () {
      expect(AppEnvironmentConfig.parse('development'), AppEnvironment.development);
      expect(AppEnvironmentConfig.parse('dev'), AppEnvironment.development);
      expect(AppEnvironmentConfig.parse('staging'), AppEnvironment.staging);
      expect(AppEnvironmentConfig.parse('stage'), AppEnvironment.staging);
      expect(AppEnvironmentConfig.parse('production'), AppEnvironment.production);
      expect(AppEnvironmentConfig.parse('prod'), AppEnvironment.production);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AppEnvironmentConfig.parse('  Staging '), AppEnvironment.staging);
      expect(AppEnvironmentConfig.parse('DEV'), AppEnvironment.development);
    });

    test('missing or empty value defaults to production (safe default)', () {
      expect(AppEnvironmentConfig.parse(null), AppEnvironment.production);
      expect(AppEnvironmentConfig.parse(''), AppEnvironment.production);
    });

    test('unknown values fail safe to production, never to dev', () {
      expect(AppEnvironmentConfig.parse('prodction'), AppEnvironment.production);
      expect(AppEnvironmentConfig.parse('test'), AppEnvironment.production);
      expect(
        AppEnvironmentConfig.parse('development ' 'x'),
        isNot(AppEnvironment.development),
      );
    });
  });

  group('production constants', () {
    test('production Firebase project matches the registered project', () {
      expect(AppEnvironmentConfig.productionFirebaseProjectId, 'fadhkur-2f78c');
    });
  });
}
