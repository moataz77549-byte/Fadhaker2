class RadioStationModel {
  final String id;
  final String nameAr;
  final String streamUrl;
  final String currentTrack;
  final int bitrateKbps;
  final bool isFeatured;
  final int listenerCount;
  final String? fallbackUrl;

  const RadioStationModel({
    required this.id,
    required this.nameAr,
    required this.streamUrl,
    required this.currentTrack,
    this.bitrateKbps = 128,
    this.isFeatured = false,
    this.listenerCount = 0,
    this.fallbackUrl,
  });
}

class ReciterModel {
  final String id;
  final String nameAr;
  final String riwaya;
  final int surahsCount;
  final String bio;
  final String provider;
  final String audioQuality;

  const ReciterModel({
    required this.id,
    required this.nameAr,
    required this.riwaya,
    this.surahsCount = 114,
    this.bio = '',
    this.provider = 'مجمع الملك فهد / خوادم فذكر',
    this.audioQuality = '192 kbps • MP3',
  });
}

class PlaylistItemModel {
  final String id;
  final String title;
  final String subtitle;
  final String audioUrl;
  final int surahNumber;
  final String reciterId;

  const PlaylistItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.audioUrl,
    required this.surahNumber,
    required this.reciterId,
  });
}

class PlaylistModel {
  final String id;
  final String name;
  final List<PlaylistItemModel> items;
  final DateTime createdAt;

  const PlaylistModel({
    required this.id,
    required this.name,
    this.items = const [],
    required this.createdAt,
  });

  PlaylistModel copyWith({
    String? name,
    List<PlaylistItemModel>? items,
  }) {
    return PlaylistModel(
      id: id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt,
    );
  }
}

enum DownloadStatus {
  queued,
  downloading,
  paused,
  failed,
  completed,
}

class DownloadTaskModel {
  final String id;
  final int surahNumber;
  final String surahNameAr;
  final String reciterNameAr;
  final String expectedSha256;
  final int progressPercent;
  final DownloadStatus status;
  final String? localPath;
  final int totalBytes;
  final int downloadedBytes;

  const DownloadTaskModel({
    required this.id,
    required this.surahNumber,
    required this.surahNameAr,
    required this.reciterNameAr,
    required this.expectedSha256,
    this.progressPercent = 0,
    this.status = DownloadStatus.queued,
    this.localPath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
  });

  DownloadTaskModel copyWith({
    int? progressPercent,
    DownloadStatus? status,
    String? localPath,
    int? downloadedBytes,
  }) {
    return DownloadTaskModel(
      id: id,
      surahNumber: surahNumber,
      surahNameAr: surahNameAr,
      reciterNameAr: reciterNameAr,
      expectedSha256: expectedSha256,
      progressPercent: progressPercent ?? this.progressPercent,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    );
  }
}

class PrayerTimesModel {
  final String city;
  final String timezone;
  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;
  final String nextPrayerName;
  final String nextPrayerRemaining;

  const PrayerTimesModel({
    this.city = '',
    this.timezone = '',
    this.fajr = '',
    this.sunrise = '',
    this.dhuhr = '',
    this.asr = '',
    this.maghrib = '',
    this.isha = '',
    this.nextPrayerName = '',
    this.nextPrayerRemaining = '',
  });
}

class DhikrModel {
  final String id;
  final String title;
  final String text;
  final int targetCount;
  final int currentCount;
  final String reward;

  const DhikrModel({
    required this.id,
    required this.title,
    required this.text,
    required this.targetCount,
    this.currentCount = 0,
    this.reward = '',
  });

  DhikrModel copyWith({int? currentCount}) {
    return DhikrModel(
      id: id,
      title: title,
      text: text,
      targetCount: targetCount,
      currentCount: currentCount ?? this.currentCount,
      reward: reward,
    );
  }
}

class MemorizationPlanModel {
  final String id;
  final String title;
  final String targetSurah;
  final int currentVerse;
  final int targetVerse;
  final int completedPercent;
  final int dueReviewDays;

  const MemorizationPlanModel({
    required this.id,
    required this.title,
    required this.targetSurah,
    required this.currentVerse,
    required this.targetVerse,
    required this.completedPercent,
    required this.dueReviewDays,
  });
}
