import 'package:flutter/material.dart';

class TajweedLegendItem {
  const TajweedLegendItem(this.labelAr, this.classes, this.lightColor);

  final String labelAr;
  final Set<String> classes;
  final Color lightColor;

  Color color(bool dark) =>
      dark ? Color.lerp(lightColor, Colors.white, 0.28)! : lightColor;
}

/// Parses Quran Foundation `text_uthmani_tajweed` markup without changing
/// the underlying Quran text. Styling is display-only.
///
/// Quran Foundation returns semantic tags such as:
/// `<tajweed class=ghunnah>...</tajweed>`.
class TajweedMarkup {
  TajweedMarkup._();

  static const legend = <TajweedLegendItem>[
    TajweedLegendItem(
      'همزة الوصل / الحرف غير المنطوق',
      {'ham_wasl', 'slnt', 'silent', 'laam_shamsiyah'},
      Color(0xFF7A7A7A),
    ),
    TajweedLegendItem(
      'مد طبيعي',
      {'madda_normal'},
      Color(0xFF537FFF),
    ),
    TajweedLegendItem(
      'مد جائز',
      {'madda_permissible'},
      Color(0xFF4050FF),
    ),
    TajweedLegendItem(
      'مد لازم / واجب',
      {'madda_necessary', 'madda_obligatory'},
      Color(0xFF1622A5),
    ),
    TajweedLegendItem(
      'قلقلة',
      {'qlq', 'qalqalah'},
      Color(0xFFDD2C2C),
    ),
    TajweedLegendItem(
      'إخفاء',
      {'ikhf', 'ikhafa', 'ikhf_shfw', 'ikhafa_shafawi'},
      Color(0xFF1E8E5A),
    ),
    TajweedLegendItem(
      'إدغام',
      {
        'idghm_shfw',
        'idgh_ghn',
        'idgh_w_ghn',
        'idgh_mus',
        'idgham_with_ghunnah',
        'idgham_without_ghunnah',
      },
      Color(0xFF8E44AD),
    ),
    TajweedLegendItem(
      'إقلاب',
      {'iqlb', 'iqlab'},
      Color(0xFFC06C20),
    ),
    TajweedLegendItem(
      'غنة',
      {'ghn', 'ghunnah'},
      Color(0xFFD03A7A),
    ),
  ];

  static TextSpan parse(
    String source, {
    required TextStyle baseStyle,
    required bool dark,
  }) {
    // End-of-ayah spans are presentation markup, not Quran text mutation.
    final input = source
        .replaceAll(RegExp(r'<span\s+class=end>'), '')
        .replaceAll('</span>', '');

    final rule = RegExp(
      r'<tajweed\s+class=(?:"([^"]+)"|\'([^\']+)\'|([^>\s]+))>(.*?)</tajweed>',
      dotAll: true,
      caseSensitive: false,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final match in rule.allMatches(input)) {
      if (match.start > cursor) {
        children.add(TextSpan(
          text: _stripUnknownTags(input.substring(cursor, match.start)),
          style: baseStyle,
        ));
      }
      final className =
          match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
      final text = _stripUnknownTags(match.group(4) ?? '');
      children.add(
        TextSpan(
          text: text,
          style: baseStyle.copyWith(color: colorForClass(className, dark)),
        ),
      );
      cursor = match.end;
    }
    if (cursor < input.length) {
      children.add(TextSpan(
        text: _stripUnknownTags(input.substring(cursor)),
        style: baseStyle,
      ));
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static Color? colorForClass(String className, bool dark) {
    for (final item in legend) {
      if (item.classes.contains(className)) return item.color(dark);
    }
    return null;
  }

  static String _stripUnknownTags(String value) =>
      value.replaceAll(RegExp(r'<[^>]+>'), '');
}

class TajweedLegendSheet extends StatelessWidget {
  const TajweedLegendSheet({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'مفتاح أحكام التجويد',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final item in TajweedMarkup.legend)
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, color: item.color(dark), size: 18),
              title: Text(item.labelAr),
            ),
          const SizedBox(height: 8),
          const Text(
            'الألوان تمثل الوسوم الدلالية التي يعيدها Quran Foundation، ولا تغيّر نص الآية المخزّن.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
