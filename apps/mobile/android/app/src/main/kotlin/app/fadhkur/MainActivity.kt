package app.fadhkur

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.media.MediaMetadataRetriever
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : AudioServiceActivity() {
    private var pendingSound: MethodChannel.Result? = null
    private val soundRequest = 19045

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.fadhkur/reminder_sound")
            .setMethodCallHandler { call, result ->
                if (call.method != "pick") {
                    result.notImplemented()
                } else if (pendingSound != null) {
                    result.error("busy", "اختيار صوت جارٍ", null)
                } else {
                    pendingSound = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/*"
                    }
                    try {
                        startActivityForResult(intent, soundRequest)
                    } catch (error: Exception) {
                        pendingSound = null
                        result.error("picker", "تعذّر فتح ملفات الصوت", null)
                    }
                }
            }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != soundRequest) return
        val result = pendingSound ?: return
        pendingSound = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        var output: File? = null
        try {
            val mime = contentResolver.getType(uri) ?: ""
            val extension = when (mime) {
                "audio/mpeg", "audio/mp3" -> "mp3"
                "audio/mp4", "audio/x-m4a" -> "m4a"
                "audio/aac" -> "aac"
                "audio/ogg" -> "ogg"
                "audio/wav", "audio/x-wav", "audio/wave" -> "wav"
                else -> throw IllegalArgumentException("صيغة الصوت غير مدعومة")
            }
            val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "صوت من الهاتف"
            val directory = File(filesDir, "reminder_sounds").apply { mkdirs() }
            val chosenFile = File(directory, "${UUID.randomUUID()}.$extension")
            output = chosenFile
            var count = 0L
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "تعذّر فتح الصوت" }
                chosenFile.outputStream().use { destination ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        count += read
                        require(count <= 20L * 1024 * 1024) { "الحد الأقصى للصوت 20 ميجابايت" }
                        destination.write(buffer, 0, read)
                    }
                }
            }
            require(count > 0) { "ملف الصوت فارغ" }
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(chosenFile.absolutePath)
                val duration = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                require(duration > 0L) { "ملف الصوت غير قابل للتشغيل" }
            } finally {
                retriever.release()
            }
            val soundUri = Uri.Builder().scheme("content")
                .authority("app.fadhkur.reminder_sounds")
                .appendPath(chosenFile.name).build()
            result.success(mapOf("uri" to soundUri.toString(), "name" to name,
                "bytes" to count))
        } catch (error: Exception) {
            output?.delete()
            result.error("invalid_sound", error.message ?: "ملف صوت غير صالح", null)
        }
    }
}
