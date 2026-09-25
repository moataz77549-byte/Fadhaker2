package app.fadhkur.model

import org.junit.Assert.*
import org.junit.Test

class QuranDataTest {

    @Test
    fun quranSurahs_hasExactly114Surahs() {
        assertEquals(114, QuranData.surahs.size)
    }

    @Test
    fun quranSurahs_firstAndLastSurahAreCorrect() {
        val first = QuranData.surahs.first()
        assertEquals(1, first.number)
        assertEquals("الفاتحة", first.nameAr)
        assertEquals(1, first.page)
        assertEquals(7, first.versesCount)

        val last = QuranData.surahs.last()
        assertEquals(114, last.number)
        assertEquals("الناس", last.nameAr)
        assertEquals(604, last.page)
        assertEquals(6, last.versesCount)
    }

    @Test
    fun quranSurahs_allPagesWithinValidRange() {
        QuranData.surahs.forEach { surah ->
            assertTrue("Surah ${surah.number} page ${surah.page} must be between 1 and 604", surah.page in 1..604)
            assertTrue("Surah ${surah.number} juz ${surah.juz} must be between 1 and 30", surah.juz in 1..30)
            assertTrue("Surah ${surah.number} versesCount must be positive", surah.versesCount > 0)
        }
    }

    @Test
    fun searchSurahs_findsCorrectResults() {
        val kahfResults = QuranData.searchSurahs("الكهف")
        assertEquals(1, kahfResults.size)
        assertEquals(18, kahfResults.first().number)

        val englishResults = QuranData.searchSurahs("Ibrahim")
        assertEquals(1, englishResults.size)
        assertEquals(14, englishResults.first().number)

        val numberResults = QuranData.searchSurahs("36")
        assertEquals(1, numberResults.size)
        assertEquals("يس", numberResults.first().nameAr)
    }
}
