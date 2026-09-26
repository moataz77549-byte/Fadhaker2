import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/notification_service.dart';
import '../../../core/services/prayer_times_service.dart';
import '../domain/prayer_times.dart';

/// Tier 2: offline prayer timetable with exact Adhan alarms.
///
/// يستخدم موقع الجهاز الفعلي دائمًا — لا توجد مدينة ثابتة كقيمة افتراضية.
/// عند تعذّر تحديد الموقع تُعرض حالة خطأ صادقة مع إجراءات، لا مواقيت مدينة أخرى.
class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  static const _methodKey = 'prayer.method';
  static const _hanafiKey = 'prayer.hanafi_asr';
  static const _alarmsKey = 'prayer.alarms_enabled';
  static const _fajrSoundKey = 'prayer.fajr_sound';
  static const _regularSoundKey = 'prayer.regular_sound';
  static const _offsetKey = 'prayer.alarm_offset_minutes';

  PrayerCalculationMethod _method = PrayerCalculationMethod.ummAlQura;
  bool _hanafiAsr = false;
  bool _alarmsEnabled = false;
  bool _busy = false;
  String _fajrSound = 'adhan_madinah';
  String _regularSound = 'adhan_makkah';
  int _offsetMinutes = 0;
  String? _status;
  Future<GeoCoordinates>? _coordinatesFuture;

  static const _adhanSounds = {
    'adhan_makkah': 'أذان مكة',
    'adhan_madinah': 'أذان المدينة',
  };

  @override
  void initState() {
    super.initState();
    _coordinatesFuture = _resolveDeviceCoordinates();
    unawaited(_restoreSettings());
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final methodId = prefs.getString(_methodKey);
    if (!mounted) return;
    setState(() {
      if (methodId != null) {
        _method = PrayerCalculationMethod.fromId(methodId);
      }
      _hanafiAsr = prefs.getBool(_hanafiKey) ?? false;
      _alarmsEnabled = prefs.getBool(_alarmsKey) ?? false;
      _fajrSound = prefs.getString(_fajrSoundKey) ?? 'adhan_madinah';
      _regularSound = prefs.getString(_regularSoundKey) ?? 'adhan_makkah';
      _offsetMinutes = (prefs.getInt(_offsetKey) ?? 0).clamp(-30, 30).toInt();
    });
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_methodKey, _method.id),
      prefs.setBool(_hanafiKey, _hanafiAsr),
      prefs.setBool(_alarmsKey, _alarmsEnabled),
      prefs.setString(_fajrSoundKey, _fajrSound),
      prefs.setString(_regularSoundKey, _regularSound),
      prefs.setInt(_offsetKey, _offsetMinutes),
    ]);
  }

  /// يحدد إحداثيات الجهاز مع تمييز دقيق لحالات الرفض والتعطيل.
  Future<GeoCoordinates> _resolveDeviceCoordinates() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PrayerTimesException('location_service_disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const PrayerTimesException('location_permission_denied_forever');
    }
    if (permission == LocationPermission.denied) {
      throw const PrayerTimesException('location_permission_required');
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 12));
      return GeoCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutException {
      throw const PrayerTimesException('location_unavailable');
    }
  }

  void _retryLocation() {
    setState(() {
      _status = null;
      _coordinatesFuture = _resolveDeviceCoordinates();
    });
  }

  Future<void> _applyAlarms(bool enabled) async {
    final previouslyEnabled = _alarmsEnabled;
    setState(() {
      _busy = true;
      _alarmsEnabled = enabled;
    });

    try {
      if (enabled) {
        final coordinates = await _coordinatesFuture;
        if (coordinates == null) {
          throw const PrayerTimesException('location_unavailable');
        }
        await localAlarmScheduler.schedulePrayerAlarms(
          coordinates: coordinates,
          method: _method,
          hanafiAsr: _hanafiAsr,
          fajrSound: _fajrSound,
          regularSound: _regularSound,
          offsetMinutes: _offsetMinutes,
        );
        _status = 'تم ضبط تنبيه الأذان للأيام القادمة.';
      } else {
        await localAlarmScheduler.cancelPrayerAlarms();
        _status = 'تم إيقاف تنبيه الأذان.';
      }
      await _persistSettings();
    } catch (error) {
      _alarmsEnabled = previouslyEnabled;
      _status = error is PrayerTimesException
          ? prayerErrorArabicMessage(error.message)
          : 'تعذّر ضبط تنبيه الأذان. تحقق من أذونات الإشعارات وحاول مجددًا.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rescheduleIfEnabled() async {
    if (_alarmsEnabled) await _applyAlarms(true);
  }

  Future<void> _previewSound() async {
    try {
      await localAlarmScheduler.previewAdhan(_regularSound);
      if (mounted) setState(() => _status = 'أُرسل تنبيه تجريبي بصوت المؤذن المختار.');
    } catch (_) {
      if (mounted) setState(() => _status = 'تعذّرت التجربة. فعّل إذن الإشعارات من إعدادات الجهاز.');
    }
  }

  String _format(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  List<DropdownMenuItem<String>> get _soundItems => _adhanSounds.entries
      .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مواقيت الصلاة')),
      body: FutureBuilder<GeoCoordinates>(
        future: _coordinatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            final code = snapshot.error is PrayerTimesException
                ? (snapshot.error as PrayerTimesException).message
                : 'location_unavailable';
            return _LocationErrorState(code: code, onRetry: _retryLocation);
          }
          return _TimetableView(
            coordinates: snapshot.data!,
            method: _method,
            hanafiAsr: _hanafiAsr,
            alarmsEnabled: _alarmsEnabled,
            busy: _busy,
            fajrSound: _fajrSound,
            regularSound: _regularSound,
            offsetMinutes: _offsetMinutes,
            status: _status,
            soundItems: _soundItems,
            format: _format,
            onMethodChanged: (value) {
              if (value == null) return;
              setState(() => _method = PrayerCalculationMethod.fromId(value));
              unawaited(_persistSettings());
              _rescheduleIfEnabled();
            },
            onFajrSoundChanged: (value) {
              if (value == null) return;
              setState(() => _fajrSound = value);
              unawaited(_persistSettings());
              _rescheduleIfEnabled();
            },
            onRegularSoundChanged: (value) {
              if (value == null) return;
              setState(() => _regularSound = value);
              unawaited(_persistSettings());
              _rescheduleIfEnabled();
            },
            onHanafiAsrChanged: (value) {
              setState(() => _hanafiAsr = value);
              unawaited(_persistSettings());
              _rescheduleIfEnabled();
            },
            onAlarmsChanged: _applyAlarms,
            onPreviewSound: _previewSound,
            onOffsetChanged: (value) {
              if (value == null) return;
              setState(() => _offsetMinutes = value);
              unawaited(_persistSettings());
              unawaited(_rescheduleIfEnabled());
            },
          );
        },
      ),
    );
  }
}

class _LocationErrorState extends StatelessWidget {
  final String code;
  final VoidCallback onRetry;
  const _LocationErrorState({required this.code, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 56, color: Color(0xFF5B677A)),
            const SizedBox(height: 16),
            Text(
              prayerErrorArabicMessage(code),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (code == 'location_permission_denied_forever')
                  FilledButton.icon(
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('فتح إعدادات التطبيق'),
                  ),
                if (code == 'location_service_disabled')
                  FilledButton.icon(
                    onPressed: Geolocator.openLocationSettings,
                    icon: const Icon(Icons.location_on),
                    label: const Text('فتح إعدادات الموقع'),
                  ),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimetableView extends StatelessWidget {
  final GeoCoordinates coordinates;
  final PrayerCalculationMethod method;
  final bool hanafiAsr;
  final bool alarmsEnabled;
  final bool busy;
  final String fajrSound;
  final String regularSound;
  final int offsetMinutes;
  final String? status;
  final List<DropdownMenuItem<String>> soundItems;
  final String Function(DateTime) format;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onFajrSoundChanged;
  final ValueChanged<String?> onRegularSoundChanged;
  final ValueChanged<bool> onHanafiAsrChanged;
  final ValueChanged<bool> onAlarmsChanged;
  final ValueChanged<int?> onOffsetChanged;
  final VoidCallback onPreviewSound;

  const _TimetableView({
    required this.coordinates,
    required this.method,
    required this.hanafiAsr,
    required this.alarmsEnabled,
    required this.busy,
    required this.fajrSound,
    required this.regularSound,
    required this.offsetMinutes,
    required this.status,
    required this.soundItems,
    required this.format,
    required this.onMethodChanged,
    required this.onFajrSoundChanged,
    required this.onRegularSoundChanged,
    required this.onHanafiAsrChanged,
    required this.onAlarmsChanged,
    required this.onOffsetChanged,
    required this.onPreviewSound,
  });

  @override
  Widget build(BuildContext context) {
    final times = PrayerTimes.forDate(
      date: DateTime.now(),
      coordinates: coordinates,
      method: method,
      hanafiAsr: hanafiAsr,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0x192E9E9E),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.my_location, size: 18, color: Color(0xFF2E9E9E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المواقيت محسوبة لموقع جهازك الحالي',
                    style: TextStyle(fontSize: 13, color: Color(0xFF2E9E9E)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: Prayer.values.map((prayer) {
              return ListTile(
                leading: Icon(
                  prayer == Prayer.sunrise ? Icons.wb_twilight : Icons.mosque_outlined,
                ),
                title: Text(prayer.titleAr),
                trailing: Text(
                  format(times.timeFor(prayer)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: method.id,
          decoration: const InputDecoration(labelText: 'طريقة الحساب'),
          items: PrayerCalculationMethod.all
              .map((m) => DropdownMenuItem(value: m.id, child: Text(m.titleAr)))
              .toList(growable: false),
          onChanged: busy ? null : onMethodChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: fajrSound,
          decoration: const InputDecoration(labelText: 'مؤذن صلاة الفجر'),
          items: soundItems,
          onChanged: busy ? null : onFajrSoundChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: regularSound,
          decoration: const InputDecoration(labelText: 'مؤذن بقية الصلوات'),
          items: soundItems,
          onChanged: busy ? null : onRegularSoundChanged,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: offsetMinutes,
          decoration: const InputDecoration(labelText: 'توقيت تنبيه الأذان بالنسبة للتقويم'),
          items: const [-30, -20, -15, -10, -5, 0, 5, 10, 15, 20, 30]
              .map((minutes) => DropdownMenuItem(
                    value: minutes,
                    child: Text(minutes == 0 ? 'عند وقت الصلاة' :
                        minutes < 0 ? 'قبل الوقت بـ ${-minutes} دقائق' : 'بعد الوقت بـ $minutes دقائق'),
                  )).toList(),
          onChanged: busy ? null : onOffsetChanged,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onPreviewSound,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('تجربة صوت المؤذن والإشعار'),
        ),
        SwitchListTile(
          title: const Text('حساب العصر على المذهب الحنفي'),
          value: hanafiAsr,
          onChanged: busy ? null : onHanafiAsrChanged,
        ),
        SwitchListTile(
          title: const Text('تنبيه الأذان في وقته بدقة'),
          subtitle: const Text('يعمل دون اتصال وحتى أثناء سكون الجهاز'),
          value: alarmsEnabled,
          onChanged: busy ? null : onAlarmsChanged,
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(status!, textAlign: TextAlign.center),
          ),
      ],
    );
  }
}
