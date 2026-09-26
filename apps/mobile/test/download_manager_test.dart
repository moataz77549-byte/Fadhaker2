import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/core/services/quran_download_service.dart';

DownloadJob _job({
  DownloadJobStatus status = DownloadJobStatus.queued,
  int completedAyahs = 0,
}) {
  final now = DateTime(2026, 9, 23);
  return DownloadJob(
    id: 'dl-1',
    surahNumber: 36,
    surahNameAr: 'يس',
    reciterNameAr: 'القارئ',
    reciterPath: 'Reciter_64kbps',
    firstAyah: 1,
    lastAyah: 83,
    status: status,
    completedAyahs: completedAyahs,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('DownloadJob', () {
    test('progress is completedAyahs / totalAyahs', () {
      final job = _job(completedAyahs: 41);
      expect(job.totalAyahs, 83);
      expect(job.progress, closeTo(41 / 83, 0.0001));
      expect(job.progressPercent, (41 / 83 * 100).round());
    });

    test('progress is 0 for a fresh job and 1 when done', () {
      expect(_job().progress, 0.0);
      expect(_job(completedAyahs: 83).progress, 1.0);
    });

    test('whole-surah progress and resumable fields survive restart', () {
      final now = DateTime(2026, 9, 26);
      final job = DownloadJob(
        id: 'rec-1', surahNumber: 1, surahNameAr: 'الفاتحة',
        reciterNameAr: 'القارئ', reciterPath: 'reader/moshaf',
        sourceUrl: 'https://server.mp3quran.net/001.mp3',
        firstAyah: 1, lastAyah: 1, downloadedBytes: 512,
        totalBytes: 1024, status: DownloadJobStatus.downloading,
        localPath: '/tmp/surah_001.mp3', createdAt: now, updatedAt: now,
      );
      expect(job.progressPercent, 50);
      final restored = DownloadJob.fromJson(job.toJson());
      expect(restored.status, DownloadJobStatus.queued);
      expect(restored.sourceUrl, job.sourceUrl);
      expect(restored.localPath, job.localPath);
      expect(restored.totalBytes, 1024);
      expect(restored.progress, 0.5);
    });

    test('isActive covers queued and downloading only', () {
      expect(_job(status: DownloadJobStatus.queued).isActive, isTrue);
      expect(_job(status: DownloadJobStatus.downloading).isActive, isTrue);
      expect(_job(status: DownloadJobStatus.paused).isActive, isFalse);
      expect(_job(status: DownloadJobStatus.failed).isActive, isFalse);
      expect(_job(status: DownloadJobStatus.completed).isActive, isFalse);
    });

    test('json round-trip preserves fields', () {
      final original = _job(status: DownloadJobStatus.paused, completedAyahs: 10)
          .copyWith(
        downloadedBytes: 12345,
        localPath: '/tmp/file.mp3',
        actualSha256: 'abc',
        attempts: 2,
      );
      final restored = DownloadJob.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.surahNumber, 36);
      expect(restored.status, DownloadJobStatus.paused);
      expect(restored.completedAyahs, 10);
      expect(restored.downloadedBytes, 12345);
      expect(restored.localPath, '/tmp/file.mp3');
      expect(restored.actualSha256, 'abc');
      expect(restored.attempts, 2);
    });

    test('restoring a downloading job re-queues it (resume after restart)', () {
      final json = _job(status: DownloadJobStatus.downloading, completedAyahs: 5).toJson();
      final restored = DownloadJob.fromJson(json);
      expect(restored.status, DownloadJobStatus.queued);
      // موضع الاستئناف محفوظ — لا يُعاد تحميل ما اكتمل.
      expect(restored.completedAyahs, 5);
    });

    test('copyWith updates updatedAt', () {
      final job = _job();
      final updated = job.copyWith(status: DownloadJobStatus.downloading);
      expect(updated.status, DownloadJobStatus.downloading);
      expect(updated.updatedAt.isAfter(job.updatedAt) ||
          updated.updatedAt.isAtSameMomentAs(job.updatedAt), isTrue);
    });
  });

  group('downloadJobStatusLabel', () {
    test('returns Arabic labels for every status', () {
      final labels = DownloadJobStatus.values.map(downloadJobStatusLabel).toList();
      expect(labels.length, DownloadJobStatus.values.length);
      expect(labels.toSet().length, labels.length); // كل حالة لها تسمية مميزة
      expect(downloadJobStatusLabel(DownloadJobStatus.completed), 'مكتمل');
      expect(downloadJobStatusLabel(DownloadJobStatus.failed), 'فشل');
    });
  });
}
