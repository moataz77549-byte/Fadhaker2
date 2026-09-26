import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/audio_playback_service.dart';
import '../../../core/services/quran_download_service.dart';
import '../../quran/data/surah_metadata.dart';

/// شاشة التنزيلات — تعرض مهام [QuranDownloadManager] مباشرة:
/// طابور، إيقاف مؤقت، استئناف، إعادة محاولة، تقدّم، إلغاء، حذف،
/// مع استعادة المهام تلقائيًا بعد إعادة تشغيل التطبيق.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Future<void> _startDownload() async {
    var selectedSurah = allSurahs.first;
    var reciterPath = 'Alafasy_64kbps';
    final selection = await showDialog<(int, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('تنزيل تلاوة سورة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: selectedSurah.number,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'السورة'),
              items: allSurahs.map((s) => DropdownMenuItem(
                value: s.number, child: Text(s.displayName),
              )).toList(),
              onChanged: (number) => update(() {
                selectedSurah = allSurahs[number! - 1];
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: reciterPath,
              decoration: const InputDecoration(labelText: 'القارئ'),
              items: const [
                DropdownMenuItem(value: 'Alafasy_64kbps', child: Text('مشاري العفاسي')),
                DropdownMenuItem(value: 'Alafasy_128kbps', child: Text('مشاري العفاسي — جودة أعلى')),
              ],
              onChanged: (path) => update(() => reciterPath = path!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (selectedSurah.number, reciterPath)),
              child: const Text('بدء التنزيل'),
            ),
          ],
        ),
      ),
    );
    if (selection == null) return;
    final surah = allSurahs[selection.$1 - 1];
    try {
      await quranDownloadManager.enqueueRange(
        surahNumber: surah.number,
        surahNameAr: surah.displayName,
        reciterNameAr: 'مشاري العفاسي',
        reciterPath: selection.$2,
        firstAyah: 1,
        lastAyah: surah.ayahs,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر بدء التنزيل: $error')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // استعادة المهام المحفوظة (تُستأنف المهام المتوقفة في الطابور).
    quranDownloadManager.init();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(length: 2, child: Scaffold(
      appBar: AppBar(
        title: const Text('التنزيلات والاستماع دون اتصال'),
        actions: [IconButton(
          tooltip: 'تنزيل سورة',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _startDownload,
        )],
        bottom: const TabBar(tabs: [
          Tab(text: 'تنزيلات القرآن'),
          Tab(text: 'المصاحف الصوتية'),
        ]),
      ),
      body: TabBarView(children: [StreamBuilder<List<DownloadJob>>(
        stream: quranDownloadManager.jobsStream,
        initialData: quranDownloadManager.jobs,
        builder: (context, snapshot) {
          final jobs = snapshot.data ?? const <DownloadJob>[];
          if (jobs.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.download_for_offline_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text('لا توجد ملفات محملة حالياً',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('اختر سورة وقارئًا للتنزيل والاستماع دون اتصال.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _startDownload,
                    icon: const Icon(Icons.download), label: const Text('تنزيل سورة')),
                ]),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: jobs.length,
            itemBuilder: (ctx, i) => _JobCard(job: jobs[i]),
          );
        },
      ), const _DownloadedRecitationsTab()]),
    ));
  }
}

class _DownloadedRecitationsTab extends ConsumerStatefulWidget {
  const _DownloadedRecitationsTab();

  @override
  ConsumerState<_DownloadedRecitationsTab> createState() => _DownloadedRecitationsTabState();
}

class _DownloadedRecitationsTabState extends ConsumerState<_DownloadedRecitationsTab> {
  late Future<List<File>> _files = _scan();

  Future<List<File>> _scan() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/quran/recitations');
    if (!await directory.exists()) return const [];
    final result = <File>[];
    await for (final entry in directory.list(recursive: true, followLinks: false)) {
      if (entry is File && entry.path.endsWith('.mp3') && await entry.length() > 0) {
        result.add(entry);
      }
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<File>>(
    future: _files,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: TextButton(
          onPressed: () => setState(() => _files = _scan()),
          child: const Text('تعذّر فتح الملفات. إعادة المحاولة'),
        ));
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final files = snapshot.data!;
      if (files.isEmpty) return const Center(child: Text('لا توجد تلاوات محملة بعد.'));
      return ListView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final match = RegExp(r'surah_(\d{3})\.mp3$').firstMatch(file.path);
          final number = int.tryParse(match?.group(1) ?? '') ?? 0;
          final surahName = number >= 1 && number <= allSurahs.length
              ? allSurahs[number - 1].displayName : 'سورة $number';
          final folder = file.parent.path.split(Platform.pathSeparator).last;
          return ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(surahName),
            subtitle: Text('مصحف $folder • محفوظ على الجهاز'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'تشغيل دون اتصال', icon: const Icon(Icons.play_arrow),
                onPressed: () => ref.read(audioPlaybackProvider.notifier)
                    .playOfflineTrack(surahName, folder, file.path),
              ),
              IconButton(
                tooltip: 'حذف من الجهاز', icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await file.delete();
                  if (mounted) setState(() => _files = _scan());
                },
              ),
            ]),
          );
        },
      );
    },
  );
}

class _JobCard extends ConsumerWidget {
  final DownloadJob job;
  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioNotifier = ref.read(audioPlaybackProvider.notifier);
    final isCompleted = job.status == DownloadJobStatus.completed;
    final isActive = job.status == DownloadJobStatus.downloading ||
        job.status == DownloadJobStatus.queued;
    final isPaused = job.status == DownloadJobStatus.paused;
    final isFailed = job.status == DownloadJobStatus.failed;

    final statusColor = isCompleted
        ? const Color(0xFF2E9E9E)
        : isFailed
            ? Colors.red
            : isPaused
                ? const Color(0xFF5B677A)
                : const Color(0xFFC77955);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    job.surahNameAr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCompleted && (job.expectedSha256?.isNotEmpty ?? false)
                        ? 'مكتمل وموثق (SHA-256)'
                        : isCompleted && (job.actualSha256?.isNotEmpty ?? false)
                            ? 'مكتمل • SHA-256 محسوب'
                            : downloadJobStatusLabel(job.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              job.reciterNameAr,
              style: const TextStyle(color: Color(0xFF5B677A), fontSize: 13),
            ),
            if (isFailed && (job.errorMessage?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              Text(
                job.errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            if (!isCompleted) ...[
              LinearProgressIndicator(
                value: job.progress,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                color: const Color(0xFF2E9E9E),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${job.progressPercent}% • ${job.completedAyahs}/${job.totalAyahs} آية',
                    style: const TextStyle(color: Color(0xFF5B677A), fontSize: 12),
                  ),
                  Row(
                    children: [
                      if (isActive)
                        IconButton(
                          icon: const Icon(Icons.pause_circle_outline,
                              color: Color(0xFF243B6B)),
                          tooltip: 'إيقاف مؤقت',
                          onPressed: () => quranDownloadManager.pause(job.id),
                        ),
                      if (isPaused)
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline,
                              color: Color(0xFF2E9E9E)),
                          tooltip: 'استئناف',
                          onPressed: () => quranDownloadManager.resume(job.id),
                        ),
                      if (isFailed)
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFFC77955)),
                          tooltip: 'إعادة المحاولة',
                          onPressed: () => quranDownloadManager.retry(job.id),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: 'إلغاء المهمة',
                        onPressed: () => _confirm(
                          context,
                          'إلغاء مهمة التحميل؟',
                          () => quranDownloadManager.cancel(job.id),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الحجم: ${(job.downloadedBytes / 1000000).toStringAsFixed(1)} MB • تخزين محلي',
                    style: const TextStyle(color: Color(0xFF5B677A), fontSize: 12),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow,
                            color: Color(0xFF2E9E9E), size: 28),
                        tooltip: 'تشغيل من الملف المحلي',
                        onPressed: (job.localPath?.isNotEmpty ?? false)
                            ? () => audioNotifier.playOfflineTrack(
                                  job.surahNameAr,
                                  job.reciterNameAr,
                                  job.localPath!,
                                )
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'حذف من الجهاز',
                        onPressed: () => _confirm(
                          context,
                          'حذف الملف المحمل من الجهاز؟',
                          () => quranDownloadManager.delete(job.id),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(
      BuildContext context, String message, VoidCallback onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}
