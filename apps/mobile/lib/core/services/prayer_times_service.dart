import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_models.dart';

class PrayerTimesException implements Exception {
  final String message;
  const PrayerTimesException(this.message);

  @override
  String toString() => message;
}

/// يترجم رموز أخطاء المواقيت إلى رسائل عربية — لا يُعرض أي رمز خام للمستخدم.
String prayerErrorArabicMessage(String code) {
  switch (code) {
    case 'location_service_disabled':
      return 'خدمة الموقع معطّلة — فعّل GPS من إعدادات الجهاز ثم أعد المحاولة.';
    case 'location_permission_denied_forever':
      return 'تم رفض إذن الموقع نهائيًا — افتح إعدادات التطبيق لمنح الإذن.';
    case 'location_permission_required':
      return 'اسمح بالوصول إلى موقعك أو اختر مدينتك يدويًا.';
    case 'location_unavailable':
      return 'تعذّر تحديد الموقع حاليًا — حاول مجددًا أو اختر مدينتك يدويًا.';
    case 'city_required':
      return 'اكتب اسم المدينة أولًا ثم احفظ.';
    case 'prayer_data_unavailable':
      return 'تعذّرت قراءة مواقيت الصلاة من المصدر حاليًا.';
    default:
      if (code.startsWith('prayer_request_failed_')) {
        return 'تعذّر الاتصال بخدمة المواقيت حاليًا.';
      }
      return 'تعذّر تحميل مواقيت الصلاة حاليًا.';
  }
}

class PrayerTimesService {
  PrayerTimesService({http.Client? client, GeolocatorPlatform? geolocator})
      : _client = client ?? http.Client(),
        _geolocator = geolocator ?? GeolocatorPlatform.instance;

  static const _manualCityKey = 'prayer_manual_city';
  static const _manualCountryKey = 'prayer_manual_country';
  static const _methodKey = 'prayer_calculation_method';
  static const _offlineMethodKey = 'prayer.method';
  static const defaultCalculationMethod = 4;

  final http.Client _client;
  final GeolocatorPlatform _geolocator;
  static bool _tzInitialized = false;

  static void _ensureTimezones() {
    if (!_tzInitialized) {
      tzdata.initializeTimeZones();
      _tzInitialized = true;
    }
  }

  Future<PrayerTimesModel> loadToday() async {
    final preferences = await SharedPreferences.getInstance();
    final city = preferences.getString(_manualCityKey)?.trim();
    final country = preferences.getString(_manualCountryKey)?.trim();
    // The offline Adhan settings are the source of truth for smart radio too.
    // Honor legacy numeric preferences only when the new selection is absent.
    final method = switch (preferences.getString(_offlineMethodKey)) {
      'umm_al_qura' => 4,
      'mwl' => 3,
      'egyptian' => 5,
      'karachi' => 1,
      _ => preferences.getInt(_methodKey) ?? defaultCalculationMethod,
    };

    if (city != null && city.isNotEmpty) {
      return _loadByCity(city, country?.isNotEmpty == true ? country! : '', method);
    }

    final position = await _requestPosition();
    return _loadByCoordinates(position.latitude, position.longitude, method);
  }

  Future<void> saveManualLocation({required String city, required String country}) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) {
      throw const PrayerTimesException('city_required');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_manualCityKey, normalizedCity);
    await preferences.setString(_manualCountryKey, country.trim());
  }

  Future<void> clearManualLocation() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_manualCityKey);
    await preferences.remove(_manualCountryKey);
  }

  Future<void> setCalculationMethod(int method) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_methodKey, method);
  }

  /// يطلب موقع الجهاز مع تمييز دقيق لحالة الرفض/التعطيل.
  /// يرمي [PrayerTimesException] برمز محدد لكل حالة بدل null الغامض.
  Future<Position> _requestPosition() async {
    if (!await _geolocator.isLocationServiceEnabled()) {
      throw const PrayerTimesException('location_service_disabled');
    }
    var permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const PrayerTimesException('location_permission_denied_forever');
    }
    if (permission == LocationPermission.denied) {
      throw const PrayerTimesException('location_permission_required');
    }
    try {
      return await _geolocator
          .getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const PrayerTimesException('location_unavailable');
    }
  }

  Future<PrayerTimesModel> _loadByCoordinates(
    double latitude,
    double longitude,
    int method,
  ) async {
    final uri = Uri.https('api.aladhan.com', '/v1/timings', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'method': method.toString(),
    });
    return _fetch(uri, locationLabel: 'موقع الجهاز');
  }

  Future<PrayerTimesModel> _loadByCity(String city, String country, int method) async {
    final uri = Uri.https('api.aladhan.com', '/v1/timingsByCity', {
      'city': city,
      if (country.isNotEmpty) 'country': country,
      'method': method.toString(),
    });
    return _fetch(uri, locationLabel: country.isEmpty ? city : '$city، $country');
  }

  Future<PrayerTimesModel> _fetch(Uri uri, {required String locationLabel}) async {
    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw PrayerTimesException('prayer_request_failed_${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['code'] != 200) {
      throw const PrayerTimesException('prayer_data_unavailable');
    }
    final data = decoded['data'] as Map<String, dynamic>;
    final timings = Map<String, dynamic>.from(data['timings'] as Map);
    final meta = Map<String, dynamic>.from(data['meta'] as Map? ?? const {});
    final timezone = meta['timezone']?.toString() ?? DateTime.now().timeZoneName;
    final values = <String, String>{
      for (final entry in timings.entries)
        entry.key: entry.value.toString().split(' ').first,
    };
    final next = _nextPrayer(values, timezone);
    return PrayerTimesModel(
      city: locationLabel,
      timezone: timezone,
      fajr: values['Fajr'] ?? '',
      sunrise: values['Sunrise'] ?? '',
      dhuhr: values['Dhuhr'] ?? '',
      asr: values['Asr'] ?? '',
      maghrib: values['Maghrib'] ?? '',
      isha: values['Isha'] ?? '',
      nextPrayerName: next.$1,
      nextPrayerRemaining: next.$2,
    );
  }

  (String, String) _nextPrayer(Map<String, String> timings, String apiTimezone) {
    _ensureTimezones();
    final now = _nowIn(apiTimezone);
    const prayers = <(String, String)>[
      ('الفجر', 'Fajr'),
      ('الشروق', 'Sunrise'),
      ('الظهر', 'Dhuhr'),
      ('العصر', 'Asr'),
      ('المغرب', 'Maghrib'),
      ('العشاء', 'Isha'),
    ];
    for (final prayer in prayers) {
      final time = _todayAt(timings[prayer.$2], apiTimezone);
      if (time != null && time.isAfter(now)) {
        return (prayer.$1, _formatRemaining(time.difference(now)));
      }
    }
    final tomorrowFajr = _todayAt(timings['Fajr'], apiTimezone)?.add(const Duration(days: 1));
    return ('الفجر', tomorrowFajr == null ? '--:--:--' : _formatRemaining(tomorrowFajr.difference(now)));
  }

  /// "الآن" بتوقيت المنطقة الزمنية التي أعادها الـ API (مهم عندما يختار
  /// المستخدم مدينة يدوية في منطقة زمنية مختلفة عن جهازه).
  DateTime _nowIn(String apiTimezone) {
    try {
      return tz.TZDateTime.now(tz.getLocation(apiTimezone));
    } catch (_) {
      return DateTime.now();
    }
  }

  DateTime? _todayAt(String? value, String apiTimezone) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    try {
      final location = tz.getLocation(apiTimezone);
      final now = tz.TZDateTime.now(location);
      return tz.TZDateTime(location, now.year, now.month, now.day, hour, minute);
    } catch (_) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    }
  }

  String _formatRemaining(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 86399);
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$remainingSeconds';
  }
}

final prayerTimesService = PrayerTimesService();
