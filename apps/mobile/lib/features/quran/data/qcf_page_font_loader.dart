import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// QCF V2 has a separate font for every page. Load only pages the reader
/// actually opens; never include 604 fonts in the APK or request them at boot.
class QcfPageFontLoader {
  QcfPageFontLoader._();

  static final _loaded = <int>{};
  static final _inFlight = <int, Future<String?>>{};

  static Future<String?> load(int page) {
    if (page < 1 || page > 604) return Future.value(null);
    if (_loaded.contains(page)) return Future.value('FadhkurQcfV2Page$page');
    return _inFlight.putIfAbsent(page, () => _load(page).whenComplete(
      () => _inFlight.remove(page),
    ));
  }

  static Future<String?> _load(int page) async {
    final family = 'FadhkurQcfV2Page$page';
    final client = http.Client();
    try {
      final uri = Uri.parse(
        'https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/p$page.ttf',
      );
      final response = await client.get(uri).timeout(const Duration(seconds: 12));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 || bytes.length < 4096 ||
          response.headers['content-type']?.contains('text/html') == true) {
        return null;
      }
      await (FontLoader(family)..addFont(Future.value(
        ByteData.sublistView(Uint8List.fromList(bytes)),
      ))).load();
      _loaded.add(page);
      return family;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// QCF API glyphs can contain numeric HTML entities. Decode only these
  /// presentation codes, leaving the canonical verse text untouched.
  static String glyphs(String code) => code.replaceAllMapped(
    RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'),
    (match) {
      final raw = match.group(1)!;
      final value = raw.startsWith('x')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      return value != null && value > 0 && value <= 0x10ffff
          ? String.fromCharCode(value)
          : match.group(0)!;
    },
  );
}
