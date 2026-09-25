import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class LocalReminderService {
  final FlutterLocalNotificationsPlugin plugin;
  LocalReminderService([FlutterLocalNotificationsPlugin? plugin])
      : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(settings);
  }

  Future<bool> requestAndroidNotificationPermission() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final enabled = await android.areNotificationsEnabled();
    if (enabled == true) return true;
    return await android.requestNotificationsPermission() ?? false;
  }

  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute}) async {
    // نبني الموعد من ساعة الجهاز المحلية عبر millisecondsSinceEpoch حتى لا تُفسَّر
    // الحقول في منطقة tz.local الخاطئة (UTC افتراضيًا قبل setLocalLocation).
    final now = DateTime.now();
    final wallClock = DateTime(now.year, now.month, now.day, hour, minute);
    var scheduled = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, wallClock.millisecondsSinceEpoch);
    final nowTz = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, now.millisecondsSinceEpoch);
    if (!scheduled.isAfter(nowTz)) scheduled = scheduled.add(const Duration(days: 1));
    await plugin.zonedSchedule(
      id, title, body, scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails('fadhkur_reminders', 'تذكيرات فذكر', channelDescription: 'الأذان والأذكار', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
      // أذكار الصباح/المساء لا تحتاج امتياز exact alarm؛ هذا يتجنب
      // طلب صلاحية خاصة من المستخدم ويحافظ على البطارية.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleMorningEvening({int morningHour = 7, int eveningHour = 18}) async {
    final allowed = await requestAndroidNotificationPermission();
    if (!allowed) return;
    await scheduleDaily(id: 1001, title: 'أذكار الصباح', body: 'حان وقت أذكار الصباح', hour: morningHour, minute: 0);
    await scheduleDaily(id: 1002, title: 'أذكار المساء', body: 'حان وقت أذكار المساء', hour: eveningHour, minute: 0);
  }

  Future<void> cancelMorningEvening() async {
    await plugin.cancel(1001);
    await plugin.cancel(1002);
  }

  Future<void> cancelAll() => plugin.cancelAll();
}

final localReminderService = LocalReminderService();
