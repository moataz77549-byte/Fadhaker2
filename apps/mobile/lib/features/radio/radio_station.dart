import '../../core/models/app_models.dart';

/// نموذج محطة إذاعية يُدار بالكامل من Supabase (جدول app.stations).
///
/// يرث من [RadioStationModel] ليبقى متوافقًا مع الشيفرة القائمة التي تتعامل
/// مع النوع الأساسي (Dart covariance: ‏List<RadioStation>‏ تُسند إلى
/// ‏List<RadioStationModel>‏).
///
/// لا توجد هنا أي بيانات ثابتة: كل الحقول تُملأ من صفوف قاعدة البيانات،
/// ودوال الاشتقاق أدناه منطقٌ خالص قابل للاختبار دون شبكة.
enum StationKind {
  /// بث متواصل عام (تلاوات متنوعة)
  continuous,
  /// محطة قارئ محدد
  reciter,
  /// تفسير
  tafsir,
  /// دروس (حديث/سيرة/فتاوى/أذكار…)
  lesson,
  /// مشروع خاص
  privateProject,
}

String stationKindLabel(StationKind kind) {
  switch (kind) {
    case StationKind.continuous:
      return 'بث متواصل';
    case StationKind.reciter:
      return 'قارئ';
    case StationKind.tafsir:
      return 'تفسير';
    case StationKind.lesson:
      return 'دروس';
    case StationKind.privateProject:
      return 'مشروع خاص';
  }
}

/// اشتقاق نوع المحطة من تصنيفها (slug من app.categories) مع إمكانية
/// تجاوز صريح عبر metadata.station_kind في قاعدة البيانات.
StationKind stationKindFrom({
  String? categorySlug,
  Map<String, dynamic>? metadata,
}) {
  final override = metadata?['station_kind']?.toString().trim().toLowerCase();
  switch (override) {
    case 'continuous':
      return StationKind.continuous;
    case 'reciter':
      return StationKind.reciter;
    case 'tafsir':
    case 'tafseer':
      return StationKind.tafsir;
    case 'lesson':
      return StationKind.lesson;
    case 'private_project':
    case 'privateproject':
      return StationKind.privateProject;
  }
  if (metadata?['private_project'] == true) return StationKind.privateProject;

  switch (categorySlug?.toUpperCase()) {
    case 'RECITER':
      return StationKind.reciter;
    case 'TAFSEER':
    case 'TAFSIR':
      return StationKind.tafsir;
    case 'HADITH':
    case 'SEERAH':
    case 'SAHABAH':
    case 'FATWA':
    case 'ADHKAR':
    case 'RUQYAH':
      return StationKind.lesson;
    default:
      return StationKind.continuous;
  }
}

class RadioStation extends RadioStationModel {
  final String? nameEn;
  final String? logoUrl;
  /// رمز نوع البث من app.stream_types (MP3/AAC/SHOUTCAST/ICECAST/HLS…)
  final String streamType;
  final StationKind kind;
  final int sortOrder;
  final String? externalKey;
  final String? sourceUrl;

  const RadioStation({
    required super.id,
    required super.nameAr,
    required super.streamUrl,
    super.currentTrack = '',
    super.bitrateKbps = 128,
    super.isFeatured = false,
    super.fallbackUrl,
    this.nameEn,
    this.logoUrl,
    this.streamType = 'MP3',
    this.kind = StationKind.continuous,
    this.sortOrder = 0,
    this.externalKey,
    this.sourceUrl,
  });

  /// بناء من صف Supabase (app.stations) مع علاقة categories المضمّنة.
  factory RadioStation.fromSupabase(Map<String, dynamic> row) {
    final categories = row['categories'];
    String? categorySlug;
    if (categories is Map<String, dynamic>) {
      categorySlug = categories['slug']?.toString();
    } else if (categories is List && categories.isNotEmpty && categories.first is Map) {
      categorySlug = (categories.first as Map)['slug']?.toString();
    }
    final metadata = row['metadata'] is Map
        ? Map<String, dynamic>.from(row['metadata'] as Map)
        : <String, dynamic>{};
    int bitrate = 128;
    final metaBitrate = metadata['bitrate_kbps'] ?? metadata['bitrate'];
    if (metaBitrate is num) {
      bitrate = metaBitrate.toInt();
    } else if (metaBitrate is String) {
      bitrate = int.tryParse(metaBitrate) ?? 128;
    }

    return RadioStation(
      id: '${row['id'] ?? ''}',
      nameAr: '${row['name_ar'] ?? 'محطة إذاعية'}',
      streamUrl: '${row['stream_url'] ?? ''}'.trim(),
      fallbackUrl: _nullIfEmpty(row['fallback_stream_url']?.toString()),
      bitrateKbps: bitrate,
      isFeatured: row['is_featured'] == true,
      nameEn: row['name_en']?.toString(),
      logoUrl: _nullIfEmpty(row['logo_url']?.toString()),
      streamType: '${row['stream_type'] ?? 'MP3'}'.toUpperCase(),
      kind: stationKindFrom(categorySlug: categorySlug, metadata: metadata),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      externalKey: row['external_key']?.toString(),
      sourceUrl: row['source_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'name_en': nameEn,
        'stream_url': streamUrl,
        'fallback_stream_url': fallbackUrl,
        'logo_url': logoUrl,
        'stream_type': streamType,
        'kind': kind.name,
        'is_featured': isFeatured,
        'sort_order': sortOrder,
        'bitrate_kbps': bitrateKbps,
        'external_key': externalKey,
        'source_url': sourceUrl,
      };

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    StationKind kind = StationKind.continuous;
    for (final k in StationKind.values) {
      if (k.name == json['kind']) kind = k;
    }
    return RadioStation(
      id: '${json['id'] ?? ''}',
      nameAr: '${json['name_ar'] ?? 'محطة إذاعية'}',
      streamUrl: '${json['stream_url'] ?? ''}',
      fallbackUrl: _nullIfEmpty(json['fallback_stream_url']?.toString()),
      bitrateKbps: (json['bitrate_kbps'] as num?)?.toInt() ?? 128,
      isFeatured: json['is_featured'] == true,
      nameEn: json['name_en']?.toString(),
      logoUrl: _nullIfEmpty(json['logo_url']?.toString()),
      streamType: '${json['stream_type'] ?? 'MP3'}',
      kind: kind,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      externalKey: json['external_key']?.toString(),
      sourceUrl: json['source_url']?.toString(),
    );
  }

  static String? _nullIfEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }
}

/// محطات افتراضية مضمّنة — تعمل من الصندوق دون أي باك-إند.
///
/// كل رابط مُتحقق منه حيًّا (2026-09-23): HTTP 200 مع `Content-Type:
/// audio/mpeg` عبر طلب byte-range. المصدر: واجهة المحطات العامة
/// لـ mp3quran.net (`/api/v3/radios`) — 177 محطة حقيقية.
/// تُدمج بعد محطات Supabase الإنتاجية (بلا تكرار) في
/// [RadioCatalogService]، وتُستخدم وحدها عند تعذّر الشبكة.
const List<RadioStation> builtinRadioStations = [
  RadioStation(
    id: 'builtin-husary',
    nameAr: 'محمود خليل الحصري — بث مباشر (مرتل)',
    nameEn: 'Mahmoud Khalil Al-Husary',
    streamUrl: 'https://backup.qurango.net/radio/mahmoud_khalil_alhussary',
    streamType: 'MP3',
    kind: StationKind.reciter,
    sortOrder: 100,
    bitrateKbps: 128,
  ),
  RadioStation(
    id: 'builtin-minshawi',
    nameAr: 'محمد صديق المنشاوي — بث مباشر (مرتل)',
    nameEn: 'Mohammed Siddiq Al-Minshawi',
    streamUrl: 'https://backup.qurango.net/radio/mohammed_siddiq_alminshawi',
    streamType: 'MP3',
    kind: StationKind.reciter,
    sortOrder: 101,
    bitrateKbps: 128,
  ),
  RadioStation(
    id: 'builtin-maher',
    nameAr: 'ماهر المعيقلي — بث مباشر',
    nameEn: 'Maher Al-Muaiqly',
    streamUrl: 'https://backup.qurango.net/radio/maher',
    streamType: 'MP3',
    kind: StationKind.reciter,
    sortOrder: 102,
    bitrateKbps: 128,
  ),
  RadioStation(
    id: 'builtin-shatri',
    nameAr: 'أبو بكر الشاطري — بث مباشر',
    nameEn: 'Abu Bakr Al-Shatri',
    streamUrl: 'https://backup.qurango.net/radio/shaik_abu_bakr_al_shatri',
    streamType: 'MP3',
    kind: StationKind.reciter,
    sortOrder: 103,
    bitrateKbps: 128,
  ),
];
