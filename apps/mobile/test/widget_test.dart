import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fadhkur_mobile/main.dart';
import 'package:fadhkur_mobile/core/services/app_services.dart';
import 'package:fadhkur_mobile/core/config/features_manager.dart';
import 'package:fadhkur_mobile/core/repositories/fadhkur_repository.dart';
import 'package:fadhkur_mobile/core/models/app_models.dart';

void main() {
  group('Fadhkur Mobile Unit & Widget Tests', () {
    testWidgets('Fadhkur App boots with Arabic title and dynamic navigation shell', (WidgetTester tester) async {
      // تهيئة SharedPreferences وهمية: الشاشة الرئيسية تقرأها في initState،
      // وبدونها يعلّق الـ Future في بيئة الاختبار (لا plugin حقيقي).
      SharedPreferences.setMockInitialValues({});
      // محاكاة قناة geolocator: خدمة الموقع معطّلة في بيئة الاختبار،
      // فيرمي الـ service استثناءً معلوماً وتستقر الواجهة بدل التعليق.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (MethodCall call) async {
          if (call.method == 'isLocationServiceEnabled') return false;
          throw MissingPluginException('لا يوجد plugin في بيئة الاختبار: ${call.method}');
        },
      );
      final mockServices = AppServices(isInitialized: true, activeEnvironment: 'test');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(mockServices),
          ],
          child: const FadhkurApp(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Brand AppBar title
      expect(find.text('فذكر'), findsOneWidget);

      // Verify the simplified five-destination navigation shell.
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(find.text('القرآن'), findsOneWidget);
      expect(find.text('الاستماع'), findsOneWidget);
      expect(find.text('مكتبتي'), findsOneWidget);
      expect(find.text('المزيد'), findsOneWidget);
      expect(find.text('الإذاعة'), findsNothing);
      expect(find.text('القراء'), findsNothing);

      await tester.tap(find.text('القرآن'));
      await tester.pumpAndSettle();
      expect(find.text('ابحث باسم السورة أو رقمها'), findsOneWidget);
      expect(find.text('114 سورة'), findsOneWidget);
      expect(find.text('متابعة القراءة من سورة الكهف'), findsNothing);
    });

    testWidgets('repeated tab navigation keeps inherited widgets attached',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (MethodCall call) async {
          if (call.method == 'isLocationServiceEnabled') return false;
          throw MissingPluginException(call.method);
        },
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            AppServices(isInitialized: true, activeEnvironment: 'test'),
          ),
        ],
        child: const FadhkurApp(),
      ));
      await tester.pumpAndSettle();
      for (var pass = 0; pass < 3; pass++) {
        for (final (index, label) in [
          (1, 'القرآن'),
          (2, 'الاستماع'),
          (3, 'مكتبتي'),
          (4, 'المزيد'),
          (0, 'الرئيسية'),
        ]) {
          final rail = find.byType(NavigationRail);
          final bar = find.byType(NavigationBar);
          expect(rail.evaluate().isNotEmpty || bar.evaluate().isNotEmpty, isTrue,
              reason: 'navigation shell missing at tab $label pass $pass');
          final destination = rail.evaluate().isNotEmpty
              ? find.descendant(of: rail, matching: find.text(label))
              : find.descendant(of: bar, matching: find.text(label));
          expect(destination, findsOneWidget,
              reason: 'destination $index missing at pass $pass');
          await tester.tap(destination);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'tab $label pass $pass');
        }
      }
      await tester.tap(find.byTooltip('البحث'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('FeaturesManager toggles radio feature flag correctly', () {
      final manager = FeaturesManager();
      expect(manager.state.radioEnabled, isTrue);

      manager.toggleRadio(false);
      expect(manager.state.radioEnabled, isFalse);

      manager.toggleRadio(true);
      expect(manager.state.radioEnabled, isTrue);
    });

    test('FavoritesNotifier starts empty and toggles favorite IDs', () {
      final notifier = FavoritesNotifier();
      // لا توجد مفضلة مسبقة وهمية: الحالة الابتدائية فارغة.
      expect(notifier.isFavorite('station-1'), isFalse);

      notifier.toggleFavorite('station-1');
      expect(notifier.isFavorite('station-1'), isTrue);

      notifier.toggleFavorite('station-1');
      expect(notifier.isFavorite('station-1'), isFalse);
    });

    test('PlaylistsNotifier creates and renames playlists', () {
      final notifier = PlaylistsNotifier();
      final initialCount = notifier.state.length;

      notifier.createPlaylist('تلاوات المساء');
      expect(notifier.state.length, initialCount + 1);
      expect(notifier.state.last.name, 'تلاوات المساء');

      final newId = notifier.state.last.id;
      notifier.renamePlaylist(newId, 'تلاوات المساء والوتر');
      expect(notifier.state.last.name, 'تلاوات المساء والوتر');

      notifier.deletePlaylist(newId);
      expect(notifier.state.length, initialCount);
    });

    test('DownloadsNotifier tracks task state and supports pausing', () {
      final notifier = DownloadsNotifier();
      final initialCount = notifier.state.length;

      notifier.addDownload(1, 'سورة الفاتحة', 'الشيخ عبد الباسط');
      expect(notifier.state.length, initialCount + 1);
      final addedTask = notifier.state.last;
      expect(addedTask.status, DownloadStatus.downloading);

      notifier.togglePauseResume(addedTask.id);
      final pausedTask = notifier.state.firstWhere((t) => t.id == addedTask.id);
      expect(pausedTask.status, DownloadStatus.paused);
    });
  });
}
