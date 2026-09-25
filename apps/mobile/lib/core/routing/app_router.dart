import 'package:flutter/material.dart';

import '../../features/athkar/presentation/athkar_home_screen.dart';
import '../../features/allah_names/presentation/allah_names_screen.dart';
import '../../features/daily_hadith/presentation/daily_hadith_screen.dart';
import '../../features/daily_hadith/presentation/hadith_catalog_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/khatma/presentation/khatma_screen.dart';
import '../../features/learning/presentation/learning_screen.dart';
import '../../features/offline/presentation/downloads_screen.dart';
import '../../features/library/presentation/library_hub_screen.dart';
import '../../features/listen/presentation/listen_hub_screen.dart';
import '../../features/more/presentation/more_hub_screen.dart';
import '../../features/playlists/presentation/playlists_screen.dart';
import '../../features/settings/presentation/about_and_sources_screen.dart';
import '../../features/quran/data/surah_metadata.dart';
import '../../features/prayer/presentation/prayer_times_screen.dart';
import '../../features/quran/presentation/mushaf_reader_screen.dart';
import '../../features/quran/presentation/quran_home_screen.dart';
import '../../features/video/presentation/video_screen.dart';
import '../../features/radio/presentation/radio_screen.dart';
import '../../features/recitations/presentation/recitations_screen.dart';
import '../../features/reminders/presentation/personal_reminders_screen.dart';
import '../../features/shell/presentation/root_shell.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tasbih/presentation/tasbih_screen.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '';

    // روابط الإشعارات العميقة للسور: /quran/surah/[1-114]
    final surahMatch = RegExp(r'^/quran/surah/(\d+)$').firstMatch(name);
    if (surahMatch != null) {
      final surahId = int.tryParse(surahMatch.group(1)!);
      if (surahId != null && surahId >= 1 && surahId <= 114) {
        return _page(
          MushafReaderScreen(initialPage: startPageForSurah(surahId)),
          settings,
        );
      }
    }

    switch (settings.name) {
      case '/':
      case '/home':
        return _page(const RootShell(), settings);
      case '/quran':
        return _page(const QuranHomeScreen(), settings);
      case '/radio':
        return _page(const RadioScreen(), settings);
      case '/video':
        return _page(const VideoScreen(), settings);
      case '/reciters':
        return _page(const RecitationsScreen(), settings);
      case '/listen':
        return _page(const ListenHubScreen(), settings);
      case '/library':
        return _page(const LibraryHubScreen(), settings);
      case '/downloads':
        return _page(const DownloadsScreen(), settings);
      case '/playlists':
        return _page(const PlaylistsScreen(), settings);
      case '/more':
        return _page(const MoreHubScreen(), settings);
      case '/prayer-times':
        return _page(const PrayerTimesScreen(), settings);
      case '/adhkar':
        return _page(const AthkarHomeScreen(), settings);
      case '/custom-reminders':
        return _page(const PersonalRemindersScreen(), settings);
      case '/learning':
        return _page(const LearningScreen(), settings);
      case '/favorites':
        return _page(const FavoritesScreen(), settings);
      case '/tasbih':
        return _page(const TasbihScreen(), settings);
      case '/allah-names':
        return _page(const AllahNamesScreen(), settings);
      case '/settings':
        return _page(const SettingsScreen(), settings);
      case '/about':
        return _page(const AboutAndSourcesScreen(), settings);
      case '/hadith':
        return _page(const HadithCatalogScreen(), settings);
      case '/daily-hadith':
        return _page(const DailyHadithScreen(), settings);
      case '/khatma':
        return _page(const KhatmaScreen(), settings);
      default:
        return _page(const RootShell(), const RouteSettings(name: '/home'));
    }
  }

  /// انتقال ناعم موحّد: تلاشي + انزلاق خفيف باتجاه القراءة.
  ///
  /// في RTL (العربية) تدخل الصفحة الجديدة من اليسار — اتجاه «التقدّم»
  /// الطبيعي — وفي LTR من اليمين. المدة قصيرة (250ms) لتفادي الإحساس
  /// بالبطء، والمنحنى easeOutCubic لنهاية ناعمة.
  static PageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final rtl =
            Directionality.of(context) == TextDirection.rtl;
        final slide = Tween<Offset>(
          begin: Offset(rtl ? -0.08 : 0.08, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    );
  }
}
