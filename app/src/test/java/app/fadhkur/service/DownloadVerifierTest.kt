package app.fadhkur.service

import org.junit.Assert.*
import org.junit.Test

class DownloadVerifierTest {

    @Test
    fun calculateSha256_returnsValid64CharHex() {
        val testData = "Fadhkur Verified Recitation".toByteArray(Charsets.UTF_8)
        val hash = DownloadVerifier.calculateSha256(testData)
        assertEquals(64, hash.length)
        assertTrue(hash.matches(Regex("^[a-f0-9]{64}$")))
    }

    @Test
    fun generateDeterministicChecksum_producesConsistentHash() {
        val hash1 = DownloadVerifier.generateDeterministicChecksum(18, "الشيخ المنشاوي")
        val hash2 = DownloadVerifier.generateDeterministicChecksum(18, "الشيخ المنشاوي")
        val hash3 = DownloadVerifier.generateDeterministicChecksum(1, "الشيخ المنشاوي")

        assertEquals(hash1, hash2)
        assertNotEquals(hash1, hash3)
        assertEquals(64, hash1.length)
    }
}
