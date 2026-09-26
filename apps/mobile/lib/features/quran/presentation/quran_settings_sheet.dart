import 'package:flutter/material.dart';
import '../data/quran_font_loader.dart';
import '../data/quran_reading_state_repository.dart';
import '../domain/mushaf_edition.dart';
import '../domain/quran_font.dart';
import '../domain/riwaya.dart';

/// ورقة إعدادات المصحف: الرواية، نسخة المصحف المصوّر، الخط، حجم الخط، ووضع القراءة.
/// تُحفظ كل الخيارات محليًا عبر [QuranReadingStateRepository].
class QuranSettingsSheet extends StatefulWidget {
  const QuranSettingsSheet({
    super.key,
    required this.riwayat,
    required this.editions,
    required this.fonts,
    required this.stateRepository,
    required this.onChanged,
  });

  final List<Riwaya> riwayat;
  final List<MushafEdition> editions;
  final List<QuranFontOption> fonts;
  final QuranReadingStateRepository stateRepository;
  final VoidCallback onChanged;

  @override
  State<QuranSettingsSheet> createState() => _QuranSettingsSheetState();
}

class _QuranSettingsSheetState extends State<QuranSettingsSheet> {
  late Future<_SettingsValues> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SettingsValues> _load() async {
    final repo = widget.stateRepository;
    final riwayaId = await repo.riwayaId();
    final fontId = await repo.fontId();
    final font = QuranFontRegistry.byId(fontId, widget.fonts);
    return _SettingsValues(
      riwayaId: riwayaId,
      editionId: await repo.mushafEditionId(),
      fontId: font.id,
      fontSize: await repo.fontSize(),
      mode: await repo.readingMode(),
      loadedFontFamily: await QuranFontLoader.ensureLoaded(font),
    );
  }

  Future<void> _update(Future<void> Function() save) async {
    await save();
    widget.onChanged();
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<_SettingsValues>(
        future: _future,
        builder: (context, snapshot) {
          final values = snapshot.data;
          if (values == null) {
            return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
          }
          final riwaya = RiwayaRegistry.byId(values.riwayaId, widget.riwayat);
          // الرواية تؤثر فعليًا على الخط: تُعرض فقط الخطوط الداعمة لها،
          // ويُستخدم أفضل خط داعم كمعاينة واختيار فعلي.
          final supportedFonts =
              widget.fonts.where((f) => f.supportsRiwaya(riwaya.id)).toList();
          final font = QuranFontRegistry.bestForRiwaya(riwaya.id, widget.fonts);
          // إصدارات المصحف المصوّر المتاحة لهذه الرواية (عادي/تجويد ملوّن).
          final riwayaEditions =
              widget.editions.where((e) => e.riwayaId == riwaya.id).toList();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('إعدادات المصحف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                const Text('الرواية', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: widget.riwayat.map((r) => ChoiceChip(
                    label: Text(r.nameAr),
                    selected: r.id == values.riwayaId,
                    onSelected: (_) => _update(() => widget.stateRepository.saveRiwayaId(r.id)),
                  )).toList(),
                ),
                if (riwayaEditions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'المصحف المصوّر غير متوفّر لرواية «${riwaya.nameAr}» بعد — لا توجد نسخة مصحف موثّقة بتخطيط 604 صفحات.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (riwayaEditions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('نسخة المصحف', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: riwayaEditions.map((e) => ChoiceChip(
                      label: Text(e.nameAr),
                      selected: e.id == values.editionId,
                      onSelected: (_) => _update(() => widget.stateRepository.saveMushafEditionId(e.id)),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('وضع القراءة', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final option in const [
                    (QuranReadingMode.image, 'المدينة'),
                    (QuranReadingMode.tajweed, 'التجويد'),
                    (QuranReadingMode.thematic, 'موضوعي'),
                    (QuranReadingMode.text, 'نص'),
                  ]) ChoiceChip(
                    label: Text(option.$2),
                    selected: values.mode == option.$1,
                    onSelected: (_) => _update(() => widget.stateRepository.saveReadingMode(option.$1)),
                  ),
                ],
                ),
                const SizedBox(height: 16),
                const Text('الخط', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (supportedFonts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'لا توجد خطوط موثّقة لرواية «${riwaya.nameAr}» بعد — يُستخدم خط النظام.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                RadioGroup<String>(
                  groupValue: font.id,
                  onChanged: (v) => _update(() => widget.stateRepository.saveFontId(v ?? 'uthmanic-hafs')),
                  child: Column(
                    children: supportedFonts.map((f) => RadioListTile<String>(
                      title: Text(f.nameAr),
                      subtitle: Text(
                        [
                          if (f.licenseNoteAr.isNotEmpty) f.licenseNoteAr,
                          if (!f.hasDownload) 'لا يوجد ملف تحميل موثّق — يُستخدم خط النظام.',
                        ].join('\n'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: f.id,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('حجم الخط', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${values.fontSize.round()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: values.fontSize, min: 16, max: 40, divisions: 24,
                  label: '${values.fontSize.round()}',
                  onChanged: (v) => setState(() {
                    _future = _future.then((old) => _SettingsValues(
                      riwayaId: old.riwayaId, editionId: old.editionId, fontId: old.fontId, fontSize: v, mode: old.mode,
                      loadedFontFamily: old.loadedFontFamily,
                    ));
                  }),
                  onChangeEnd: (v) => _update(() => widget.stateRepository.saveFontSize(v)),
                ),
                const SizedBox(height: 4),
                Text(
                  'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    // null = الخط لم يُحمَّل بعد فيُستخدم خط النظام.
                    fontFamily: values.loadedFontFamily,
                    fontSize: values.fontSize,
                    height: font.lineHeight,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ملاحظة: تُحمَّل ملفات الخطوط عند أول استخدام من مصادرها الموثّقة وتُخزَّن على الجهاز؛ وعند تعذّر التحميل يُستخدم خط النظام تلقائيًا.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SettingsValues {
  const _SettingsValues({
    required this.riwayaId,
    required this.editionId,
    required this.fontId,
    required this.fontSize,
    required this.mode,
    required this.loadedFontFamily,
  });
  final String riwayaId;
  final String editionId;
  final String fontId;
  final double fontSize;
  final QuranReadingMode mode;

  /// اسم عائلة الخط بعد تحميله؛ null = خط النظام.
  final String? loadedFontFamily;
}
