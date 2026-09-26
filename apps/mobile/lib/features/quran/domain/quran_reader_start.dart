import 'quran_location.dart';

/// Resolves an incoming navigation target before restoring reading progress.
class QuranReaderStart {
  const QuranReaderStart(this.pageNumber, this.verseKey);

  final int pageNumber;
  final String? verseKey;

  static QuranReaderStart resolve({
    int? requestedPage,
    String? requestedVerseKey,
    QuranLocation? savedLocation,
    int? savedPage,
  }) {
    final page = (requestedPage ?? savedLocation?.pageNumber ?? savedPage ?? 293)
        .clamp(1, 604)
        .toInt();
    return QuranReaderStart(
      page,
      requestedPage != null
          ? requestedVerseKey
          : savedLocation?.pageNumber == page ? savedLocation?.verseKey : null,
    );
  }
}
