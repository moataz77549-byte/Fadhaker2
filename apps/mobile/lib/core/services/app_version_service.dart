import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  final String name;
  final String code;
  const AppVersion({required this.name, required this.code});

  String get display => '$name+$code';
}

class AppVersionService {
  Future<AppVersion> read() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(name: info.version, code: info.buildNumber);
  }
}

final appVersionService = AppVersionService();
