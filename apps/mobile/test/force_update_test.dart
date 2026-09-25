import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/services/force_update_service.dart';

void main() {
  group('compareVersions', () {
    test('compares numeric components correctly', () {
      expect(compareVersions('1.0.64', '1.0.64'), 0);
      expect(compareVersions('1.0.63', '1.0.64'), lessThan(0));
      expect(compareVersions('1.0.65', '1.0.64'), greaterThan(0));
      expect(compareVersions('1.0.7', '1.0.64'), lessThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.10.0', '1.9.99'), greaterThan(0));
    });

    test('treats missing components as zero', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0'), greaterThan(0));
    });

    test('handles whitespace and empty strings', () {
      expect(compareVersions(' 1.0.64 ', '1.0.64'), 0);
      expect(compareVersions('', ''), 0);
    });
  });

  group('requiresForceUpdate', () {
    test('no update when current meets the minimum', () {
      expect(
        requiresForceUpdate(
          currentVersion: '1.0.64',
          currentBuild: 64,
          minVersion: '1.0.64',
          minBuild: 64,
        ),
        isFalse,
      );
      expect(
        requiresForceUpdate(
          currentVersion: '1.0.70',
          currentBuild: 70,
          minVersion: '1.0.64',
          minBuild: 64,
        ),
        isFalse,
      );
    });

    test('update when version is below the minimum', () {
      expect(
        requiresForceUpdate(
          currentVersion: '1.0.63',
          currentBuild: 64,
          minVersion: '1.0.64',
          minBuild: 64,
        ),
        isTrue,
      );
      expect(
        requiresForceUpdate(
          currentVersion: '0.9.99',
          currentBuild: 99,
          minVersion: '1.0.64',
          minBuild: 64,
        ),
        isTrue,
      );
    });

    test('update when build number is below the minimum', () {
      expect(
        requiresForceUpdate(
          currentVersion: '1.0.64',
          currentBuild: 63,
          minVersion: '1.0.64',
          minBuild: 64,
        ),
        isTrue,
      );
    });

    test('ignores unset minimums (empty version / zero build)', () {
      expect(
        requiresForceUpdate(
          currentVersion: '1.0.1',
          currentBuild: 1,
          minVersion: '',
          minBuild: 0,
        ),
        isFalse,
      );
    });
  });
}
