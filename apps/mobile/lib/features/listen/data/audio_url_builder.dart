/// MP3Quran's documented moshaf server hosts zero-padded surah MP3 files.
/// Only numbers declared by that moshaf's `surah_list` may be requested.
class AudioUrlBuilder {
  static Set<int> availableSurahs(String? list) => (list ?? '')
      .split(',')
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .where((number) => number >= 1 && number <= 114)
      .toSet();

  static Uri? forMp3Quran(String server, int surah, Set<int> available) {
    if (!available.contains(surah) || surah < 1 || surah > 114) return null;
    final base = Uri.tryParse(server.trim());
    if (base == null || base.scheme != 'https' ||
        !(base.host == 'mp3quran.net' || base.host.endsWith('.mp3quran.net'))) {
      return null;
    }
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$path${surah.toString().padLeft(3, '0')}.mp3');
  }
}
