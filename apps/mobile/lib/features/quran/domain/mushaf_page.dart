import 'dart:convert';

class MushafWord {
  const MushafWord({
    required this.verseKey,
    required this.position,
    required this.lineNumber,
    required this.textQpcHafs,
    this.location = '',
    this.codeV2 = '',
    this.charTypeName = '',
  });

  final String verseKey;
  final int position;
  final int lineNumber;
  final String textQpcHafs;
  final String location;
  final String codeV2;
  final String charTypeName;

  factory MushafWord.fromJson(Map<String, dynamic> json) {
    final location = (json['location'] ?? '').toString();
    final locationParts = location.split(':');
    return MushafWord(
      verseKey: (json['verse_key'] ?? json['verseKey'] ?? '').toString(),
      position: (json['position'] as num?)?.toInt() ??
          (locationParts.length > 2 ? int.tryParse(locationParts.last) : null) ??
          0,
      lineNumber: (json['line_number'] as num?)?.toInt() ??
          (json['lineNumber'] as num?)?.toInt() ??
          0,
      textQpcHafs:
          (json['text_qpc_hafs'] ?? json['textQpcHafs'] ?? json['text'] ?? '')
              .toString(),
      location: location,
      codeV2: (json['code_v2'] ?? json['codeV2'] ?? '').toString(),
      charTypeName:
          (json['char_type_name'] ?? json['charTypeName'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'verse_key': verseKey,
        'position': position,
        'line_number': lineNumber,
        'text_qpc_hafs': textQpcHafs,
        if (location.isNotEmpty) 'location': location,
        if (codeV2.isNotEmpty) 'code_v2': codeV2,
        if (charTypeName.isNotEmpty) 'char_type_name': charTypeName,
      };
}

class MushafAyah {
  const MushafAyah({
    required this.key,
    required this.chapterId,
    required this.number,
    required this.text,
    required this.tajweedText,
    this.pageNumber,
    this.juzNumber,
    this.hizbNumber,
    this.rubElHizbNumber,
    this.words = const [],
  });

  final String key;
  final int chapterId;
  final int number;
  final String text;
  final String tajweedText;
  final int? pageNumber;
  final int? juzNumber;
  final int? hizbNumber;
  final int? rubElHizbNumber;
  final List<MushafWord> words;

  factory MushafAyah.fromJson(Map<String, dynamic> json) {
    final key =
        json['verse_key'] as String? ?? json['verseKey'] as String? ?? '';
    final parts = key.split(':');
    final rawWords = json['words'];
    return MushafAyah(
      key: key,
      chapterId: int.tryParse(parts.first) ?? 1,
      number: int.tryParse(parts.length > 1 ? parts.last : '1') ?? 1,
      text: json['text_uthmani'] as String? ??
          json['textUthmani'] as String? ??
          '',
      tajweedText: json['text_uthmani_tajweed'] as String? ??
          json['tajweedText'] as String? ??
          json['text_uthmani'] as String? ??
          '',
      pageNumber: (json['page_number'] as num?)?.toInt() ??
          (json['pageNumber'] as num?)?.toInt(),
      juzNumber: (json['juz_number'] as num?)?.toInt() ??
          (json['juzNumber'] as num?)?.toInt(),
      hizbNumber: (json['hizb_number'] as num?)?.toInt() ??
          (json['hizbNumber'] as num?)?.toInt(),
      rubElHizbNumber: (json['rub_el_hizb_number'] as num?)?.toInt() ??
          (json['rubElHizbNumber'] as num?)?.toInt(),
      words: rawWords is List
          ? rawWords
              .whereType<Map>()
              .map((e) => MushafWord.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'verse_key': key,
        'text_uthmani': text,
        'text_uthmani_tajweed': tajweedText,
        if (pageNumber != null) 'page_number': pageNumber,
        if (juzNumber != null) 'juz_number': juzNumber,
        if (hizbNumber != null) 'hizb_number': hizbNumber,
        if (rubElHizbNumber != null) 'rub_el_hizb_number': rubElHizbNumber,
        if (words.isNotEmpty)
          'words': words.map((word) => word.toJson()).toList(growable: false),
      };
}

class MushafPage {
  const MushafPage({
    required this.number,
    required this.juz,
    required this.hizb,
    required this.surahName,
    required this.ayahs,
    this.rubElHizb,
    this.riwayaId = 'hafs',
  });

  final int number;
  final int juz;
  final int hizb;
  final int? rubElHizb;
  final String surahName;
  final List<MushafAyah> ayahs;
  final String riwayaId;

  String? get firstVerseKey =>
      ayahs.isEmpty || ayahs.first.key.isEmpty ? null : ayahs.first.key;

  factory MushafPage.fromApi(
    int page,
    Map<String, dynamic> json,
    String surahName, {
    String riwayaId = 'hafs',
  }) {
    final rawVerses = (json['verses'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final verses =
        rawVerses.map(MushafAyah.fromJson).toList(growable: false);
    final first =
        rawVerses.isEmpty ? const <String, dynamic>{} : rawVerses.first;
    return MushafPage(
      number: page,
      juz: (first['juz_number'] as num?)?.toInt() ??
          ((page - 1) ~/ 20) + 1,
      hizb: (first['hizb_number'] as num?)?.toInt() ??
          ((page - 1) ~/ 10) + 1,
      rubElHizb: (first['rub_el_hizb_number'] as num?)?.toInt(),
      surahName: surahName,
      ayahs: verses,
      riwayaId: riwayaId,
    );
  }

  String encode() => jsonEncode({
        'number': number,
        'juz': juz,
        'hizb': hizb,
        'rubElHizb': rubElHizb,
        'surahName': surahName,
        'riwayaId': riwayaId,
        'ayahs': ayahs.map((ayah) => ayah.toJson()).toList(),
      });

  factory MushafPage.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return MushafPage(
      number: (json['number'] as num).toInt(),
      juz: (json['juz'] as num).toInt(),
      hizb: (json['hizb'] as num).toInt(),
      rubElHizb: (json['rubElHizb'] as num?)?.toInt(),
      surahName: json['surahName'] as String,
      riwayaId: json['riwayaId'] as String? ?? 'hafs',
      ayahs: (json['ayahs'] as List<dynamic>)
          .whereType<Map>()
          .map((e) => MushafAyah.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}
