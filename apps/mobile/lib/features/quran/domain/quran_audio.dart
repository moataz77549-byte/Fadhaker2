class QuranRecitation {
  const QuranRecitation({
    required this.id,
    required this.nameAr,
    this.style,
  });

  final int id;
  final String nameAr;
  final String? style;

  factory QuranRecitation.fromJson(Map<String, dynamic> json) => QuranRecitation(
        id: (json['id'] as num).toInt(),
        nameAr: (json['nameAr'] ?? json['reciter_name'] ?? '').toString(),
        style: json['style']?.toString(),
      );
}

class QuranAyahAudio {
  const QuranAyahAudio({
    required this.verseKey,
    required this.audioUrl,
    this.duration,
  });

  final String verseKey;
  final String audioUrl;
  final Duration? duration;
}
