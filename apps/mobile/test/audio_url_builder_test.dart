import 'package:fadhkur_mobile/features/listen/data/audio_url_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recitation URLs require a real MP3Quran subdomain and listed surah', () {
    expect(AudioUrlBuilder.forMp3Quran(
      'https://server.mp3quran.net/reader/', 1, {1})?.toString(),
      'https://server.mp3quran.net/reader/001.mp3');
    expect(AudioUrlBuilder.forMp3Quran(
      'https://evilmp3quran.net/reader/', 1, {1}), isNull);
    expect(AudioUrlBuilder.forMp3Quran(
      'https://server.mp3quran.net/reader/', 2, {1}), isNull);
  });
}
