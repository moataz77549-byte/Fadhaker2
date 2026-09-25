import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TajweedCacheService {
  Future<File> getPage(int page, {String? remoteUrl}) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/tajweed/page_${page.toString().padLeft(3, '0')}.png');
    if (await file.exists() && await file.length() > 0) return file;
    await file.parent.create(recursive: true);
    final url = remoteUrl ?? 'https://raw.githubusercontent.com/quran/quran.com-images/master/ pages/$page.png';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw HttpException('Tajweed page unavailable: ${response.statusCode}');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }
}

final tajweedCacheService = TajweedCacheService();
