import 'package:fadhkur_mobile/core/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal offset moves only alarm instant across midnight', () {
    final calculated = DateTime(2026, 9, 26, 0, 10);
    expect(effectivePrayerAlarmTime(calculated, -20), DateTime(2026, 9, 25, 23, 50));
    expect(effectivePrayerAlarmTime(calculated, 10), DateTime(2026, 9, 26, 0, 20));
    expect(calculated, DateTime(2026, 9, 26, 0, 10));
  });

  test('offset outside supported range fails', () {
    expect(() => effectivePrayerAlarmTime(DateTime(2026), 31), throwsArgumentError);
  });

  test('each muezzin has a distinct Android 8 channel', () {
    expect(NotificationChannels.adhanForSound('adhan_makkah').id,
        isNot(NotificationChannels.adhanForSound('adhan_madinah').id));
  });

  test('a changed reminder sound uses a new Android 8 channel', () {
    expect(NotificationChannels.personalForSound('reminder_soft').id,
        isNot(NotificationChannels.personalForSound('adhan_short').id));
    expect(NotificationChannels.adhanForSound('adhan_madinah').id,
        startsWith('fadhkur_adhan_v2_'));
  });
}
