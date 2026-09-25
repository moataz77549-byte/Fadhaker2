/// مصادر التفاسير.
///
/// التفسير يُجلب دائمًا من الـ Backend (عبر Quran Foundation API من خلال
/// الـ Edge Function) — ممنوع منعًا باتًا لصق أي نص تفسير داخل ملفات Dart.
///
/// معرّفات الموارد (resourceId) حقيقية وموثّقة من فهرس
/// `GET /resources/tafsirs` في Quran Foundation / Quran.com API v4:
/// - 16 → التفسير الميسر (ar-tafsir-muyassar)
/// - 14 → تفسير ابن كثير (ar-tafsir-ibn-kathir)
/// - 91 → تفسير السعدي (ar-tafseer-al-saddi)
/// - 90 → تفسير القرطبي (ar-tafseer-al-qurtubi)
/// القائمة قابلة للتغيير من الـ Backend (quran/tafsirs في الـ Edge Function).
class TafsirSource {
  const TafsirSource({
    required this.resourceId,
    required this.nameAr,
    required this.slug,
  });

  /// المعرّف الرقمي في Quran Foundation API.
  final int resourceId;
  final String nameAr;
  final String slug;

  factory TafsirSource.fromJson(Map<String, dynamic> json) {
    final id = (json['resourceId'] as num?)?.toInt();
    if (id == null) throw const FormatException('Tafsir resourceId is missing');
    return TafsirSource(
      resourceId: id,
      nameAr: json['nameAr'] as String? ?? '$id',
      slug: json['slug'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'resourceId': resourceId,
        'nameAr': nameAr,
        'slug': slug,
      };
}

class TafsirSourceRegistry {
  const TafsirSourceRegistry._();

  static const muyassar = TafsirSource(
    resourceId: 16,
    nameAr: 'التفسير الميسر',
    slug: 'ar-tafsir-muyassar',
  );
  static const ibnKathir = TafsirSource(
    resourceId: 14,
    nameAr: 'تفسير ابن كثير',
    slug: 'ar-tafsir-ibn-kathir',
  );
  static const saadi = TafsirSource(
    resourceId: 91,
    nameAr: 'تفسير السعدي',
    slug: 'ar-tafseer-al-saddi',
  );
  static const qurtubi = TafsirSource(
    resourceId: 90,
    nameAr: 'تفسير القرطبي',
    slug: 'ar-tafseer-al-qurtubi',
  );

  static const List<TafsirSource> builtin = [muyassar, ibnKathir, saadi, qurtubi];

  static List<TafsirSource> merge(List<TafsirSource> backend) {
    if (backend.isEmpty) return builtin;
    return List<TafsirSource>.unmodifiable(backend);
  }

  static List<TafsirSource> parseList(dynamic value) {
    if (value is! List) return const [];
    final out = <TafsirSource>[];
    for (final item in value.whereType<Map<String, dynamic>>()) {
      try {
        out.add(TafsirSource.fromJson(item));
      } on FormatException {
        continue;
      }
    }
    return out;
  }
}

/// تفسير آية واحدة كما يصل من الـ Backend (نص HTML يُحوَّل لنص صريح عند العرض).
class TafsirEntry {
  const TafsirEntry({
    required this.resourceId,
    required this.ayahKey,
    required this.sourceNameAr,
    required this.htmlText,
  });

  final int resourceId;
  final String ayahKey;
  final String sourceNameAr;

  /// نص التفسير بصيغة HTML من المصدر — لا يُخزَّن في الكود إطلاقًا.
  final String htmlText;

  /// يحوّل HTML إلى نص صريح للعرض دون اعتماديات إضافية.
  String get plainText {
    var text = htmlText
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  factory TafsirEntry.fromQuranFoundation({
    required int resourceId,
    required String ayahKey,
    required String sourceNameAr,
    required Map<String, dynamic> json,
  }) {
    final tafsir = json['tafsir'] as Map<String, dynamic>?;
    final text = tafsir?['text'] as String? ?? '';
    return TafsirEntry(
      resourceId: resourceId,
      ayahKey: ayahKey,
      sourceNameAr: sourceNameAr,
      htmlText: text,
    );
  }

  /// تسلسل للكاش المحلي (يُعاد بناؤه عبر [fromQuranFoundation]).
  Map<String, dynamic> toCacheJson() => {
        'tafsir': {'text': htmlText},
      };
}
