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
import android.provider.DocumentsContract
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingLyrics: MethodChannel.Result? = null
    private var pendingLyricsFolder: String? = null
    private val lyricsPreferences by lazy { getSharedPreferences("lyrics_folders", MODE_PRIVATE) }
    private var pendingPermission: MethodChannel.Result? = null
    private val permission: String get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE
    private fun allowed() = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.svara/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseLyricsFolder" -> {
                    if (pendingLyrics != null) result.error("busy", "Folder picker already open.", null)
                    else {
                        pendingLyrics = result
                        pendingLyricsFolder = call.argument<String>("folder") ?: ""
                        intentLyricsVolume = Uri.parse(call.argument<String>("uri")).pathSegments.firstOrNull()
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, 71)
                        } catch (_: Exception) {
                            pendingLyrics = null; pendingLyricsFolder = null
                            result.error("folder", "Folder picker unavailable.", null)
                        }
                    }
                }
                "readLocalLyrics" -> worker.execute {
                    try {
                        val text = readLocalLyrics(Uri.parse(call.argument<String>("uri")), call.argument<String>("folder") ?: "")
                        runOnUiThread { result.success(text) }
                    } catch (_: Exception) { runOnUiThread { result.error("lyrics", "Local lyrics could not be read. Choose the song folder again.", null) } }
                }
                "hasPermission" -> result.success(allowed())
                "requestPermission" -> if (allowed()) result.success(true) else if (pendingPermission != null) result.success(false) else {
                    pendingPermission = result
                    requestPermissions(arrayOf(permission), 70)
                }
                "openSettings" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null) }
                "openUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url"))
                    val isWeb = uri.scheme in setOf("https", "http") && !uri.host.isNullOrBlank()
                    val isEmail = uri.scheme == "mailto" && !uri.schemeSpecificPart.isNullOrBlank()
                    if (isWeb || isEmail) {
                        val action = if (isEmail) Intent.ACTION_SENDTO else Intent.ACTION_VIEW
                        try { startActivity(Intent(action, uri)); result.success(null) }
                        catch (_: Exception) { result.error("launcher", "No app available to open this link.", null) }
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
    // READ_MEDIA_AUDIO does not grant access to text sidecars. On scoped-storage
    // devices, the user grants this exact song folder through the system picker.
    private fun readLocalLyrics(audio: Uri, folder: String): String? {
        if (audio.scheme != "content" || audio.authority != MediaStore.AUTHORITY) return null
        var name: String? = null
        var legacyPath: String? = null
        val columns = mutableListOf(MediaStore.MediaColumns.DISPLAY_NAME)
        if (Build.VERSION.SDK_INT <= 28) columns.add(MediaStore.Audio.Media.DATA)
        contentResolver.query(audio, columns.toTypedArray(), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                name = cursor.getString(0)
                if (Build.VERSION.SDK_INT <= 28) legacyPath = cursor.getString(1)
            }
        }
        val sidecar = name?.substringBeforeLast('.')?.plus(".lrc") ?: return null
        if (legacyPath != null) {
            val file = File(File(legacyPath!!).parentFile, sidecar)
            if (file.isFile) return file.inputStream().use { decodeLyrics(it.readBytesBounded()) }
        }
        val saved = lyricsPreferences.getString(folderKey(audio, folder), null) ?: return null
        val tree = Uri.parse(saved)
        val parentId = DocumentsContract.getTreeDocumentId(tree)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1).equals(sidecar, ignoreCase = true)) {
                    val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                    return contentResolver.openInputStream(uri)?.use { decodeLyrics(it.readBytesBounded()) }
                }
            }
        }
        return null
    }
    private fun folderKey(audio: Uri, folder: String) = "${audio.pathSegments.firstOrNull()}:$folder"
    private fun java.io.InputStream.readBytesBounded(): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            if (out.size() + count > 256 * 1024) throw IllegalArgumentException("Lyrics file too large")
            out.write(buffer, 0, count)
        }
        return out.toByteArray()
    }
    private fun decodeLyrics(bytes: ByteArray): String {
        val charset = if (bytes.size >= 2 && ((bytes[0] == 0xff.toByte() && bytes[1] == 0xfe.toByte()) || (bytes[0] == 0xfe.toByte() && bytes[1] == 0xff.toByte()))) Charsets.UTF_16 else Charsets.UTF_8
        return String(bytes, charset)
    }
    @Deprecated("Android legacy activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 71) return
        val result = pendingLyrics
        pendingLyrics = null
        val folder = pendingLyricsFolder
        pendingLyricsFolder = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null || folder == null) { result?.success(false); return }
        try {
            contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Include volume identity so equal paths on different storage volumes do not collide.
            val audioVolume = intentLyricsVolume
            lyricsPreferences.edit().putString("$audioVolume:$folder", tree.toString()).apply()
            result?.success(true)
        } catch (_: Exception) { result?.error("folder", "Read access was not granted.", null) }
    }
    private var intentLyricsVolume: String? = null
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
