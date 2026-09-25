import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/quran_font.dart';

/// تحميل خطوط القرآن عند أول استخدام مع تخزين مؤقت على القرص.
///
/// - لا تُضمَّن ملفات الخطوط في حزمة التطبيق.
/// - عند أول طلب لخطٍّ له [QuranFontOption.downloadUrl] موثّق، يُنزَّل الملف
///   ويُحفظ في مجلد دعم التطبيق (`quran_fonts/<id>.ttf`) ثم يُسجَّل عبر
///   FontLoader ليُستخدم في TextStyle.
/// - لا تُنزَّل الخطوط الأربعة عند بدء التطبيق — فقط الخط المختار فعليًا.
/// - عند أي فشل (لا رابط، خطأ شبكة، ملف تالف) يُعاد null فيسقط العرض
///   على خط النظام (fallback أنيق) مع بقاء الملاحظة الصادقة في الإعدادات.
///
/// الدالة آمنة للتكرار: العائلات المحمّلة تُتتبَّع، والطلبات المتزامنة
/// لنفس الخط تُدمج في مستقبل واحد.
class QuranFontLoader {
  const QuranFontLoader._();

  static final Set<String> _loadedFamilies = <String>{};
  static final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};

  /// أصغر حجم مقبول لملف خط (حماية من صفحات خطأ HTML مخزّنة كخط).
  static const _minFontBytes = 50 * 1024;

  /// يضمن جاهزية الخط ويعيد اسم العائلة المسجّلة، أو null عند التعذّر
  /// (يُستخدم خط النظام حينها).
  static Future<String?> ensureLoaded(QuranFontOption font) {
    if (_loadedFamilies.contains(font.fontFamily)) {
      return Future.value(font.fontFamily);
    }
    return _inFlight.putIfAbsent(font.fontFamily, () => _load(font).whenComplete(
          () => _inFlight.remove(font.fontFamily),
        ));
  }

  static Future<String?> _load(QuranFontOption font) async {
    final url = font.downloadUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final bytes = await _cachedOrDownload(font);
      if (bytes == null || bytes.lengthInBytes < _minFontBytes) return null;
      final loader = FontLoader(font.fontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFamilies.add(font.fontFamily);
      return font.fontFamily;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _cachedOrDownload(QuranFontOption font) async {
    final file = await _cacheFile(font.id);
    try {
      if (await file.exists()) {
        final cached = await file.readAsBytes();
        if (cached.lengthInBytes >= _minFontBytes) return cached;
      }
    } catch (_) {
      // تجاهل هادئ: نُعيد التنزيل.
    }
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(font.downloadUrl!));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 || bytes.lengthInBytes < _minFontBytes) {
        return null;
      }
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // فشل الكتابة على القرص لا يمنع استخدام الخط هذه الجلسة.
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<File> _cacheFile(String fontId) async {
    final dir = await getApplicationSupportDirectory();
    final safe = fontId.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return File('${dir.path}/quran_fonts/$safe.ttf');
  }
}
