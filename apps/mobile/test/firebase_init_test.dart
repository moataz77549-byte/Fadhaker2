import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/services/push_notification_service.dart';

/// Firebase bootstrap is tested with a mocked initializer so no platform
/// channel is ever touched: [ensureFirebaseInitialized] must call the real
/// Firebase SDK exactly once per isolate, and skip when already initialized.
void main() {
  group('ensureFirebaseInitialized (mocked Firebase)', () {
    test('calls the initializer exactly once when not initialized', () async {
      var calls = 0;
      await ensureFirebaseInitialized(
        isInitialized: () => false,
        initializer: () async {
          calls++;
        },
      );
      expect(calls, 1);
    });

    test('skips the initializer when Firebase is already initialized', () async {
      var calls = 0;
      await ensureFirebaseInitialized(
        isInitialized: () => true,
        initializer: () async {
          calls++;
        },
      );
      expect(calls, 0);
    });

    test('a second boot after the first is a no-op (idempotent)', () async {
      var calls = 0;
      var initialized = false;
      Future<void> boot() => ensureFirebaseInitialized(
            isInitialized: () => initialized,
            initializer: () async {
              calls++;
              initialized = true;
            },
          );
      await boot();
      await boot();
      await boot();
      expect(calls, 1);
    });

    test('initializer errors propagate to the caller', () async {
      expect(
        () => ensureFirebaseInitialized(
          isInitialized: () => false,
          initializer: () => throw StateError('mock init failure'),
        ),
        throwsStateError,
      );
    });
  });

  group('notification preference topics', () {
    test('canonical topic set matches the production taxonomy', () {
      expect(
        NotificationPreferences.topics.keys.toSet(),
        {
          'morning_athkar',
          'evening_athkar',
          'sleep_athkar',
          'friday_kahf',
          'live_radio',
          'general',
          'prayer_fajr',
          'prayer_dhuhr',
          'prayer_asr',
          'prayer_maghrib',
          'prayer_isha',
        },
      );
    });

    test('storage keys are namespaced per preference', () {
      expect(
        NotificationPreferences.storageKey('morning_athkar'),
        'fcm_pref_morning_athkar',
      );
      expect(
        NotificationPreferences.storageKey('prayer_fajr'),
        'fcm_pref_prayer_fajr',
      );
    });

    test('legacy topics are tracked for cleanup on revoke/restore', () {
      expect(
        NotificationPreferences.legacyTopics,
        containsAll({'daily_content', 'app_announcements'}),
      );
      // Legacy topics must never collide with canonical ones.
      expect(
        NotificationPreferences.legacyTopics
            .intersection(NotificationPreferences.topics.values.toSet()),
        isEmpty,
      );
    });

    test('every topic has an Arabic label for the settings toggles', () {
      expect(
        NotificationPreferences.labelsAr.keys.toSet(),
        NotificationPreferences.topics.keys.toSet(),
      );
    });

    test('every topic belongs to exactly one settings group', () {
      final grouped = NotificationPreferences.groupsAr.values
          .expand((keys) => keys)
          .toList();
      expect(grouped.toSet(), NotificationPreferences.topics.keys.toSet());
      expect(grouped.length, NotificationPreferences.topics.length,
          reason: 'a topic must not appear in two groups');
    });
  });
}
