import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer/domain/prayer_times.dart';
import '../../features/reminders/domain/personal_reminder.dart';

/// Android notification channels used by the offline scheduler.
class NotificationChannels {
  static const adhan = AndroidNotificationChannel(
    'fadhkur_adhan_channel',
    'مواقيت الصلاة والأذان',
    description: 'تنبيهات الأذان في وقتها حتى لو كان الجهاز في وضع السكون',
    importance: Importance.max,
    playSound: true,
  );

  static const personal = AndroidNotificationChannel(
    'fadhkur_personal_reminders',
    'التذكيرات الشخصية',
    description: 'الورد اليومي والتذكيرات التي ينشئها المستخدم',
    importance: Importance.high,
    playSound: true,
  );
}

/// Schedules exact, doze-proof local notifications: Adhan alarms (Tier 2) and
/// user-created personal reminders (Tier 3).
///
/// Every scheduling call is idempotent: it cancels the ids it owns before
/// re-creating them, so a reboot or a settings change never duplicates alarms.
class LocalAlarmScheduler {
  LocalAlarmScheduler([FlutterLocalNotificationsPlugin? plugin])
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  bool _initialized = false;

  /// Reserved id range for Adhan alarms (7 days x 6 prayers).
  static const int adhanIdBase = 500000;

  Future<void> initialize({
    void Function(String payload)? onSelectRoute,
  }) async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onSelectRoute?.call(payload);
        }
      },
    );

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(NotificationChannels.adhan);
      await android.createNotificationChannel(NotificationChannels.personal);
    }

    _initialized = true;
  }

  bool _canScheduleExact = false;

  Future<bool> _ensureAndroidPermissions({
    required bool requestIfMissing,
  }) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _canScheduleExact = false;
      return true;
    }

    var notificationsEnabled = await android.areNotificationsEnabled() ?? false;
    if (!notificationsEnabled && requestIfMissing) {
      notificationsEnabled =
          await android.requestNotificationsPermission() ?? false;
    }
    if (!notificationsEnabled) return false;

    _canScheduleExact =
        await android.canScheduleExactNotifications() ?? false;
    if (!_canScheduleExact && requestIfMissing) {
      _canScheduleExact =
          await android.requestExactAlarmsPermission() ?? false;
    }
    return true;
  }

  /// Schedules the Adhan for the coming [days] starting at [from].
  Future<void> schedulePrayerAlarms({
    required GeoCoordinates coordinates,
    PrayerCalculationMethod method = PrayerCalculationMethod.ummAlQura,
    bool hanafiAsr = false,
    Set<Prayer> enabledPrayers = const {
      Prayer.fajr,
      Prayer.dhuhr,
      Prayer.asr,
      Prayer.maghrib,
      Prayer.isha,
    },
    String fajrSound = 'adhan_madinah',
    String regularSound = 'adhan_makkah',
    DateTime? from,
    int days = 5,
    bool requestPermissions = true,
  }) async {
    await initialize();
    if (!await _ensureAndroidPermissions(
      requestIfMissing: requestPermissions,
    )) {
      throw StateError('notification_permission_required');
    }
    // An inexact fallback must never be reported as an exact Adhan alarm.
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null && !_canScheduleExact) {
      throw StateError('exact_alarm_permission_required');
    }
    await cancelPrayerAlarms(days: days);

    final start = from ?? DateTime.now();

    for (var dayOffset = 0; dayOffset < days; dayOffset++) {
      final date = DateTime(start.year, start.month, start.day)
          .add(Duration(days: dayOffset));
      final times = PrayerTimes.forDate(
        date: date,
        coordinates: coordinates,
        method: method,
        hanafiAsr: hanafiAsr,
      );

      for (final prayer in Prayer.values) {
        if (!prayer.isAdhan || !enabledPrayers.contains(prayer)) continue;
        final at = times.timeFor(prayer);
        if (!at.isAfter(start)) continue;

        final sound = prayer == Prayer.fajr ? fajrSound : regularSound;
        await _zonedSchedule(
          id: _prayerId(dayOffset, prayer),
          title: 'حان الآن وقت صلاة ${prayer.titleAr}',
          body: 'اللهم اجعلنا من المحافظين على الصلاة',
          when: at,
          payload: '/prayer-times',
          channel: NotificationChannels.adhan,
          soundResource: sound,
        );
      }
    }
  }

  Future<void> cancelPrayerAlarms({int days = 5}) async {
    for (var dayOffset = 0; dayOffset < days; dayOffset++) {
      for (final prayer in Prayer.values) {
        await plugin.cancel(_prayerId(dayOffset, prayer));
      }
    }
  }

  /// Re-creates the schedule for a single personal reminder.
  Future<void> schedulePersonalReminder(
    PersonalReminder reminder, {
    bool requestPermissions = true,
  }) async {
    await initialize();
    if (!await _ensureAndroidPermissions(
      requestIfMissing: requestPermissions,
    )) {
      return;
    }
    await cancelPersonalReminder(reminder);
    if (!reminder.enabled) return;

    final now = DateTime.now();
    if (reminder.isDaily) {
      await _zonedSchedule(
        id: reminder.notificationIds.first,
        title: reminder.title,
        body: 'تذكير شخصي من تطبيق فذكر',
        when: reminder.nextOccurrence(now),
        payload: '/custom-reminders',
        channel: NotificationChannels.personal,
        soundResource: reminder.sound.androidResource,
        matchComponents: DateTimeComponents.time,
      );
      return;
    }

    final sortedDays = reminder.weekdays.toList(growable: false)..sort();
    for (final weekday in sortedDays) {
      final when = _nextWeekday(now, weekday, reminder.hour, reminder.minute);
      await _zonedSchedule(
        id: reminder.id * 10 + weekday,
        title: reminder.title,
        body: 'تذكير شخصي من تطبيق فذكر',
        when: when,
        payload: '/custom-reminders',
        channel: NotificationChannels.personal,
        soundResource: reminder.sound.androidResource,
        matchComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  Future<void> cancelPersonalReminder(PersonalReminder reminder) async {
    for (var day = 0; day <= 7; day++) {
      await plugin.cancel(reminder.id * 10 + day);
    }
  }

  /// Called at app start and after `BOOT_COMPLETED` re-launch.
  Future<void> rescheduleAll(Iterable<PersonalReminder> reminders) async {
    await initialize();
    for (final reminder in reminders) {
      try {
        await schedulePersonalReminder(
          reminder,
          requestPermissions: false,
        );
      } catch (error) {
        debugPrint('Reminder ${reminder.id} reschedule notice: $error');
      }
    }
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required AndroidNotificationChannel channel,
    String? payload,
    String? soundResource,
    DateTimeComponents? matchComponents,
  }) async {
    // ملاحظة: tz.local قد يكون UTC إذا لم يُضبط setLocalLocation،
    // لذا نحوّل عبر millisecondsSinceEpoch للحفاظ على اللحظة المطلقة الصحيحة
    // بدل تفسير حقول الساعة المحلية في منطقة خاطئة.
    final scheduled = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, when.millisecondsSinceEpoch);

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: Priority.high,
      category: channel.id == NotificationChannels.adhan.id
          ? AndroidNotificationCategory.alarm
          : AndroidNotificationCategory.reminder,
      fullScreenIntent: false,
      playSound: true,
      sound: soundResource == null
          ? null
          : RawResourceAndroidNotificationSound(soundResource),
      audioAttributesUsage: channel.id == NotificationChannels.adhan.id
          ? AudioAttributesUsage.alarm
          : AudioAttributesUsage.notification,
    );

    await plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: _canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
      payload: payload,
    );
  }

  static int _prayerId(int dayOffset, Prayer prayer) =>
      adhanIdBase + dayOffset * 10 + prayer.index;

  static DateTime _nextWeekday(
    DateTime from,
    int weekday,
    int hour,
    int minute,
  ) {
    for (var offset = 0; offset <= 7; offset++) {
      final day = DateTime(from.year, from.month, from.day)
          .add(Duration(days: offset));
      final candidate = DateTime(day.year, day.month, day.day, hour, minute);
      if (candidate.isAfter(from) && candidate.weekday == weekday) {
        return candidate;
      }
    }
    return from.add(const Duration(days: 7));
  }
}

final localAlarmScheduler = LocalAlarmScheduler();
