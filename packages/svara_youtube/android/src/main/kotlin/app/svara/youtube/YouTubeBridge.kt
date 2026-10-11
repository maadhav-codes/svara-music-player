// SPDX-License-Identifier: GPL-3.0-or-later
package app.svara.youtube

import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.Image
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.exceptions.*
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.stream.*
import java.io.IOException
import java.net.SocketTimeoutException
import java.util.UUID
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs

class YouTubeBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private val downloader = ExtractorDownloader()
        private var initialized = false
        @Synchronized private fun initialize() {
            if (!initialized) { NewPipe.init(downloader); initialized = true }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private val worker = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, ArrayBlockingQueue(8))
    private val operations = ConcurrentHashMap<String, Operation>()
    private data class Continuation(val query: String, val page: Page, val expires: Long)
    private val continuations = LinkedHashMap<String, Continuation>()
    private class Operation(val result: MethodChannel.Result) {
        val context = RequestContext()
        val finished = AtomicBoolean(false)
        var future: Future<*>? = null
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "app.svara/youtube").also { it.setMethodCallHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        operations.keys.toList().forEach { cancel(it) }
        worker.shutdownNow()
        synchronized(continuations) { continuations.clear() }
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") { cancel(call.argument<String>("requestId") ?: ""); result.success(null); return }
        if (call.method !in setOf("search", "getMetadata", "resolveAudio")) { result.notImplemented(); return }
        val id = call.argument<String>("requestId") ?: UUID.randomUUID().toString()
        val op = Operation(result)
        operations[id] = op
        val timeout = Runnable { cancel(id, "timeout") }
        main.postDelayed(timeout, 30000)
        try {
            op.future = worker.submit {
                downloader.context.set(op.context)
                try {
                    initialize()
                    val answer = when (call.method) {
                        "search" -> search(call)
                        "getMetadata" -> metadata(info(call))
                        else -> resolve(call)
                    }
                    main.post { if (op.finished.compareAndSet(false, true)) result.success(answer) }
                } catch (e: Exception) {
                    val code = classify(e, op)
                    val retry = causes(e).filterIsInstance<ExtractorHttpException>().firstOrNull()?.retryAfter
                    main.post { if (op.finished.compareAndSet(false, true)) result.error(code, "YouTube request failed.", mapOf("retryAfter" to retry)) }
                } finally {
                    downloader.context.remove()
                    operations.remove(id, op)
                    main.removeCallbacks(timeout)
                }
            }
        } catch (_: RejectedExecutionException) {
            operations.remove(id); main.removeCallbacks(timeout)
            op.finished.set(true); result.error("busy", "YouTube is busy.", null)
        }
    }
    private fun cancel(id: String, code: String = "cancelled") {
        val op = operations.remove(id) ?: return
        op.context.cancel(); op.future?.cancel(true)
        if (op.finished.compareAndSet(false, true)) main.post { op.result.error(code, "YouTube request cancelled.", null) }
    }
    private fun causes(error: Throwable): List<Throwable> = generateSequence(error) { it.cause }.take(8).toList()
    private fun classify(error: Exception, op: Operation): String {
        if (op.context.cancelled.get()) return "cancelled"
        val chain = causes(error)
        if (chain.any { it is ExtractorHttpException && it.status == 429 }) return "rate_limit"
        if (chain.any { it is ExtractorHttpException }) return "server"
        if (chain.any { it is SocketTimeoutException || it is TimeoutException }) return "timeout"
        if (chain.any { it is AgeRestrictedContentException || it is PrivateContentException || it is GeographicRestrictionException || it is PaidContentException || it is ReCaptchaException || it is SignInConfirmNotBotException }) return "restricted"
        if (chain.any { it is ContentNotAvailableException }) return "unavailable"
        if (chain.any { it is UnsupportedAudio }) return "unsupported_format"
        if (chain.any { it is IllegalArgumentException }) return "invalid"
        if (chain.any { it is IOException }) return "network"
        return "extractor"
    }
    private fun videoId(call: MethodCall): String {
        val id = call.argument<String>("videoId") ?: ""
        require(Regex("[A-Za-z0-9_-]{11}").matches(id))
        return id
    }
    private fun info(call: MethodCall): StreamInfo {
        val id = videoId(call)
        val extractor = ServiceList.YouTube.getStreamExtractor("https://www.youtube.com/watch?v=$id")
        extractor.fetchPage()
        // Reject age restrictions before StreamInfo attempts optional fields.
        if (extractor.ageLimit > 0) throw AgeRestrictedContentException("Restricted video")
        return StreamInfo.getInfo(extractor)
    }
    private fun artwork(images: List<Image>): String? = images
        .filter { Uri.parse(it.url).scheme == "https" }
        .minByOrNull { abs(it.width - 480) }?.url
    private fun metadata(info: StreamInfo): Map<String, Any?> = mapOf(
        "videoId" to info.id, "title" to info.name, "uploader" to info.uploaderName,
        "uploaderUrl" to info.uploaderUrl, "durationMs" to maxOf(0, info.duration) * 1000,
        "artwork" to artwork(info.thumbnails), "streamable" to (info.ageLimit == 0 && info.streamType == StreamType.VIDEO_STREAM)
    )
    private fun search(call: MethodCall): Map<String, Any?> {
        val query = call.argument<String>("query")?.trim() ?: ""
        require(query.isNotEmpty() && query.length <= 300)
        // Songs uses YouTube Music's catalog, rather than general video results.
        // Continuous mixes/album uploads are exposed by its music-video search.
        val filter = if (MusicSearchPolicy.allowsLongMusic(query))
            YoutubeSearchQueryHandlerFactory.MUSIC_VIDEOS else YoutubeSearchQueryHandlerFactory.MUSIC_SONGS
        val handler = ServiceList.YouTube.searchQHFactory.fromQuery(query, listOf(filter), "")
        val token = call.argument<String>("continuation")
        val items: List<org.schabi.newpipe.extractor.InfoItem>
        val next: Page?
        if (token == null) {
            val data = SearchInfo.getInfo(ServiceList.YouTube, handler)
            if (data.relatedItems.isEmpty() && data.errors.isNotEmpty()) throw ExtractionException("Search extraction failed", data.errors.first())
            items = data.relatedItems; next = data.nextPage
        } else {
            val saved = synchronized(continuations) { continuations[token] }
            require(saved != null && saved.query == query && saved.expires > System.currentTimeMillis())
            val data = SearchInfo.getMoreItems(ServiceList.YouTube, handler, saved.page)
            if (data.items.isEmpty() && data.errors.isNotEmpty()) throw ExtractionException("Search extraction failed", data.errors.first())
            items = data.items; next = data.nextPage
        }
        val tracks = items.filterIsInstance<StreamInfoItem>()
            .filter { it.streamType == StreamType.VIDEO_STREAM &&
                MusicSearchPolicy.accepts(query, it.name, it.duration) }
            .take(50).mapNotNull { item ->
            val id = try { ServiceList.YouTube.streamLHFactory.getId(item.url) } catch (_: Exception) { return@mapNotNull null }
            mapOf("videoId" to id, "title" to item.name, "uploader" to item.uploaderName,
                "uploaderUrl" to item.uploaderUrl, "durationMs" to maxOf(0, item.duration) * 1000,
                "artwork" to artwork(item.thumbnails),
                "streamable" to (item.streamType == StreamType.VIDEO_STREAM && item.contentAvailability in setOf(ContentAvailability.AVAILABLE, ContentAvailability.UNKNOWN)))
        }
        val nextToken = if (Page.isValid(next)) UUID.randomUUID().toString() else null
        if (nextToken != null && next != null) synchronized(continuations) {
            continuations.entries.removeAll { it.value.expires <= System.currentTimeMillis() }
            while (continuations.size >= 20) continuations.remove(continuations.keys.first())
            continuations[nextToken] = Continuation(query, next, System.currentTimeMillis() + 15 * 60 * 1000)
        }
        return mapOf("tracks" to tracks, "continuation" to nextToken)
    }
    private class UnsupportedAudio : Exception()
    private fun resolve(call: MethodCall): Map<String, Any?> {
        val info = info(call)
        if (info.streamType != StreamType.VIDEO_STREAM) throw UnsupportedAudio()
        val target = when (call.argument<String>("quality")) { "dataSaver" -> 64; "high" -> 256; else -> 128 }
        val supported = info.audioStreams.filter {
            it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP &&
                it.format in setOf(MediaFormat.M4A, MediaFormat.WEBMA, MediaFormat.WEBMA_OPUS) && Uri.parse(it.content).scheme == "https"
        }
        val ranked = supported.sortedWith(compareBy<AudioStream> { abs(it.averageBitrate - target) }
            .thenBy { if (it.format == MediaFormat.M4A) 0 else 1 })
        val preferred = ranked.firstOrNull() ?: throw UnsupportedAudio()
        val stream = if (call.argument<Boolean>("alternative") == true)
            ranked.firstOrNull { it.format != preferred.format } ?: ranked.getOrNull(1) ?: preferred
            else preferred
        val expires = Uri.parse(stream.content).getQueryParameter("expire")?.toLongOrNull()?.times(1000)
        return mapOf("track" to metadata(info), "url" to stream.content,
            "headers" to emptyMap<String, String>(), "mimeType" to stream.format?.mimeType,
            "codec" to stream.codec, "expiresAt" to expires)
    }
}
