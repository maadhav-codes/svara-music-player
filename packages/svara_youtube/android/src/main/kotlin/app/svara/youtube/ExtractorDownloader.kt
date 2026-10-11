// SPDX-License-Identifier: GPL-3.0-or-later
package app.svara.youtube

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class ExtractorHttpException(val status: Int, val retryAfter: Int?) : IOException()
internal class RequestContext {
    val cancelled = AtomicBoolean(false)
    @Volatile var active: Call? = null
    fun cancel() { cancelled.set(true); active?.cancel() }
}

internal class ExtractorDownloader : Downloader() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS)
        .callTimeout(18, TimeUnit.SECONDS).retryOnConnectionFailure(false).build()
    val context = ThreadLocal<RequestContext>()

    override fun execute(request: Request): Response {
        val state = context.get()
        if (state?.cancelled?.get() == true) throw IOException("cancelled")
        val builder = okhttp3.Request.Builder().url(request.url())
        request.headers().forEach { (name, values) -> values.forEach { builder.addHeader(name, it) } }
        val body = request.dataToSend()?.toRequestBody()
        builder.method(request.httpMethod(), body)
        val call = client.newCall(builder.build())
        state?.active = call
        if (state?.cancelled?.get() == true) { call.cancel(); throw IOException("cancelled") }
        try {
            call.execute().use { response ->
                if (response.code == 429 || response.code >= 500) {
                    throw ExtractorHttpException(response.code, response.header("Retry-After")?.toIntOrNull())
                }
                // Metadata/player scripts only. Audio goes directly to Media3.
                val responseBody = response.body
                if ((responseBody?.contentLength() ?: 0) > 16 * 1024 * 1024) throw IOException("response too large")
                val buffer = okio.Buffer()
                if (responseBody != null) {
                    val source = responseBody.source()
                    while (source.read(buffer, 8192) != -1L) {
                        if (buffer.size > 16 * 1024 * 1024 || state?.cancelled?.get() == true) throw IOException("response cancelled or too large")
                    }
                }
                return Response(response.code, response.message, response.headers.toMultimap(), buffer.readUtf8(), response.request.url.toString())
            }
        } finally { state?.active = null }
    }
}
