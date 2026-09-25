import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

class ContentSyncService {
  Future<List<Map<String, dynamic>>> loadCollection(String table, {int limit = 100}) async {
    final cacheKey = 'fadhkur.sync.$table';
    try {
      if (!SupabaseConfig.isConfigured) throw StateError('Supabase is not configured');
      final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table?select=*&limit=$limit');
      final response = await http.get(uri, headers: {
        'apikey': SupabaseConfig.publishableKey,
        'Accept-Profile': 'app',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cacheKey, jsonEncode(decoded));
          return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);
    if (cached == null) return [];
    try {
      final decoded = jsonDecode(cached);
      return decoded is List ? decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    } catch (_) { return []; }
  }
}

final contentSyncService = ContentSyncService();
