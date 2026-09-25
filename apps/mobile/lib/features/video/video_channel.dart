/// نموذج قناة فيديو تُقرأ من Supabase (جدول app.video_channels).
///
/// لا توجد روابط ثابتة في كود Dart إطلاقًا: كل القنوات — بما فيها روابط
/// الاختبار — تأتي من قاعدة البيانات (أو ملف الـ seed الموثّق).
/// عند غياب الجدول يُرجع المستودع قائمة فارغة (empty state).

/// نوع مصدر الفيديو — يُشتق من الرابط.
enum VideoSourceType {
  hls,
  youtube,
  mp4,
  unknown,
}

String videoSourceTypeLabel(VideoSourceType type) {
  switch (type) {
    case VideoSourceType.hls:
      return 'بث مباشر (HLS)';
    case VideoSourceType.youtube:
      return 'يوتيوب';
    case VideoSourceType.mp4:
      return 'فيديو (MP4)';
    case VideoSourceType.unknown:
      return 'فيديو';
  }
}

/// اشتقاق نوع المصدر من الرابط — منطق خالص قابل للاختبار.
VideoSourceType videoSourceTypeFromUrl(String url) {
  final normalized = url.trim().toLowerCase();
  if (normalized.isEmpty) return VideoSourceType.unknown;
  if (_youtubeVideoId(normalized) != null) return VideoSourceType.youtube;
  if (normalized.contains('.m3u8')) return VideoSourceType.hls;
  if (normalized.contains('.mp4')) return VideoSourceType.mp4;
  return VideoSourceType.unknown;
}

/// استخراج معرّف فيديو يوتيوب من مختلف صيغ الروابط.
/// يدعم: watch?v=, youtu.be/, ‎/embed/‎, ‎/shorts/‎, ‎/live/‎ — منطق خالص قابل للاختبار.
String? youtubeVideoIdFromUrl(String url) => _youtubeVideoId(url.trim());

String? _youtubeVideoId(String url) {
  if (url.isEmpty) return null;
  // معرّفات يوتيوب لا تُستخرج إلا من نطاقات يوتيوب نفسها، حتى لا يُساء
  // تصنيف روابط HLS/MP4 التي تحوي مقاطع مثل ‎/live/‎ في مسارها.
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  final isYouTubeHost = host == 'youtu.be' ||
      host.endsWith('.youtu.be') ||
      host.contains('youtube.com') ||
      host.contains('youtube-nocookie.com');
  if (!isYouTubeHost) return null;
  // caseSensitive: false للحروف الثابتة فقط — مجموعة الالتقاط تحفظ حالة الأحرف الأصلية.
  final patterns = <RegExp>[
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11,})', caseSensitive: false),
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11,})', caseSensitive: false),
    RegExp(r'/embed/([A-Za-z0-9_-]{11,})', caseSensitive: false),
    RegExp(r'/shorts/([A-Za-z0-9_-]{11,})', caseSensitive: false),
    RegExp(r'/live/([A-Za-z0-9_-]{11,})', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final id = pattern.firstMatch(url)?.group(1);
    if (id != null) return id;
  }
  return null;
}

class VideoChannel {
  final String id;
  final String nameAr;
  final String? nameEn;
  final String streamUrl;
  final String? logoUrl;
  final VideoSourceType sourceType;
  final bool isActive;
  final int sortOrder;

  const VideoChannel({
    required this.id,
    required this.nameAr,
    this.nameEn,
    required this.streamUrl,
    this.logoUrl,
    this.sourceType = VideoSourceType.unknown,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// معرّف يوتيوب عند الحاجة (لقنوات يوتيوب فقط).
  String? get youtubeVideoId =>
      sourceType == VideoSourceType.youtube ? youtubeVideoIdFromUrl(streamUrl) : null;

  factory VideoChannel.fromSupabase(Map<String, dynamic> row) {
    final url = '${row['stream_url'] ?? row['url'] ?? ''}'.trim();
    return VideoChannel(
      id: '${row['id'] ?? url.hashCode}',
      nameAr: '${row['name_ar'] ?? row['title'] ?? 'قناة مرئية'}',
      nameEn: row['name_en']?.toString(),
      streamUrl: url,
      logoUrl: _nullIfEmpty(row['logo_url']?.toString() ?? row['thumbnail_url']?.toString()),
      sourceType: videoSourceTypeFromUrl(url),
      isActive: row['is_active'] != false,
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        'stream_url': streamUrl,
        'logo_url': logoUrl,
        'source_type': sourceType.name,
        'is_active': isActive,
        'sort_order': sortOrder,
      };

  factory VideoChannel.fromJson(Map<String, dynamic> json) {
    VideoSourceType type = VideoSourceType.unknown;
    for (final t in VideoSourceType.values) {
      if (t.name == json['source_type']) type = t;
    }
    return VideoChannel(
      id: '${json['id'] ?? ''}',
      nameAr: '${json['name_ar'] ?? 'قناة مرئية'}',
      nameEn: json['name_en']?.toString(),
      streamUrl: '${json['stream_url'] ?? ''}',
      logoUrl: _nullIfEmpty(json['logo_url']?.toString()),
      sourceType: type,
      isActive: json['is_active'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  static String? _nullIfEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }
}
