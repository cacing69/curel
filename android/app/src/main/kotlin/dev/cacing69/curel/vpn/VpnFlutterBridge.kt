package dev.cacing69.curel.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentLinkedQueue

class VpnFlutterBridge(
    private val channel: MethodChannel,
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
) {
    private val pendingRequests = ConcurrentLinkedQueue<Map<String, Any?>>()
    private var batchScheduled = false

    fun sendCapturedRequest(
        method: String,
        url: String,
        host: String,
        headers: String,
        body: String,
        sourceIp: String,
        timestamp: Long
    ) {
        val data = mapOf(
            "method" to method,
            "url" to url,
            "host" to host,
            "headers" to headers,
            "body" to body,
            "sourceIp" to sourceIp,
            "timestamp" to timestamp
        )
        pendingRequests.add(data)
        scheduleBatch()
    }

    private fun scheduleBatch() {
        if (batchScheduled) return
        batchScheduled = true
        mainHandler.postDelayed({ flushBatch() }, 200)
    }

    private fun flushBatch() {
        batchScheduled = false
        val batch = mutableListOf<Map<String, Any?>>()
        while (pendingRequests.isNotEmpty()) {
            batch.add(pendingRequests.poll())
        }
        if (batch.isNotEmpty()) {
            mainHandler.post {
                channel.invokeMethod("onCapturedRequests", listOf(batch))
            }
        }
    }
}
