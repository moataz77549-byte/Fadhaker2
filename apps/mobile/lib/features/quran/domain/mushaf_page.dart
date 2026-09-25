import 'dart:convert';

class MushafAyah {
  const MushafAyah({required this.key, required this.chapterId, required this.number, required this.text, required this.tajweedText});
  final String key;
  final int chapterId;
  final int number;
  final String text;
  final String tajweedText;

  factory MushafAyah.fromJson(Map<String, dynamic> json) {
    final key = json['verse_key'] as String? ?? json['verseKey'] as String? ?? '';
    final parts = key.split(':');
    return MushafAyah(
      key: key,
      chapterId: int.tryParse(parts.first) ?? 1,
      number: int.tryParse(parts.length > 1 ? parts.last : '1') ?? 1,
      text: json['text_uthmani'] as String? ?? json['textUthmani'] as String? ?? '',
      tajweedText: json['text_uthmani_tajweed'] as String? ?? json['text_uthmani'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'verse_key': key, 'text_uthmani': text, 'text_uthmani_tajweed': tajweedText};
}

class MushafPage {
  const MushafPage({required this.number, required this.juz, required this.hizb, required this.surahName, required this.ayahs, this.riwayaId = 'hafs'});
  final int number;
  final int juz;
  final int hizb;
  final String surahName;
  final List<MushafAyah> ayahs;

  /// معرّف الرواية التي بُنيت عليها هذه الصفحة (افتراضيًا حفص).
  final String riwayaId;

  factory MushafPage.fromApi(int page, Map<String, dynamic> json, String surahName, {String riwayaId = 'hafs'}) {
    final rawVerses = (json['verses'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList(growable: false);
    final verses = rawVerses.map(MushafAyah.fromJson).toList(growable: false);
    final first = rawVerses.isEmpty ? const <String, dynamic>{} : rawVerses.first;
    return MushafPage(
      number: page,
      juz: first['juz_number'] as int? ?? ((page - 1) ~/ 20) + 1,
      hizb: first['hizb_number'] as int? ?? ((page - 1) ~/ 10) + 1,
      surahName: surahName,
      ayahs: verses,
      riwayaId: riwayaId,
    );
  }

  String encode() => jsonEncode({'number': number, 'juz': juz, 'hizb': hizb, 'surahName': surahName, 'riwayaId': riwayaId, 'ayahs': ayahs.map((ayah) => ayah.toJson()).toList()});

  factory MushafPage.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return MushafPage(
      number: json['number'] as int,
      juz: json['juz'] as int,
      hizb: json['hizb'] as int,
      surahName: json['surahName'] as String,
      riwayaId: json['riwayaId'] as String? ?? 'hafs',
      ayahs: (json['ayahs'] as List<dynamic>).whereType<Map<String, dynamic>>().map(MushafAyah.fromJson).toList(),
    );
  }
}
