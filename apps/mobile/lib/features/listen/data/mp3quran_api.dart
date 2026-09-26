import 'dart:convert';

import 'package:http/http.dart' as http;

/// Official public MP3Quran v3 catalog; no media URLs are embedded in the APK.
/// UI code never calls this class directly.
class Mp3QuranApi {
  Mp3QuranApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const baseUrl = 'https://www.mp3quran.net/api/v3';

  Future<List<Map<String, dynamic>>> reciters() => _list('reciters', 'reciters');
  Future<List<Map<String, dynamic>>> radios() => _list('radios', 'radios');
  Future<List<Map<String, dynamic>>> liveTv() => _list('live-tv', 'livetv');

  Future<List<Map<String, dynamic>>> _list(String path, String key) async {
    final uri = Uri.parse('$baseUrl/$path?language=ar');
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw http.ClientException('Catalog HTTP ${response.statusCode}');
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map || data[key] is! List) throw const FormatException('Malformed MP3Quran catalog');
    return (data[key] as List).whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  void dispose() => _client.close();
}
