import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config/supabase_config.dart';
import 'notification_service.dart';
import '../../features/quran/data/surah_metadata.dart';

const _androidDownloadRecoveryUniqueName =
    'fadhkur.android.quran.download.recovery';
const _androidDownloadRecoveryTask =
    'fadhkur.android.quran.download.recovery.task';
const _prayerRenewalUniqueName = 'fadhkur.android.prayer.renewal';
const _prayerRenewalTask = 'fadhkur.android.prayer.renewal.task';

/// Android-only recovery entrypoint. WorkManager starts this in a separate
/// Flutter isolate after the UI process has been backgrounded or killed.
@pragma('vm:entry-point')
void androidDownloadRecoveryDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == _prayerRenewalTask) {
      try {
        await LocalAlarmScheduler().restorePrayerAlarms();
        return true;
      } catch (_) {
        return false;
      }
    }
    if (taskName != _androidDownloadRecoveryTask) return true;
    try {
      return await quranDownloadManager.runBackgroundRecovery();
    } catch (_) {
      return false;
    }
  });
}

/// Initializes WorkManager only on Android. No iOS background-task
/// configuration is used by the current product.
Future<void> initializeAndroidDownloadRecovery() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(androidDownloadRecoveryDispatcher);
  // The exact alarm window is five days. Replenish it in the background even
  // when the user has not opened the app; the worker checks opt-in locally.
  await Workmanager().registerPeriodicTask(
    _prayerRenewalUniqueName,
    _prayerRenewalTask,
    frequency: const Duration(hours: 12),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Schedules a delayed recovery worker. Foreground downloads continue
/// immediately; WorkManager only takes over if that process stops making
/// progress. A single unique task covers the whole persisted queue.
Future<void> _scheduleAndroidDownloadRecovery() async {
  if (!Platform.isAndroid) return;
  await Workmanager().registerOneOffTask(
    _androidDownloadRecoveryUniqueName,
    _androidDownloadRecoveryTask,
    initialDelay: const Duration(minutes: 2),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
      requiresStorageNotLow: true,
    ),
  );
}

/// حالات مهمة التحميل.
enum DownloadJobStatus {
  queued,
  downloading,
  paused,
  failed,
  completed,
  canceled,
}

String downloadJobStatusLabel(DownloadJobStatus status) {
  switch (status) {
    case DownloadJobStatus.queued:
      return 'في الانتظار';
    case DownloadJobStatus.downloading:
      return 'جارٍ التحميل';
    case DownloadJobStatus.paused:
      return 'متوقف مؤقتًا';
    case DownloadJobStatus.failed:
      return 'فشل';
    case DownloadJobStatus.completed:
      return 'مكتمل';
    case DownloadJobStatus.canceled:
      return 'ملغي';
  }
}

/// مهمة تحميل سورة — قابلة للتسلسل لاستعادة الحالة بعد إعادة التشغيل.
class DownloadJob {
  final String id;
  final int surahNumber;
  final String surahNameAr;
  final String reciterNameAr;
  final String reciterPath;
  final int firstAyah;
  final int lastAyah;
  final String? expectedSha256;
  final DownloadJobStatus status;
  final int completedAyahs;
  final int downloadedBytes;
  final String? localPath;
  final String? actualSha256;
  final String? errorMessage;
  final int attempts;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DownloadJob({
    required this.id,
    required this.surahNumber,
    required this.surahNameAr,
    required this.reciterNameAr,
    required this.reciterPath,
    required this.firstAyah,
    required this.lastAyah,
    this.expectedSha256,
    this.status = DownloadJobStatus.queued,
    this.completedAyahs = 0,
    this.downloadedBytes = 0,
    this.localPath,
    this.actualSha256,
    this.errorMessage,
    this.attempts = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  int get totalAyahs => max(1, lastAyah - firstAyah + 1);
  double get progress => (completedAyahs / totalAyahs).clamp(0.0, 1.0);
  int get progressPercent => (progress * 100).round();

  bool get isActive => status == DownloadJobStatus.queued || status == DownloadJobStatus.downloading;
  bool get isFinished =>
      status == DownloadJobStatus.completed || status == DownloadJobStatus.canceled;

  DownloadJob copyWith({
    DownloadJobStatus? status,
    int? completedAyahs,
    int? downloadedBytes,
    String? localPath,
    String? actualSha256,
    String? errorMessage,
    int? attempts,
  }) {
    return DownloadJob(
      id: id,
      surahNumber: surahNumber,
      surahNameAr: surahNameAr,
      reciterNameAr: reciterNameAr,
      reciterPath: reciterPath,
      firstAyah: firstAyah,
      lastAyah: lastAyah,
      expectedSha256: expectedSha256,
      status: status ?? this.status,
      completedAyahs: completedAyahs ?? this.completedAyahs,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      localPath: localPath ?? this.localPath,
      actualSha256: actualSha256 ?? this.actualSha256,
      errorMessage: errorMessage,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'surahNumber': surahNumber,
        'surahNameAr': surahNameAr,
        'reciterNameAr': reciterNameAr,
        'reciterPath': reciterPath,
        'firstAyah': firstAyah,
        'lastAyah': lastAyah,
        'expectedSha256': expectedSha256,
        'status': status.name,
        'completedAyahs': completedAyahs,
        'downloadedBytes': downloadedBytes,
        'localPath': localPath,
        'actualSha256': actualSha256,
        'errorMessage': errorMessage,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DownloadJob.fromJson(Map<String, dynamic> json) {
    DownloadJobStatus status = DownloadJobStatus.queued;
    for (final s in DownloadJobStatus.values) {
      if (s.name == json['status']) status = s;
    }
    // مهمة كانت قيد التحميل عند إغلاق التطبيق تُستعاد كمنتظرة (تُستأنف لاحقًا).
    if (status == DownloadJobStatus.downloading) status = DownloadJobStatus.queued;
    return DownloadJob(
      id: '${json['id']}',
      surahNumber: (json['surahNumber'] as num?)?.toInt() ?? 0,
      surahNameAr: '${json['surahNameAr'] ?? ''}',
      reciterNameAr: '${json['reciterNameAr'] ?? ''}',
      reciterPath: '${json['reciterPath'] ?? ''}',
      firstAyah: (json['firstAyah'] as num?)?.toInt() ?? 1,
      lastAyah: (json['lastAyah'] as num?)?.toInt() ?? 1,
      expectedSha256: json['expectedSha256']?.toString(),
      status: status,
      completedAyahs: (json['completedAyahs'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      localPath: json['localPath']?.toString(),
      actualSha256: json['actualSha256']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
    );
  }
}

/// بيانات السورة (عدد الآيات): Supabase أولًا، ثم الكاش، ثم البيانات
/// البنيوية المضمّنة (114 سورة — حقائق ثابتة). لا تُرمى أخطاء قاتلة.
class SurahMetadataService {
  static const _cacheKey = 'fadhkur.surah_meta.v1';

  Future<_SurahMeta?> fetchSurah(int number) async {
    final cached = await _cached(number);
    try {
      final remote = await _fetchRemote();
      if (remote.isNotEmpty) {
        await _saveCache(remote);
        return remote[number];
      }
    } catch (_) {}
    if (cached != null) return cached;
    // Offline-first: البيانات المضمّنة حقيقية (الاسم وعدد الآيات).
    if (number >= 1 && number <= allSurahs.length) {
      final meta = allSurahs[number - 1];
      return _SurahMeta(number: meta.number, nameAr: meta.name, ayahCount: meta.ayahs);
    }
    return null;
  }

  Future<Map<int, _SurahMeta>> _fetchRemote() async {
    if (!SupabaseConfig.isConfigured) throw StateError('Supabase is not configured');
    final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/surahs')
        .replace(queryParameters: {'select': 'number,name_ar,ayah_count', 'order': 'number.asc'});
    final response = await http.get(uri, headers: {
      'apikey': SupabaseConfig.publishableKey,
      'Authorization': 'Bearer ${SupabaseConfig.publishableKey}',
      'Accept-Profile': 'app',
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Surah metadata request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final result = <int, _SurahMeta>{};
    if (decoded is List) {
      for (final e in decoded.whereType<Map>()) {
        final n = (e['number'] as num?)?.toInt();
        final count = (e['ayah_count'] as num?)?.toInt();
        if (n != null && count != null && count > 0) {
          result[n] = _SurahMeta(number: n, nameAr: '${e['name_ar'] ?? ''}', ayahCount: count);
        }
      }
    }
    return result;
  }

  Future<void> _saveCache(Map<int, _SurahMeta> meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(meta.map((k, v) => MapEntry('$k', v.toJson()))),
    );
  }

  Future<_SurahMeta?> _cached(int number) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = decoded['$number'];
      if (entry is! Map) return null;
      return _SurahMeta.fromJson(Map<String, dynamic>.from(entry));
    } catch (_) {
      return null;
    }
  }
}

class _SurahMeta {
  final int number;
  final String nameAr;
  final int ayahCount;
  const _SurahMeta({required this.number, required this.nameAr, required this.ayahCount});

  Map<String, dynamic> toJson() => {'number': number, 'nameAr': nameAr, 'ayahCount': ayahCount};

  factory _SurahMeta.fromJson(Map<String, dynamic> json) => _SurahMeta(
        number: (json['number'] as num?)?.toInt() ?? 0,
        nameAr: '${json['nameAr'] ?? ''}',
        ayahCount: (json['ayahCount'] as num?)?.toInt() ?? 0,
      );
}

/// مدير التحميل: طابور، إيقاف مؤقت، استئناف، إعادة محاولة، تقدّم، إلغاء، حذف،
/// تحقق SHA-256 عند توفر الـ hash، واستعادة المهام بعد إعادة التشغيل.
///
/// يعمل على ملفات الآيات من everyayah (نمط التسمية 001001.mp3) ويجمعها في
/// ملف واحد لكل سورة. الاستئناف على مستوى الآية: الأجزاء المكتملة تُحفظ
/// في مجلد مؤقت ولا تُحمَّل مجددًا.
class QuranDownloadManager {
  static const _jobsKey = 'fadhkur.download_manager.v1';
  static const _base = 'https://everyayah.com/data';
  static const _maxAttempts = 3;

  final _controller = StreamController<List<DownloadJob>>.broadcast();
  final Map<String, DownloadJob> _jobs = {};
  final SurahMetadataService _surahMeta = SurahMetadataService();

  bool _initialized = false;
  bool _workerRunning = false;
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelRequested = {};

  Stream<List<DownloadJob>> get jobsStream => _controller.stream;
  List<DownloadJob> get jobs {
    final list = _jobs.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// استعادة المهام المحفوظة — تُستدعى مرة واحدة عند بدء التطبيق.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jobsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded.whereType<Map>()) {
            final job = DownloadJob.fromJson(Map<String, dynamic>.from(e));
            // المهام الملغاة لا تُستعاد.
            if (job.status != DownloadJobStatus.canceled) {
              _jobs[job.id] = job;
            }
          }
        }
      } catch (_) {}
    }
    _emit();
    _pump();
  }

  /// إضافة مهمة تحميل سورة كاملة. عدد الآيات يُجلب من Supabase (app.surahs).
  Future<DownloadJob> enqueueSurah({
    required int surahNumber,
    String? surahNameAr,
    required String reciterNameAr,
    required String reciterPath,
    String? expectedSha256,
  }) async {
    await init();
    // منع التكرار: مهمة نشطة لنفس السورة والقارئ تُعاد كما هي.
    for (final job in _jobs.values) {
      if (job.surahNumber == surahNumber &&
          job.reciterPath == reciterPath &&
          !job.isFinished &&
          job.status != DownloadJobStatus.failed) {
        return job;
      }
    }
    final meta = await _surahMeta.fetchSurah(surahNumber);
    if (meta == null || meta.ayahCount <= 0) {
      throw StateError('تعذّر تحديد عدد آيات السورة $surahNumber.');
    }
    final now = DateTime.now();
    final job = DownloadJob(
      id: 'dl-${now.millisecondsSinceEpoch}-${surahNumber}',
      surahNumber: surahNumber,
      surahNameAr: (surahNameAr?.isNotEmpty ?? false) ? surahNameAr! : meta.nameAr,
      reciterNameAr: reciterNameAr,
      reciterPath: reciterPath,
      firstAyah: 1,
      lastAyah: meta.ayahCount,
      expectedSha256: (expectedSha256?.isNotEmpty ?? false) ? expectedSha256 : null,
      createdAt: now,
      updatedAt: now,
    );
    _jobs[job.id] = job;
    await _persist();
    _emit();
    _pump();
    unawaited(_scheduleAndroidDownloadRecovery());
    return job;
  }

  /// مهمة بمدى آيات صريح (للتوافق مع الواجهة القديمة).
  Future<DownloadJob> enqueueRange({
    required int surahNumber,
    required String surahNameAr,
    required String reciterNameAr,
    required String reciterPath,
    required int firstAyah,
    required int lastAyah,
    String? expectedSha256,
  }) async {
    await init();
    if (firstAyah < 1 || lastAyah < firstAyah) {
      throw ArgumentError('نطاق آيات غير صالح: $firstAyah-$lastAyah');
    }
    final now = DateTime.now();
    final job = DownloadJob(
      id: 'dl-${now.millisecondsSinceEpoch}-${surahNumber}',
      surahNumber: surahNumber,
      surahNameAr: surahNameAr,
      reciterNameAr: reciterNameAr,
      reciterPath: reciterPath,
      firstAyah: firstAyah,
      lastAyah: lastAyah,
      expectedSha256: (expectedSha256?.isNotEmpty ?? false) ? expectedSha256 : null,
      createdAt: now,
      updatedAt: now,
    );
    _jobs[job.id] = job;
    await _persist();
    _emit();
    _pump();
    unawaited(_scheduleAndroidDownloadRecovery());
    return job;
  }

  Future<void> pause(String id) async {
    final job = _jobs[id];
    if (job == null || !job.isActive) return;
    // الحالة أولًا ثم إغلاق العميل: أي طلب جارٍ سيرى الحالة الجديدة
    // ويُترجم لاستثناء إيقاف بدل فشل.
    _jobs[id] = job.copyWith(status: DownloadJobStatus.paused, errorMessage: null);
    await _persist();
    _emit();
    _activeClients[id]?.close();
    _activeClients.remove(id);
  }

  Future<void> resume(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    if (job.status != DownloadJobStatus.paused && job.status != DownloadJobStatus.failed) return;
    _jobs[id] = job.copyWith(status: DownloadJobStatus.queued, errorMessage: null, attempts: 0);
    await _persist();
    _emit();
    _pump();
    unawaited(_scheduleAndroidDownloadRecovery());
  }

  Future<void> retry(String id) => resume(id);

  /// إلغاء مهمة نشطة وحذف أجزائها المؤقتة (دون حذف ملف مكتمل إن وُجد).
  Future<void> cancel(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    _cancelRequested.add(id);
    _activeClients[id]?.close();
    _activeClients.remove(id);
    await _deletePartsDir(job);
    _jobs.remove(id);
    await _persist();
    _emit();
    _pump();
  }

  /// حذف مهمة وملفاتها (المؤقتة والنهائية) من الجهاز.
  Future<void> delete(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    _cancelRequested.add(id);
    _activeClients[id]?.close();
    _activeClients.remove(id);
    await _deletePartsDir(job);
    final path = job.localPath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _jobs.remove(id);
    await _persist();
    _emit();
    _pump();
  }

  // ---------- العامل الداخلي ----------

  void _pump() {
    if (_workerRunning) return;
    final next = jobs.where((j) => j.status == DownloadJobStatus.queued).toList();
    if (next.isEmpty) return;
    _workerRunning = true;
    // الأقدم أولًا.
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _run(next.first.id).whenComplete(() {
      _workerRunning = false;
      _pump();
    });
  }

  Future<void> _run(String id) async {
    final initial = _jobs[id];
    if (initial == null || initial.status != DownloadJobStatus.queued) return;
    _cancelRequested.remove(id);

    var job = initial.copyWith(status: DownloadJobStatus.downloading, errorMessage: null);
    _jobs[id] = job;
    await _persist();
    _emit();

    final client = http.Client();
    _activeClients[id] = client;
    try {
      final partsDir = await _partsDir(job);
      for (var ayah = job.firstAyah + job.completedAyahs; ayah <= job.lastAyah; ayah++) {
        if (_cancelRequested.contains(id)) return;
        final current = _jobs[id];
        if (current == null || current.status != DownloadJobStatus.downloading) return;

        final partFile = File('${partsDir.path}/${ayah.toString().padLeft(3, '0')}.mp3');
        // The loop starts at the first uncounted ayah. Any file already at
        // this path may be a truncated remnant from a killed process, so it is
        // deliberately re-downloaded rather than trusted by file length alone.
        if (await partFile.exists()) {
          await partFile.delete();
        }
        await _downloadAyahWithRetry(client, job, ayah, partFile);
        if (_cancelRequested.contains(id)) return;
        final updated = _jobs[id];
        if (updated == null || updated.status != DownloadJobStatus.downloading) return;
        final bytes = await partFile.length();
        _jobs[id] = updated.copyWith(
          completedAyahs: updated.completedAyahs + 1,
          downloadedBytes: updated.downloadedBytes + bytes,
        );
        await _persist();
        _emit();
      }
      await _finalize(id);
    } on _PausedException {
      // تم التعامل معها في pause().
    } catch (e) {
      final failed = _jobs[id];
      if (failed != null && failed.status == DownloadJobStatus.downloading) {
        _jobs[id] = failed.copyWith(
          status: DownloadJobStatus.failed,
          errorMessage: _friendlyError(e),
        );
        await _persist();
        _emit();
      }
    } finally {
      _activeClients.remove(id);
      try {
        client.close();
      } catch (_) {}
    }
  }

  Future<void> _downloadAyahWithRetry(
    http.Client client,
    DownloadJob job,
    int ayah,
    File partFile,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (_cancelRequested.contains(job.id)) throw _CancelledException();
      final current = _jobs[job.id];
      if (current == null || current.status != DownloadJobStatus.downloading) {
        throw _PausedException();
      }
      try {
        await _downloadAyah(client, job, ayah, partFile);
        return;
      } catch (e) {
        lastError = e;
        if (e is _PausedException || e is _CancelledException) rethrow;
        // الإيقاف/الإلغاء أثناء فترة الانتظار بين المحاولات.
        if (_cancelRequested.contains(job.id)) throw _CancelledException();
        final current = _jobs[job.id];
        if (current == null || current.status != DownloadJobStatus.downloading) {
          throw _PausedException();
        }
        if (attempt < _maxAttempts) {
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
        }
      }
    }
    throw lastError ?? StateError('فشل تحميل الآية $ayah');
  }

  Future<void> _downloadAyah(
    http.Client client,
    DownloadJob job,
    int ayah,
    File partFile,
  ) async {
    final url =
        '$_base/${job.reciterPath}/${job.surahNumber.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';
    http.StreamedResponse response;
    try {
      final request = http.Request('GET', Uri.parse(url));
      response = await client.send(request).timeout(const Duration(seconds: 30));
    } on http.ClientException {
      // إغلاق العميل أثناء الإيقاف المؤقت/الإلغاء.
      final current = _jobs[job.id];
      if (current == null || current.status != DownloadJobStatus.downloading) {
        throw _PausedException();
      }
      rethrow;
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('فشل تحميل الآية $ayah: ${response.statusCode}');
    }
    final tempFile = File('${partFile.path}.download');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    final sink = tempFile.openWrite();
    try {
      await sink.addStream(response.stream);
      await sink.flush();
      await sink.close();
      if (await partFile.exists()) await partFile.delete();
      await tempFile.rename(partFile.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _finalize(String id) async {
    var job = _jobs[id];
    if (job == null) return;
    final partsDir = await _partsDir(job);
    final directory = await getApplicationDocumentsDirectory();
    final root = Directory('${directory.path}/quran/${job.reciterPath}');
    await root.create(recursive: true);
    final output = File(
        '${root.path}/${job.surahNumber.toString().padLeft(3, '0')}_${job.firstAyah}_${job.lastAyah}.mp3');

    final sink = output.openWrite();
    try {
      for (var ayah = job.firstAyah; ayah <= job.lastAyah; ayah++) {
        final part = File('${partsDir.path}/${ayah.toString().padLeft(3, '0')}.mp3');
        if (!await part.exists()) {
          throw StateError('جزء مفقود للآية $ayah — أعد المحاولة.');
        }
        await sink.addStream(part.openRead());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    // التحقق من SHA-256 عند توفر الـ hash المتوقع.
    final digest = await sha256.bind(output.openRead()).first;
    final actualSha = digest.toString();
    final expected = job.expectedSha256;
    if (expected != null && expected.isNotEmpty && expected.toLowerCase() != actualSha.toLowerCase()) {
      try {
        await output.delete();
      } catch (_) {}
      _jobs[id] = job.copyWith(
        status: DownloadJobStatus.failed,
        errorMessage: 'فشل التحقق من سلامة الملف (SHA-256 غير متطابق).',
        actualSha256: actualSha,
      );
      await _persist();
      _emit();
      return;
    }

    await _deletePartsDir(job);
    _jobs[id] = job.copyWith(
      status: DownloadJobStatus.completed,
      completedAyahs: job.totalAyahs,
      localPath: output.path,
      actualSha256: actualSha,
      errorMessage: null,
    );
    await _persist();
    _emit();
  }

  Future<Directory> _partsDir(DownloadJob job) async {
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory('${directory.path}/quran/${job.reciterPath}/parts_${job.id}');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deletePartsDir(DownloadJob job) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dir = Directory('${directory.path}/quran/${job.reciterPath}/parts_${job.id}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  String _friendlyError(Object e) {
    if (e is SocketException) return 'انقطع الاتصال بالشبكة.';
    if (e is TimeoutException) return 'انتهت مهلة الاتصال.';
    if (e is HttpException) return e.message;
    if (e is StateError) return e.message;
    return 'خطأ غير متوقع أثناء التحميل.';
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    // لا نحفظ المهام الملغاة.
    final list = _jobs.values
        .where((j) => j.status != DownloadJobStatus.canceled)
        .map((j) => j.toJson())
        .toList();
    await prefs.setString(_jobsKey, jsonEncode(list));
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(jobs);
  }

  /// WorkManager recovery runner.
  ///
  /// If the foreground process is still updating a download, return false so
  /// Android retries later instead of starting a duplicate transfer. If the
  /// persisted "downloading" state is stale, init() converts it back to queued
  /// and resumes from the first uncounted ayah. The worker voluntarily stops
  /// before Android's regular worker time limit; another retry can continue.
  Future<bool> runBackgroundRecovery({
    Duration activeFreshness = const Duration(minutes: 3),
    Duration maxRun = const Duration(minutes: 8),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jobsKey);
    if (raw == null || raw.isEmpty) return true;

    bool hasRecoverableWork = false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return true;
      final now = DateTime.now();
      for (final entry in decoded.whereType<Map>()) {
        final row = Map<String, dynamic>.from(entry);
        final status = row['status']?.toString() ?? '';
        if (status == DownloadJobStatus.downloading.name) {
          final updated = DateTime.tryParse(row['updatedAt']?.toString() ?? '');
          if (updated != null && now.difference(updated) < activeFreshness) {
            // Another isolate/process is probably still making progress.
            return false;
          }
          hasRecoverableWork = true;
        } else if (status == DownloadJobStatus.queued.name) {
          hasRecoverableWork = true;
        }
      }
    } catch (_) {
      return true;
    }

    if (!hasRecoverableWork) return true;

    await init();
    if (!jobs.any((j) => j.isActive)) return true;

    final completer = Completer<bool>();
    late final StreamSubscription<List<DownloadJob>> subscription;
    Timer? timeout;

    void check(List<DownloadJob> current) {
      if (!completer.isCompleted && !current.any((job) => job.isActive)) {
        completer.complete(true);
      }
    }

    subscription = jobsStream.listen(check);
    check(jobs);
    timeout = Timer(maxRun, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final result = await completer.future;
    timeout.cancel();
    await subscription.cancel();
    return result;
  }

  /// إغلاق المدير (للاختبارات).
  Future<void> dispose() async {
    for (final client in _activeClients.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _activeClients.clear();
    await _controller.close();
  }
}

class _PausedException implements Exception {}

class _CancelledException implements Exception {}

final quranDownloadManager = QuranDownloadManager();

// ---------------------------------------------------------------------------
// واجهة توافقية قديمة — تُستخدم من الشيفرة التي لم تُحدَّث بعد.
// تُحوَّل داخليًا إلى مدير التحميل الجديد.
// ---------------------------------------------------------------------------

class QuranDownloadResult {
  final String path;
  final int bytes;
  final String sha256;
  const QuranDownloadResult({required this.path, required this.bytes, required this.sha256});
}

class QuranDownloadService {
  static const _indexKey = 'fadhkur.downloads.v1';

  Future<QuranDownloadResult> downloadSurah({
    required int surah,
    required String reciterPath,
    required int firstAyah,
    required int lastAyah,
    void Function(double progress)? onProgress,
  }) async {
    final job = await quranDownloadManager.enqueueRange(
      surahNumber: surah,
      surahNameAr: 'سورة $surah',
      reciterNameAr: '',
      reciterPath: reciterPath,
      firstAyah: firstAyah,
      lastAyah: lastAyah,
    );
    // حماية من السباق: قد تكتمل المهمة قبل بدء الاستماع للبث.
    final already = quranDownloadManager._jobs[job.id];
    if (already != null && already.status == DownloadJobStatus.completed) {
      final result = QuranDownloadResult(
        path: already.localPath ?? '',
        bytes: already.downloadedBytes,
        sha256: already.actualSha256 ?? '',
      );
      await _remember(result.path, result.sha256);
      return result;
    }
    await for (final _ in quranDownloadManager.jobsStream) {
      final current = quranDownloadManager._jobs[job.id];
      if (current == null) throw StateError('أُلغيت مهمة التحميل.');
      onProgress?.call(current.progress);
      if (current.status == DownloadJobStatus.completed) {
        final result = QuranDownloadResult(
          path: current.localPath ?? '',
          bytes: current.downloadedBytes,
          sha256: current.actualSha256 ?? '',
        );
        await _remember(result.path, result.sha256);
        return result;
      }
      if (current.status == DownloadJobStatus.failed) {
        throw StateError(current.errorMessage ?? 'فشل التحميل.');
      }
      if (current.status == DownloadJobStatus.canceled) {
        throw StateError('أُلغيت مهمة التحميل.');
      }
    }
    throw StateError('توقف مدير التحميل بشكل غير متوقع.');
  }

  Future<void> _remember(String path, String sha) async {
    final prefs = await SharedPreferences.getInstance();
    final current = jsonDecode(prefs.getString(_indexKey) ?? '[]');
    final list = current is List ? current.whereType<Map>().toList() : <Map>[];
    list.removeWhere((e) => e['path'] == path);
    list.add({'path': path, 'sha256': sha, 'savedAt': DateTime.now().toIso8601String()});
    await prefs.setString(_indexKey, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> index() async {
    final completed = quranDownloadManager.jobs
        .where((j) => j.status == DownloadJobStatus.completed && (j.localPath?.isNotEmpty ?? false));
    return completed
        .map((j) => {
              'path': j.localPath!,
              'sha256': j.actualSha256 ?? '',
              'surahNameAr': j.surahNameAr,
              'reciterNameAr': j.reciterNameAr,
              'savedAt': j.updatedAt.toIso8601String(),
            })
        .toList();
  }
}

final quranDownloadService = QuranDownloadService();
