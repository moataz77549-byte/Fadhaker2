import 'dart:math' as math;

/// The five daily prayers plus sunrise, used for offline Adhan alarms.
enum Prayer { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerLabel on Prayer {
  String get id => name;

  String get titleAr {
    switch (this) {
      case Prayer.fajr:
        return 'الفجر';
      case Prayer.sunrise:
        return 'الشروق';
      case Prayer.dhuhr:
        return 'الظهر';
      case Prayer.asr:
        return 'العصر';
      case Prayer.maghrib:
        return 'المغرب';
      case Prayer.isha:
        return 'العشاء';
    }
  }

  /// Sunrise is informational only; it never raises an Adhan alarm.
  bool get isAdhan => this != Prayer.sunrise;
}

/// Angle/interval parameters for the supported calculation methods.
class PrayerCalculationMethod {
  const PrayerCalculationMethod({
    required this.id,
    required this.titleAr,
    required this.fajrAngle,
    this.ishaAngle,
    this.ishaIntervalMinutes,
  }) : assert(
          ishaAngle != null || ishaIntervalMinutes != null,
          'Isha needs either an angle or a fixed interval after Maghrib',
        );

  final String id;
  final String titleAr;
  final double fajrAngle;
  final double? ishaAngle;
  final int? ishaIntervalMinutes;

  static const ummAlQura = PrayerCalculationMethod(
    id: 'umm_al_qura',
    titleAr: 'أم القرى (مكة المكرمة)',
    fajrAngle: 18.5,
    ishaIntervalMinutes: 90,
  );

  static const muslimWorldLeague = PrayerCalculationMethod(
    id: 'mwl',
    titleAr: 'رابطة العالم الإسلامي',
    fajrAngle: 18,
    ishaAngle: 17,
  );

  static const egyptian = PrayerCalculationMethod(
    id: 'egyptian',
    titleAr: 'الهيئة المصرية العامة للمساحة',
    fajrAngle: 19.5,
    ishaAngle: 17.5,
  );

  static const karachi = PrayerCalculationMethod(
    id: 'karachi',
    titleAr: 'جامعة العلوم الإسلامية بكراتشي',
    fajrAngle: 18,
    ishaAngle: 18,
  );

  static const all = <PrayerCalculationMethod>[
    ummAlQura,
    muslimWorldLeague,
    egyptian,
    karachi,
  ];

  static PrayerCalculationMethod fromId(String? id) {
    return all.firstWhere(
      (method) => method.id == id,
      orElse: () => ummAlQura,
    );
  }
}

/// Geographic coordinates used for the local (offline) calculation.
class GeoCoordinates {
  const GeoCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Fallback used before the user picks a city: Makkah al-Mukarramah.
  static const makkah = GeoCoordinates(latitude: 21.3891, longitude: 39.8579);

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory GeoCoordinates.fromMap(Map<String, dynamic> map) => GeoCoordinates(
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
      );
}

/// Pure-Dart prayer time calculation (no plugins, fully unit testable).
///
/// Implements the standard solar position algorithm used by PrayTimes:
/// sun declination + equation of time, then hour angles for each prayer.
class PrayerTimes {
  PrayerTimes._(this.date, this.coordinates, this.method, this._times);

  final DateTime date;
  final GeoCoordinates coordinates;
  final PrayerCalculationMethod method;
  final Map<Prayer, DateTime> _times;

  Map<Prayer, DateTime> get all => Map.unmodifiable(_times);

  DateTime operator [](Prayer prayer) => _times[prayer]!;

  DateTime timeFor(Prayer prayer) => _times[prayer]!;

  /// The next upcoming Adhan relative to [from]; null when the day is over.
  MapEntry<Prayer, DateTime>? nextAfter(DateTime from) {
    final upcoming = _times.entries
        .where((entry) => entry.key.isAdhan && entry.value.isAfter(from))
        .toList(growable: false)
      ..sort((a, b) => a.value.compareTo(b.value));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  static PrayerTimes forDate({
    required DateTime date,
    required GeoCoordinates coordinates,
    PrayerCalculationMethod method = PrayerCalculationMethod.ummAlQura,
    bool hanafiAsr = false,
    Duration? utcOffset,
  }) {
    final local = DateTime(date.year, date.month, date.day);
    final offset = utcOffset ?? date.timeZoneOffset;
    final tzHours = offset.inMinutes / 60.0;

    final julian =
        _julianDay(local.year, local.month, local.day) - coordinates.longitude / (15 * 24);
    final d = julian - 2451545.0;

    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g));
    final e = 23.439 - 0.00000036 * d;

    final rightAscension =
        _fixHour(_atan2(_cos(e) * _sin(l), _cos(l)) / 15.0);
    final equationOfTime = q / 15.0 - rightAscension;
    final declination = _asin(_sin(e) * _sin(l));

    final dhuhrHours =
        12.0 + tzHours - coordinates.longitude / 15.0 - equationOfTime;

    double? hourAngle(double angle) {
      final latitude = coordinates.latitude;
      final numerator = -_sin(angle) - _sin(declination) * _sin(latitude);
      final denominator = _cos(declination) * _cos(latitude);
      if (denominator == 0) return null;
      final ratio = numerator / denominator;
      if (ratio < -1 || ratio > 1) return null;
      return _acos(ratio) / 15.0;
    }

    double? asrHourAngle(int shadowFactor) {
      final latitude = coordinates.latitude;
      final angle = -_acot(
        shadowFactor + _tan((latitude - declination).abs()),
      );
      return hourAngle(angle);
    }

    DateTime at(double hours) {
      final totalMinutes = (hours * 60).round();
      return DateTime(local.year, local.month, local.day)
          .add(Duration(minutes: totalMinutes));
    }

    final sunriseAngle = hourAngle(0.833);
    final fajrAngle = hourAngle(method.fajrAngle);
    final asrAngle = asrHourAngle(hanafiAsr ? 2 : 1);

    final dhuhr = at(dhuhrHours);
    final sunrise = at(dhuhrHours - (sunriseAngle ?? 6));
    final maghrib = at(dhuhrHours + (sunriseAngle ?? 6));
    final fajr = at(dhuhrHours - (fajrAngle ?? (sunriseAngle ?? 6) + 1.2));
    final asr = at(dhuhrHours + (asrAngle ?? 3.5));

    final DateTime isha;
    if (method.ishaIntervalMinutes != null) {
      isha = maghrib.add(Duration(minutes: method.ishaIntervalMinutes!));
    } else {
      final ishaAngle = hourAngle(method.ishaAngle!);
      isha = at(dhuhrHours + (ishaAngle ?? (sunriseAngle ?? 6) + 1.2));
    }

    return PrayerTimes._(local, coordinates, method, {
      Prayer.fajr: fajr,
      Prayer.sunrise: sunrise,
      Prayer.dhuhr: dhuhr,
      Prayer.asr: asr,
      Prayer.maghrib: maghrib,
      Prayer.isha: isha,
    });
  }

  static double _julianDay(int year, int month, int day) {
    var y = year;
    var m = month;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        day +
        b -
        1524.5;
  }
}

const double _degToRad = math.pi / 180.0;

double _sin(double degrees) => math.sin(degrees * _degToRad);
double _cos(double degrees) => math.cos(degrees * _degToRad);
double _tan(double degrees) => math.tan(degrees * _degToRad);
double _asin(double value) => math.asin(value) / _degToRad;
double _acos(double value) => math.acos(value) / _degToRad;
double _atan2(double y, double x) => math.atan2(y, x) / _degToRad;
double _acot(double value) => math.atan2(1, value) / _degToRad;

double _fixAngle(double angle) {
  final value = angle - 360.0 * (angle / 360.0).floor();
  return value < 0 ? value + 360.0 : value;
}

double _fixHour(double hour) {
  final value = hour - 24.0 * (hour / 24.0).floor();
  return value < 0 ? value + 24.0 : value;
}
