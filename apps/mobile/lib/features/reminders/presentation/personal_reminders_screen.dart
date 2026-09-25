import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/personal_reminder.dart';
import '../data/personal_reminder_repository.dart';

/// Tier 3: user-managed personal reminders ("ورد يومي").
class PersonalRemindersScreen extends ConsumerWidget {
  const PersonalRemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(personalRemindersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('تذكيرات شخصية')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('تذكير جديد'),
      ),
      body: remindersAsync.when(
        loading: () => const Center(child: Text('جارٍ تحميل التذكيرات...')),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذّر تحميل التذكيرات: $error'),
          ),
        ),
        data: (reminders) {
          if (reminders.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد تذكيرات بعد.\nأضف وردك اليومي ليصلك في وقته بدقة.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: reminders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final reminder = reminders[index];
              return Card(
                child: ListTile(
                  title: Text(reminder.title),
                  subtitle: Text(
                    '${reminder.timeLabel} • ${reminder.repeatLabel} • ${reminder.sound.titleAr}',
                  ),
                  leading: Switch(
                    value: reminder.enabled,
                    onChanged: (value) async {
                      await ref
                          .read(personalReminderRepositoryProvider)
                          .save(reminder.copyWith(enabled: value));
                      ref.invalidate(personalRemindersProvider);
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'حذف',
                    onPressed: () async {
                      await ref
                          .read(personalReminderRepositoryProvider)
                          .delete(reminder);
                      ref.invalidate(personalRemindersProvider);
                    },
                  ),
                  onTap: () => _openEditor(context, ref, reminder),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    PersonalReminder? existing,
  ) async {
    final result = await showModalBottomSheet<PersonalReminder>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReminderEditor(initial: existing),
    );
    if (result == null) return;
    await ref.read(personalReminderRepositoryProvider).save(result);
    ref.invalidate(personalRemindersProvider);
  }
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({this.initial});

  final PersonalReminder? initial;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.initial?.title ?? '');
  late TimeOfDay _time = TimeOfDay(
    hour: widget.initial?.hour ?? 6,
    minute: widget.initial?.minute ?? 0,
  );
  late Set<int> _weekdays = {...?widget.initial?.weekdays};
  late ReminderSound _sound = widget.initial?.sound ?? ReminderSound.soft;

  static const _dayLabels = {
    7: 'الأحد',
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
  };

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'تذكير جديد' : 'تعديل التذكير',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'العنوان',
                hintText: 'مثال: ورد القرآن اليومي',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('الوقت'),
              subtitle: Text(_time.format(context)),
              onTap: () async {
                final picked =
                    await showTimePicker(context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('التكرار (اتركه فارغًا ليكون يوميًا)'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _dayLabels.entries.map((entry) {
                final selected = _weekdays.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _weekdays.add(entry.key);
                    } else {
                      _weekdays.remove(entry.key);
                    }
                  }),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReminderSound>(
              initialValue: _sound,
              decoration: const InputDecoration(labelText: 'الصوت'),
              items: ReminderSound.values
                  .map(
                    (sound) => DropdownMenuItem(
                      value: sound,
                      child: Text(sound.titleAr),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _sound = value ?? ReminderSound.soft),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final title = _titleController.text.trim();
                Navigator.of(context).pop(
                  PersonalReminder(
                    id: widget.initial?.id ?? 0,
                    title: title.isEmpty ? 'تذكير' : title,
                    hour: _time.hour,
                    minute: _time.minute,
                    weekdays: _weekdays,
                    sound: _sound,
                    enabled: widget.initial?.enabled ?? true,
                  ),
                );
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
