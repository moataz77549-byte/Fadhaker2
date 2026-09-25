import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemoteFeatureFlags {
  final bool radioEnabled;
  final bool offlineDownloadsEnabled;
  final bool prayerTimesEnabled;
  final bool adhkarEnabled;
  final bool learningEnabled;
  final bool announcementsEnabled;
  final bool maintenanceMode;
  final String minSupportedVersion;
  final List<String> homeSectionsOrder;

  const RemoteFeatureFlags({
    this.radioEnabled = true,
    this.offlineDownloadsEnabled = true,
    this.prayerTimesEnabled = true,
    this.adhkarEnabled = true,
    this.learningEnabled = true,
    this.announcementsEnabled = true,
    this.maintenanceMode = false,
    this.minSupportedVersion = '1.0.64',
    this.homeSectionsOrder = const [
      'featured',
      'prayer',
      'memorization',
      'stations',
      'reciters',
      'offline'
    ],
  });

  factory RemoteFeatureFlags.fromJson(Map<String, dynamic> json) {
    return RemoteFeatureFlags(
      radioEnabled: json['radioEnabled'] as bool? ?? true,
      offlineDownloadsEnabled: json['offlineDownloadsEnabled'] as bool? ?? true,
      prayerTimesEnabled: json['prayerTimesEnabled'] as bool? ?? true,
      adhkarEnabled: json['adhkarEnabled'] as bool? ?? true,
      learningEnabled: json['learningEnabled'] as bool? ?? true,
      announcementsEnabled: json['announcementsEnabled'] as bool? ?? true,
      maintenanceMode: json['maintenanceMode'] as bool? ?? false,
      minSupportedVersion: json['minSupportedVersion'] as String? ?? '1.0.64',
      homeSectionsOrder: (json['homeSectionsOrder'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['featured', 'prayer', 'memorization', 'stations', 'reciters', 'offline'],
    );
  }
}

class FeaturesManager extends StateNotifier<RemoteFeatureFlags> {
  FeaturesManager() : super(const RemoteFeatureFlags());

  void updateFlags(RemoteFeatureFlags flags) {
    state = flags;
  }

  void toggleRadio(bool enabled) {
    state = RemoteFeatureFlags(
      radioEnabled: enabled,
      offlineDownloadsEnabled: state.offlineDownloadsEnabled,
      prayerTimesEnabled: state.prayerTimesEnabled,
      adhkarEnabled: state.adhkarEnabled,
      learningEnabled: state.learningEnabled,
      announcementsEnabled: state.announcementsEnabled,
      maintenanceMode: state.maintenanceMode,
      minSupportedVersion: state.minSupportedVersion,
      homeSectionsOrder: state.homeSectionsOrder,
    );
  }
}

final featuresManagerProvider =
    StateNotifierProvider<FeaturesManager, RemoteFeatureFlags>((ref) {
  return FeaturesManager();
});
