import 'package:fadhkur_mobile/core/services/audio_playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// منطق حالة المشغّل — اختبارات Dart خالصة دون منصّة.
///
/// ملاحظة: مسارات `FadhkurAudioNotifier` التي تلمس `just_audio`
/// (كإطلاق المؤقت الفعلي ثم `stop()`) تتطلب قناة منصّة حقيقية،
/// لذا تُختبر يدويًا على جهاز؛ هنا نغطّي منطق الحالة الخالص
/// الذي كان سبب الانحدار السابق.
void main() {
  group('PlaybackState', () {
    test('الحالة الافتراضية بلا مصدر ولا عناوين وهمية', () {
      const state = PlaybackState();
      expect(state.currentUri, isEmpty);
      expect(state.currentTitle, isEmpty);
      expect(state.currentSubtitle, isEmpty);
      expect(state.isPlaying, isFalse);
      expect(state.sleepTimerMinutes, isNull);
      expect(state.speed, 1.0);
    });

    test('copyWith يمسح sleepTimerMinutes عند تمرير null صراحةً', () {
      const state = PlaybackState(sleepTimerMinutes: 15);
      final cleared = state.copyWith(sleepTimerMinutes: null);
      expect(cleared.sleepTimerMinutes, isNull);
    });

    test('copyWith يُبقي sleepTimerMinutes عند عدم تمريره', () {
      const state = PlaybackState(sleepTimerMinutes: 15);
      final kept = state.copyWith(isPlaying: true);
      expect(kept.sleepTimerMinutes, 15);
    });

    test('copyWith يحدّث sleepTimerMinutes بقيمة جديدة', () {
      const state = PlaybackState();
      final updated = state.copyWith(sleepTimerMinutes: 30);
      expect(updated.sleepTimerMinutes, 30);
    });
  });
}
