package app.svara

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result? = null
    private val permission: String get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
    private fun allowed() = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.svara/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(allowed())
                "requestPermission" -> if (allowed()) result.success(true) else if (pendingPermission != null) result.success(false) else {
                    pendingPermission = result
                    requestPermissions(arrayOf(permission), 70)
                }
                "openSettings" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                "openUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url"))
                    if (uri.scheme == "https" && uri.host in setOf("audius.co", "audius.org", "www.youtube.com", "youtube.com", "policies.google.com")) {
                        try { startActivity(Intent(Intent.ACTION_VIEW, uri)); result.success(null) }
                        catch (e: Exception) { result.error("browser", "No browser available.", null) }
                    } else result.error("url", "Unsupported URL", null)
                }
                "scan" -> {
                    if (!allowed()) result.error("permission", "Music permission is required.", null)
                    else worker.execute {
                        try {
                            val known = call.argument<Map<String, Number>>("known") ?: emptyMap()
                            val answer = scan(known, call.argument<String>("version"))
                            runOnUiThread { result.success(answer) }
                        } catch (e: Exception) { runOnUiThread { result.error("scan", e.message, null) } }
                    }
                }
                "artwork" -> worker.execute {
                    var bytes: ByteArray? = null
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(this, Uri.parse(call.argument<String>("uri")))
                        val embedded = retriever.embeddedPicture
                        if (embedded != null) {
                            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeByteArray(embedded, 0, embedded.size, bounds)
                            val opts = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 256) }
                            val bitmap = BitmapFactory.decodeByteArray(embedded, 0, embedded.size, opts)
                            if (bitmap != null) {
                                val out = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                                bytes = out.toByteArray(); bitmap.recycle()
                            }
                        }
                    } catch (_: Exception) { } finally { retriever.release() }
                    runOnUiThread { result.success(bytes) }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun scan(known: Map<String, Number>, previousVersion: String?): Map<String, Any> {
        val volumes = if (Build.VERSION.SDK_INT >= 29) MediaStore.getExternalVolumeNames(this) else setOf("external")
        val version = if (Build.VERSION.SDK_INT >= 30) volumes.sorted().joinToString(";") { "$it:${MediaStore.getVersion(this, it)}:${MediaStore.getGeneration(this, it)}" } else null
        if (version != null && version == previousVersion) return mapOf("unchanged" to true)
        val changed = mutableListOf<Map<String, Any?>>()
        val ids = mutableListOf<String>()
        val projection = mutableListOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_MODIFIED, MediaStore.Audio.Media.SIZE)
        if (Build.VERSION.SDK_INT >= 30) projection.add(MediaStore.MediaColumns.GENERATION_MODIFIED)
        if (Build.VERSION.SDK_INT >= 29) projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
        else projection.add(MediaStore.Audio.Media.DATA)
        for (volume in volumes) {
            val base = MediaStore.Audio.Media.getContentUri(volume)
            contentResolver.query(base, projection.toTypedArray(), "${MediaStore.Audio.Media.SIZE} > 0", null, "${MediaStore.Audio.Media._ID} ASC")?.use { cursor ->
                fun string(column: String) = cursor.getString(cursor.getColumnIndexOrThrow(column)) ?: ""
                fun number(column: String) = cursor.getLong(cursor.getColumnIndexOrThrow(column))
                while (cursor.moveToNext()) {
                    val mediaId = number(MediaStore.Audio.Media._ID)
                    val id = "local:$volume:$mediaId"
                    ids.add(id)
                    val folder = if (Build.VERSION.SDK_INT >= 29) string(MediaStore.Audio.Media.RELATIVE_PATH) else string(MediaStore.Audio.Media.DATA).substringBeforeLast('/', "")
                    // Generation catches metadata-only edits on API 30+. Older devices
                    // include path/title metadata so rename does not depend on file mtime.
                    val modified = if (Build.VERSION.SDK_INT >= 30) number(MediaStore.MediaColumns.GENERATION_MODIFIED)
                        else number(MediaStore.Audio.Media.DATE_MODIFIED) * 1000003L + number(MediaStore.Audio.Media.SIZE) +
                            (folder + string(MediaStore.Audio.Media.TITLE) + string(MediaStore.Audio.Media.ARTIST) + string(MediaStore.Audio.Media.ALBUM)).hashCode().toLong()
                    if (known[id]?.toLong() == modified) continue
                    val uri = ContentUris.withAppendedId(base, mediaId).toString()
                    changed.add(mapOf("id" to id, "title" to string(MediaStore.Audio.Media.TITLE),
                        "artist" to string(MediaStore.Audio.Media.ARTIST), "album" to string(MediaStore.Audio.Media.ALBUM),
                        "durationMs" to number(MediaStore.Audio.Media.DURATION), "folder" to folder,
                        "uri" to uri, "modified" to modified, "online" to false))
                }
            }
        }
        return buildMap { put("changed", changed); put("ids", ids); if (version != null) put("version", version) }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 70) { pendingPermission?.success(allowed()); pendingPermission = null }
    }
}
