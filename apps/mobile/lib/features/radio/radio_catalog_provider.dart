import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/radio_catalog_service.dart';
import 'radio_station.dart';

/// مزوّد كتالوج المحطات: محطات Supabase الإنتاجية أولًا ثم المضمّنة.
/// لا يرمي أبدًا — القائمة الفارغة مستحيلة عمليًا (المضمّنة دائمًا موجودة)
/// وأي حالة شاذة تُعالج كـ empty state صادق في الواجهة.
final radioStationsProvider = FutureProvider<List<RadioStation>>((ref) async {
  return radioCatalogService.load();
});
