import 'package:flutter_test/flutter_test.dart';
import 'package:fadhkur_mobile/features/video/video_channel.dart';

void main() {
  group('videoSourceTypeFromUrl', () {
    test('detects HLS playlists', () {
      expect(
        videoSourceTypeFromUrl('http://m.live.net.sa:1935/live/quran/playlist.m3u8'),
        VideoSourceType.hls,
      );
      expect(
        videoSourceTypeFromUrl('https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/index.m3u8'),
        VideoSourceType.hls,
      );
    });

    test('detects YouTube links', () {
      expect(
        videoSourceTypeFromUrl('https://www.youtube.com/watch?v=ATMosZ7Xq1c'),
        VideoSourceType.youtube,
      );
      expect(videoSourceTypeFromUrl('https://youtu.be/ATMosZ7Xq1c'), VideoSourceType.youtube);
    });

    test('detects mp4 files', () {
      expect(videoSourceTypeFromUrl('https://example.com/video.mp4'), VideoSourceType.mp4);
    });

    test('returns unknown for empty or unrecognized urls', () {
      expect(videoSourceTypeFromUrl(''), VideoSourceType.unknown);
      expect(videoSourceTypeFromUrl('https://example.com/stream'), VideoSourceType.unknown);
    });
  });

  group('youtubeVideoIdFromUrl', () {
    test('extracts id from watch urls', () {
      expect(youtubeVideoIdFromUrl('https://www.youtube.com/watch?v=ATMosZ7Xq1c'),
          'ATMosZ7Xq1c');
    });

    test('extracts id with extra query params', () {
      expect(
        youtubeVideoIdFromUrl('https://www.youtube.com/watch?v=ATMosZ7Xq1c&t=120s'),
        'ATMosZ7Xq1c',
      );
    });

    test('extracts id from short, embed, shorts and live urls', () {
      expect(youtubeVideoIdFromUrl('https://youtu.be/ATMosZ7Xq1c'), 'ATMosZ7Xq1c');
      expect(youtubeVideoIdFromUrl('https://www.youtube.com/embed/ATMosZ7Xq1c'),
          'ATMosZ7Xq1c');
      expect(youtubeVideoIdFromUrl('https://www.youtube.com/shorts/ATMosZ7Xq1c'),
          'ATMosZ7Xq1c');
      expect(
          youtubeVideoIdFromUrl('https://www.youtube.com/live/ATMosZ7Xq1c'),
          'ATMosZ7Xq1c');
    });

    test('preserves id letter casing', () {
      expect(youtubeVideoIdFromUrl('https://youtu.be/AbC123xYz_-Q'), 'AbC123xYz_-Q');
    });

    test('returns null for non-youtube urls', () {
      expect(youtubeVideoIdFromUrl('https://example.com/index.m3u8'), isNull);
      expect(youtubeVideoIdFromUrl(''), isNull);
    });
  });

  group('VideoChannel.fromSupabase', () {
    test('parses a row and derives the source type', () {
      final channel = VideoChannel.fromSupabase({
        'id': 'ch-1',
        'name_ar': 'قناة القرآن',
        'stream_url': 'https://example.com/live/index.m3u8',
        'logo_url': 'https://example.com/logo.png',
        'is_active': true,
        'sort_order': 10,
      });
      expect(channel.nameAr, 'قناة القرآن');
      expect(channel.sourceType, VideoSourceType.hls);
      expect(channel.youtubeVideoId, isNull);
      expect(channel.isActive, isTrue);
      expect(channel.sortOrder, 10);
    });

    test('youtube channels expose the video id', () {
      final channel = VideoChannel.fromSupabase({
        'id': 'ch-2',
        'name_ar': 'قناة السنة',
        'stream_url': 'https://www.youtube.com/watch?v=ATMosZ7Xq1c',
      });
      expect(channel.sourceType, VideoSourceType.youtube);
      expect(channel.youtubeVideoId, 'ATMosZ7Xq1c');
    });

    test('json round-trip preserves fields', () {
      const original = VideoChannel(
        id: 'ch-3',
        nameAr: 'قناة',
        streamUrl: 'https://example.com/v.mp4',
        sourceType: VideoSourceType.mp4,
        sortOrder: 7,
      );
      final restored = VideoChannel.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.sourceType, VideoSourceType.mp4);
      expect(restored.sortOrder, 7);
    });
  });
}
