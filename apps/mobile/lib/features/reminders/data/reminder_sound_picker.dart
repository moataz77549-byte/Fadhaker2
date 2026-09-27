import 'package:flutter/services.dart';

/// Android stores one selected audio file privately and exposes a stable
/// content URI to the system notification service. No network is involved.
class ReminderSoundPicker {
  const ReminderSoundPicker();
  static const _channel = MethodChannel('app.fadhkur/reminder_sound');

  Future<SelectedReminderSound?> pick() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('pick');
    if (raw == null) return null;
    final uri = raw['uri']?.toString() ?? '';
    if (!uri.startsWith('content://app.fadhkur.reminder_sounds/')) {
      throw const FormatException('رابط الصوت غير صالح');
    }
    return SelectedReminderSound(uri: uri,
        name: raw['name']?.toString() ?? 'صوت من الهاتف');
  }
}

class SelectedReminderSound {
  const SelectedReminderSound({required this.uri, required this.name});
  final String uri;
  final String name;
}
