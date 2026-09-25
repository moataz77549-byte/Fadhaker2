import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'video_channel_repository.dart';

/// مزوّد قنوات الفيديو من Supabase (app.video_channels).
/// القائمة الفارغة حالة طبيعية — تُعرض empty state دون بيانات تجريبية.
final videoChannelsProvider = FutureProvider<VideoCatalogResult>((ref) async {
  return videoChannelRepository.loadResult();
});
