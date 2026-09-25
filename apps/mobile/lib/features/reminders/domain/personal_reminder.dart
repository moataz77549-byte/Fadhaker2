/// Sound categories a user can attach to a personal reminder.
enum ReminderSound { soft, takbeer, adhanShort, recorded }

extension ReminderSoundLabel on ReminderSound {
  String get id => name;

  String get titleAr {
    switch (this) {
      case ReminderSound.soft:
        return 'نغمة هادئة';
      case ReminderSound.takbeer:
        return 'تكبير';
      case ReminderSound.adhanShort:
        return 'أذان مختصر';
      case ReminderSound.recorded:
        return 'مقطع مسجّل من الإذاعة';
    }
  }

  /// Android raw resource name (without extension) used by the channel sound.
  String? get androidResource {
    switch (this) {
      case ReminderSound.soft:
        return 'reminder_soft';
      case ReminderSound.takbeer:
        return 'reminder_takbeer';
      case ReminderSound.adhanShort:
        return 'adhan_short';
      case ReminderSound.recorded:
        return null;
    }
  }

  static ReminderSound fromId(String? id) {
    return ReminderSound.values.firstWhere(
      (sound) => sound.name == id,
      orElse: () => ReminderSound.soft,
    );
  }
}

/// A user-created reminder ("ورد يومي") persisted locally and rescheduled
/// after every reboot.
class PersonalReminder {
  const PersonalReminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.weekdays = const <int>{},
    this.sound = ReminderSound.soft,
    this.customSoundPath,
    this.enabled = true,
  })  : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  final int id;
  final String title;
  final int hour;
  final int minute;

  /// DateTime weekdays (1 = Monday ... 7 = Sunday). Empty means daily.
  final Set<int> weekdays;
  final ReminderSound sound;
  final String? customSoundPath;
  final bool enabled;

  bool get isDaily => weekdays.isEmpty || weekdays.length == 7;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get repeatLabel {
    if (isDaily) return 'يوميًا';
    const names = {
      1: 'الإثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد',
    };
    final sorted = weekdays.toList(growable: false)..sort();
    return sorted.map((day) => names[day] ?? '').join('، ');
  }

  /// Notification ids are derived so a weekly reminder can hold one id per day.
  List<int> get notificationIds {
    if (isDaily) return [id * 10];
    final sorted = weekdays.toList(growable: false)..sort();
    return sorted.map((day) => id * 10 + day).toList(growable: false);
  }

  /// The next occurrence at or after [from], honouring the weekday filter.
  DateTime nextOccurrence(DateTime from) {
    for (var offset = 0; offset <= 7; offset++) {
      final day = DateTime(from.year, from.month, from.day)
          .add(Duration(days: offset));
      final candidate = DateTime(day.year, day.month, day.day, hour, minute);
      if (!candidate.isAfter(from)) continue;
      if (isDaily || weekdays.contains(candidate.weekday)) return candidate;
    }
    return DateTime(from.year, from.month, from.day, hour, minute)
        .add(const Duration(days: 1));
  }

  PersonalReminder copyWith({
    int? id,
    String? title,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    ReminderSound? sound,
    String? customSoundPath,
    bool? enabled,
  }) {
    return PersonalReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      sound: sound ?? this.sound,
      customSoundPath: customSoundPath ?? this.customSoundPath,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'hour': hour,
        'minute': minute,
        'weekdays': (weekdays.toList(growable: false)..sort()).join(','),
        'sound': sound.name,
        'custom_sound_path': customSoundPath,
        'enabled': enabled ? 1 : 0,
      };

  factory PersonalReminder.fromMap(Map<String, Object?> map) {
    final rawDays = (map['weekdays'] as String? ?? '').trim();
    final days = rawDays.isEmpty
        ? <int>{}
        : rawDays
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .where((day) => day >= 1 && day <= 7)
            .toSet();

    return PersonalReminder(
      id: (map['id'] as num).toInt(),
      title: (map['title'] as String?)?.trim().isNotEmpty == true
          ? (map['title'] as String).trim()
          : 'تذكير',
      hour: (map['hour'] as num).toInt(),
      minute: (map['minute'] as num).toInt(),
      weekdays: days,
      sound: ReminderSoundLabel.fromId(map['sound'] as String?),
      customSoundPath: map['custom_sound_path'] as String?,
      enabled: (map['enabled'] as num?)?.toInt() != 0,
    );
  }
}
