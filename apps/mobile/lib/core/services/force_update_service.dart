import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/app_config_repository.dart';

/// بوابة التحديث الإجباري (Force Update).
///
/// عند بدء التشغيل (بشكل غير حاجب — non-blocking) تُقرأ من جدول
/// `app.app_config` المفتاحان العامّان عبر [AppConfigRepository]
/// (كاش ذاكرة ← SharedPreferences ← PostgREST):
///   * `min_supported_version` — نص JSON مثل "1.0.64"
///   * `min_supported_build`   — رقم JSON مثل 64
/// وتُقارَن مع نسخة التطبيق من بيانات الحزمة (package_info_plus).
/// إذا كانت النسخة الحالية أدنى من الدنيا المدعومة يُعرض حوار Material 3
/// (RTL تلقائيًا) حاجب غير قابل للتجاوز يطلب التحديث.
///
/// عند تعذّر الوصول للشبكة/الجدول: تُقرأ آخر قيمة مخزّنة محليًا
/// لأغراض التشخيص فقط — ولا يُحجب المستخدم أبدًا إلا بناءً على
/// قراءة شبكية حديثة وناجحة.
///
/// لا تُعرض أي بيانات حساسة هنا: المفتاحان العامّان فقط.
class ForceUpdateService {
  ForceUpdateService({AppConfigRepository? configRepository})
      : _config = configRepository ?? AppConfigRepository();

  static const _versionKey = 'min_supported_version';
  static const _buildKey = 'min_supported_build';

  final AppConfigRepository _config;

  /// فحص بدء التشغيل. لا يحجب الإقلاع ولا يرمي استثناءات أبدًا —
  /// المتصل يستدعيه عبر `unawaited(...)`.
  ///
  /// الحجب يتم **فقط** عند نجاح القراءة الشبكية الحديثة؛ القيم
  /// المخزّنة محليًا للتشخيص فقط ولا تُستخدم في قرار الحجب.
  Future<void> checkAtStartup({
    BuildContext? Function()? getContext,
  }) async {
    try {
      final remote = await _config.refreshKeys({_versionKey, _buildKey});
      if (remote == null) {
        // تعذّر الوصول للشبكة/الجدول: لا حجب إطلاقًا دون قراءة حديثة.
        debugPrint(
          'Force-update offline notice: no fresh remote minimum — '
          'continuing without blocking.',
        );
        return;
      }
      final current = await PackageInfo.fromPlatform();
      final minVersion =
          remote[_versionKey] is String ? remote[_versionKey] as String : '';
      final minBuild = remote[_buildKey] is int ? remote[_buildKey] as int : 0;
      if (requiresForceUpdate(
        currentVersion: current.version,
        currentBuild: int.tryParse(current.buildNumber) ?? 0,
        minVersion: minVersion,
        minBuild: minBuild,
      )) {
        await _showBlockingDialog(getContext, current, minVersion);
      }
    } catch (e) {
      debugPrint('Force-update check notice: $e');
    }
  }

  /// ينتظر توفر سياق صالح (بعد بناء الشجرة) ثم يعرض الحوار الحاجب.
  Future<void> _showBlockingDialog(
    BuildContext? Function()? getContext,
    PackageInfo current,
    String minVersion,
  ) async {
    BuildContext? context;
    for (var i = 0; i < 40; i++) {
      context = getContext?.call();
      if (context != null && context.mounted) break;
      context = null;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (context == null || !context.mounted) {
      debugPrint('Force-update notice: no valid context for blocking dialog.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.system_update, size: 40),
          title: const Text('تحديث التطبيق مطلوب'),
          content: Text(
            'النسخة المثبتة لديك (${current.version}+${current.buildNumber}) '
            'أقدم من النسخة الدنيا المدعومة'
            '${minVersion.isNotEmpty ? ' ($minVersion)' : ''}. '
            'يرجى تحديث التطبيق من المتجر للمتابعة.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton.icon(
              onPressed: () => _openStore(current.packageName),
              icon: const Icon(Icons.download),
              label: const Text('تحديث الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStore(String packageName) async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageName',
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) debugPrint('Force-update notice: could not open store page.');
    } catch (e) {
      debugPrint('Force-update store launch notice: $e');
    }
  }
}

/// مقارنة رقمية لمكوّنات النسخة ("1.0.64" مقابل "1.0.7").
/// تعيد سالبًا إذا كانت [a] أقدم، صفرًا للتساوي، موجبًا إذا أحدث.
int compareVersions(String a, String b) {
  final aParts = a.trim().split('.');
  final bParts = b.trim().split('.');
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final aPart = i < aParts.length ? aParts[i].trim() : '0';
    final bPart = i < bParts.length ? bParts[i].trim() : '0';
    final aNum = int.tryParse(aPart);
    final bNum = int.tryParse(bPart);
    if (aNum != null && bNum != null) {
      if (aNum != bNum) return aNum.compareTo(bNum);
    } else if (aPart != bPart) {
      return aPart.compareTo(bPart);
    }
  }
  return 0;
}

/// هل تتطلب النسخة الحالية تحديثًا إجباريًا؟
/// التحديث مطلوب إذا كانت النسخة الحالية أدنى من الدنيا
/// أو رقم البناء الحالي أدنى من الأدنى.
bool requiresForceUpdate({
  required String currentVersion,
  required int currentBuild,
  required String minVersion,
  required int minBuild,
}) {
  final versionTooOld =
      minVersion.trim().isNotEmpty && compareVersions(currentVersion, minVersion) < 0;
  final buildTooOld = minBuild > 0 && currentBuild < minBuild;
  return versionTooOld || buildTooOld;
}

final forceUpdateService = ForceUpdateService();
