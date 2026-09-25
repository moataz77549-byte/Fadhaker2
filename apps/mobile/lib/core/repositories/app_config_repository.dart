import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

/// المستودع الموحّد لقراءة إعدادات التطبيق من جدول `app.app_config`.
///
/// يعمّم النمط الذي كان مبنيًا جزئيًا داخل [ForceUpdateService]:
/// كاش ذاكرة (الأسرع) ← SharedPreferences (آخر قيمة معروفة) ←
/// PostgREST (القيمة الحية). أي ميزة تحتاج مفتاح إعدادات عام
/// (مثل `min_supported_version`) تقرأ من هنا بدل تكرار منطق الجلب.
///
/// - القراءة لا ترمي استثناءات أبدًا: عند الفشل تُعاد آخر قيمة مخزّنة
///   أو null.
/// - الكتابة في الذاكرة والتخزين المحلي best-effort.
/// - لا تُخزَّن هنا أي أسرار: المفاتيح العامة فقط.
class AppConfigRepository {
  AppConfigRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _table = 'app_config';
  static const _prefsPrefix = 'fadhkur.app_config.';

  final http.Client _client;

  /// كاش الذاكرة: key → raw JSON value.
  final Map<String, Object?> _memoryCache = {};

  /// يقرأ مفتاحًا واحدًا. [refresh] يجبر الجلب من الشبكة أولًا.
  Future<Object?> get(String key, {bool refresh = false}) async {
    if (!refresh && _memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }
    if (refresh) {
      final remote = await _fetchKeys({key});
      if (remote != null && remote.containsKey(key)) {
        return remote[key];
      }
    }
    final cached = await _readStored(key);
    if (cached.found) {
      _memoryCache[key] = cached.value;
      return cached.value;
    }
    if (!refresh) {
      final remote = await _fetchKeys({key});
      if (remote != null && remote.containsKey(key)) {
        return remote[key];
      }
    }
    return null;
  }

  /// يجلب مجموعة مفاتيح دفعة واحدة ويحدّث كل الكاشات.
  /// يعيد null عند أي فشل (شبكة/جدول/Supabase غير مهيأ).
  Future<Map<String, Object?>?> refreshKeys(Set<String> keys) =>
      _fetchKeys(keys);

  Future<String?> getString(String key, {bool refresh = false}) async {
    final value = await get(key, refresh: refresh);
    return value is String ? value : null;
  }

  Future<int?> getInt(String key, {bool refresh = false}) async {
    final value = await get(key, refresh: refresh);
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Future<bool?> getBool(String key, {bool refresh = false}) async {
    final value = await get(key, refresh: refresh);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  /// يمسح كاش الذاكرة (مثلًا بعد تسجيل الخروج — لا يوجد حاليًا).
  void clearMemoryCache() => _memoryCache.clear();

  Future<Map<String, Object?>?> _fetchKeys(Set<String> keys) async {
    if (keys.isEmpty || !SupabaseConfig.isConfigured) return null;
    try {
      final inList = keys.map((k) => '"$k"').join(',');
      final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$_table').replace(
        queryParameters: {
          'select': 'key,value',
          'key': 'in.($inList)',
        },
      );
      final response = await _client.get(uri, headers: {
        'apikey': SupabaseConfig.publishableKey,
        // الجداول في سكيمة app (مكشوفة في PostgREST عبر config.toml).
        'Accept-Profile': 'app',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;

      final result = <String, Object?>{};
      for (final row in decoded.whereType<Map>()) {
        final key = row['key']?.toString();
        if (key == null || !keys.contains(key)) continue;
        result[key] = row['value'];
      }
      await _persist(result);
      _memoryCache.addAll(result);
      return result;
    } catch (e) {
      debugPrint('AppConfig fetch notice: $e');
      return null;
    }
  }

  Future<void> _persist(Map<String, Object?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in values.entries) {
        final prefKey = '$_prefsPrefix${entry.key}';
        final value = entry.value;
        if (value is String) {
          await prefs.setString(prefKey, value);
        } else if (value is int) {
          await prefs.setInt(prefKey, value);
        } else if (value is double) {
          await prefs.setDouble(prefKey, value);
        } else if (value is bool) {
          await prefs.setBool(prefKey, value);
        } else if (value != null) {
          await prefs.setString(prefKey, jsonEncode(value));
        }
      }
    } catch (e) {
      debugPrint('AppConfig cache notice: $e');
    }
  }

  Future<({bool found, Object? value})> _readStored(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefKey = '$_prefsPrefix$key';
      // ملاحظة: المفاتيح القديمة لبوابة التحديث الإجباري كانت تُخزَّن
      // تحت `fadhkur.min_supported_*` — تُقرأ كبديل للتوافق.
      final legacyKey = _legacyPrefKey(key);
      Object? value = prefs.get(prefKey);
      value ??= legacyKey == null ? null : prefs.get(legacyKey);
      if (value == null) return (found: false, value: null);
      return (found: true, value: value);
    } catch (e) {
      debugPrint('AppConfig stored read notice: $e');
      return (found: false, value: null);
    }
  }

  /// توافق رجعي مع مفاتيح التخزين القديمة قبل توحيد المستودع.
  static String? _legacyPrefKey(String key) => switch (key) {
        'min_supported_version' => 'fadhkur.min_supported_version',
        'min_supported_build' => 'fadhkur.min_supported_build',
        _ => null,
      };
}

final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository();
});
