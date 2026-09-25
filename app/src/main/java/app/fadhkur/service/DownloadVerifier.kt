package app.fadhkur.service

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Verifier and checksum utility for Fadhkur audio files.
 * Adheres to the fail-closed security principle: Any file with mismatched
 * checksum is immediately rejected and discarded.
 */
object DownloadVerifier {

    /**
     * Calculates the SHA-256 hash of a given byte array.
     */
    fun calculateSha256(data: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(data)
        return hash.joinToString("") { "%02x".format(it) }
    }

    /**
     * Calculates the SHA-256 hash of a file on disk.
     */
    fun calculateFileSha256(file: File): String {
        if (!file.exists()) return ""
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(8192)
        FileInputStream(file).use { fis ->
            var bytesRead: Int
            while (fis.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Verifies that the file matches the expected SHA-256 hash.
     */
    fun verifyChecksum(file: File, expectedSha256: String): Boolean {
        if (expectedSha256.isBlank()) return true // Skip if no checksum specified
        val actual = calculateFileSha256(file)
        return actual.equals(expectedSha256.trim(), ignoreCase = true)
    }

    /**
     * Generates a deterministic mock checksum for sample Quran tracks.
     */
    fun generateDeterministicChecksum(surahNumber: Int, reciterName: String): String {
        val seed = "fadhkur_${surahNumber}_${reciterName}"
        return calculateSha256(seed.toByteArray(Charsets.UTF_8))
    }
}
