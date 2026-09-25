import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/audio_playback_service.dart';
import '../../../core/utils/haptics.dart';

/// خيارات التشغيل المشتركة: مؤقت النوم وسرعة التشغيل.
///
/// تُستخدم في شاشة الراديو وورقة المشغّل الكاملة — المؤقت يعمل لأي
/// مصدر صوتي (راديو/تلاوة/ملف محلي) لأن المشغّل واحد.

const List<int> _sleepOptions = [15, 30, 60];
const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

/// ورقة مؤقت النوم: 15/30/60 دقيقة + إلغاء. تعرض الحالة النشطة إن وجدت.
Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(audioPlaybackProvider.notifier);
  final active = ref.read(audioPlaybackProvider).sleepTimerMinutes;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'مؤقت النوم',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              active == null
                  ? 'سيتوقف التشغيل تلقائيًا بعد المدة المختارة.'
                  : 'المؤقت نشط: سيتوقف التشغيل بعد $active دقيقة.',
              style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          ..._sleepOptions.map(
            (minutes) => ListTile(
              leading: Icon(
                active == minutes
                    ? Icons.check_circle
                    : Icons.timer_outlined,
                color: active == minutes
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text('إيقاف بعد $minutes دقيقة'),
              onTap: () async {
                notifier.setSleepTimer(minutes);
                await AppHaptics.confirm();
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('تم ضبط مؤقت النوم: إيقاف بعد $minutes دقيقة'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
          ListTile(
            leading: Icon(
              active == null ? Icons.check_circle : Icons.timer_off_outlined,
              color: active == null
                  ? Theme.of(ctx).colorScheme.primary
                  : null,
            ),
            title: const Text('إلغاء المؤقت'),
            onTap: () async {
              notifier.setSleepTimer(null);
              await AppHaptics.confirm();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// ورقة سرعة التشغيل — تُطبَّق حيث يدعم المشغّل ذلك (البث الحي قد يتجاهلها).
Future<void> showSpeedSheet(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(audioPlaybackProvider.notifier);
  final current = ref.read(audioPlaybackProvider).speed;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'سرعة التشغيل',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'تُطبَّق حيث يدعمها المشغّل — البث الإذاعي الحي قد يتجاهلها.',
              style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          ..._speedOptions.map(
            (speed) => ListTile(
              leading: Icon(
                current == speed ? Icons.check_circle : Icons.speed_outlined,
                color: current == speed
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(
                speed == 1.0 ? 'طبيعية (1.0x)' : '${speed}x',
              ),
              onTap: () async {
                await notifier.setSpeed(speed);
                await AppHaptics.confirm();
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
