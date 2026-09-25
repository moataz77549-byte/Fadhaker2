import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/services/app_services.dart';
import '../../../core/services/app_version_service.dart';
import '../../../core/services/local_reminder_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/brand_mark.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _adhkarRemindersKey = 'local_adhkar_reminders_enabled';

  bool _notificationsConsent = false;
  bool _adhkarReminders = false;
  bool _loading = true;
  final _prefsSectionKey =
      GlobalKey<_NotificationPreferencesSectionState>();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notificationsConsent =
          prefs.getBool(NotificationPreferences.consentKey) ?? false;
      _adhkarReminders = prefs.getBool(_adhkarRemindersKey) ?? false;
      _loading = false;
    });
  }

  Future<void> _setAdhkarReminders(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final allowed =
          await localReminderService.requestAndroidNotificationPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم منح إذن الإشعارات على الجهاز.'),
          ),
        );
        return;
      }
      await localReminderService.scheduleMorningEvening();
    } else {
      await localReminderService.cancelMorningEvening();
    }
    await prefs.setBool(_adhkarRemindersKey, enabled);
    if (mounted) setState(() => _adhkarReminders = enabled);
  }

  Future<void> _setCloudConsent(bool enabled) async {
    if (enabled) {
      final ok = await ref
          .read(appServicesProvider)
          .pushService
          .requestConsentAndRegisterDevice(context);
      if (!ok) {
        if (mounted) setState(() => _notificationsConsent = false);
        return;
      }
    } else {
      await ref.read(appServicesProvider).pushService.revokeConsent();
    }
    if (mounted) {
      setState(() => _notificationsConsent = enabled);
      _prefsSectionKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _AppIdentityCard(scheme: scheme),
                const SizedBox(height: 18),
                _SectionTitle('التنبيهات المحلية'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.wb_twilight_rounded),
                        title: const Text('تذكير أذكار الصباح والمساء'),
                        subtitle: const Text(
                          'تنبيهات محلية على الجهاز بدون مشاركة موقعك.',
                        ),
                        value: _adhkarReminders,
                        onChanged: _setAdhkarReminders,
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.mosque_rounded),
                        title: const Text('تنبيهات الأذان ومواقيت الصلاة'),
                        subtitle: const Text(
                          'اختيار طريقة الحساب والصوت والأذان الدقيق.',
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () =>
                            Navigator.of(context).pushNamed('/prayer-times'),
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.alarm_rounded),
                        title: const Text('تذكيرات شخصية'),
                        subtitle: const Text('أنشئ تنبيهاتك الخاصة ومواعيدها.'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () =>
                            Navigator.of(context).pushNamed('/custom-reminders'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('الإشعارات السحابية والخصوصية'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary:
                            const Icon(Icons.notifications_active_rounded),
                        title: const Text('الإشعارات العامة'),
                        subtitle: const Text(
                          'لا يتم تسجيل الجهاز قبل موافقتك الصريحة.',
                        ),
                        value: _notificationsConsent,
                        onChanged: _setCloudConsent,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            _notificationsConsent
                                ? 'يمكنك اختيار أنواع الإشعارات أدناه.'
                                : 'الإشعارات السحابية متوقفة حاليًا.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _NotificationPreferencesSection(key: _prefsSectionKey),
                const SizedBox(height: 18),
                _SectionTitle('التطبيق'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: const Text('المصادر وعن التطبيق'),
                        subtitle: const Text(
                          'المصادر المعتمدة والحقوق وسياسة المحتوى.',
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.of(context).pushNamed('/about'),
                      ),
                      const Divider(indent: 56),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('الخصوصية'),
                        subtitle: const Text(
                          'الموقع للصلاة محليًا، والإشعارات باختيارك.',
                        ),
                        trailing: const Icon(Icons.lock_outline_rounded),
                        onTap: () => Navigator.of(context).pushNamed('/about'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _AppIdentityCard extends StatelessWidget {
  const _AppIdentityCard({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const FadhkurBrandMark(size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    BrandConfig.nameAr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<AppVersion>(
                    future: appVersionService.read(),
                    builder: (context, snapshot) => Text(
                      snapshot.hasData
                          ? 'الإصدار ${snapshot.data!.display}'
                          : 'جارٍ قراءة الإصدار...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _NotificationPreferencesSection extends ConsumerStatefulWidget {
  const _NotificationPreferencesSection({super.key});

  @override
  ConsumerState<_NotificationPreferencesSection> createState() =>
      _NotificationPreferencesSectionState();
}

class _NotificationPreferencesSectionState
    extends ConsumerState<_NotificationPreferencesSection> {
  bool _loading = true;
  bool _consent = false;
  Map<String, bool> _prefs = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final push = ref.read(appServicesProvider).pushService;
    final prefs = await SharedPreferences.getInstance();
    final consent =
        prefs.getBool(NotificationPreferences.consentKey) ?? false;
    final stored = await push.readNotificationPreferences();
    if (!mounted) return;
    setState(() {
      _consent = consent;
      _prefs = stored;
      _loading = false;
    });
  }

  Future<void> _onToggle(String key, bool enabled) async {
    final push = ref.read(appServicesProvider).pushService;
    if (enabled && !_consent) {
      final ok = await push.requestConsentAndRegisterDevice(context);
      if (!ok || !mounted) return;
      await refresh();
    }
    if (!mounted) return;
    setState(() => _prefs[key] = enabled);
    await AppHaptics.confirm();
    await push.setNotificationPreference(key, enabled);
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_consent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'فعّل الإشعارات العامة أولًا، أو فعّل أي نوع وسيظهر طلب الموافقة.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            for (final group in NotificationPreferences.groupsAr.entries) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, bottom: 4),
                child: Text(
                  group.key,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.secondary,
                      ),
                ),
              ),
              for (final key in group.value)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    NotificationPreferences.labelsAr[key] ?? key,
                  ),
                  value: _prefs[key] ?? false,
                  onChanged: (value) => _onToggle(key, value),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
