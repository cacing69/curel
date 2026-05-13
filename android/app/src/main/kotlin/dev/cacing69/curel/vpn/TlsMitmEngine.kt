package dev.cacing69.curel.vpn

import android.util.Log
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLEngineResult
import javax.net.ssl.SSLSession
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import java.net.Socket
import java.security.SecureRandom
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import java.security.cert.X509Certificate

class TlsMitmEngine(
    private val certManager: CertManager,
    private val hostname: String,
    private val dstPort: Int,
    private val protect: (Socket) -> Boolean
) {
    companion object {
        const val TAG = "CurelMitm"
        const val TLS_APP_MAX = 16384
    }

    private val clientToServer = ByteArrayOutputStream()  // raw bytes from client
    private val serverToClient = ByteArrayOutputStream()  // encrypted bytes to send back to client
    private var serverEngine: SSLEngine? = null
    private var realSocket: SSLSocket? = null
    private var realInput: ByteArrayOutputStream? = null
    private var handshakeDone = false
    private var httpBuffer = ByteArrayOutputStream()
    private var requestCaptured = false
    private var closed = false

    fun isClosed(): Boolean = closed

    fun close() {
        closed = true
        try { realSocket?.close() } catch (_: Exception) {}
    }

    fun feedClientData(data: ByteArray, offset: Int, length: Int): ByteArray? {
        if (closed) return null
        clientToServer.write(data, offset, length)

        if (!handshakeDone) {
            return doHandshake()
        }

        return decryptAndForward()
    }

    fun getEncryptedResponse(): ByteArray? {
        val data = serverToClient.toByteArray()
        if (data.isEmpty()) return null
        serverToClient.reset()
        return data
    }

    private fun doHandshake(): ByteArray? {
        if (serverEngine == null) {
            initServerEngine()
            if (serverEngine == null) return null
        }
        val engine = serverEngine ?: return null

        try {
            engine.beginHandshake()
            var result: SSLEngineResult
            var needMore = false

            while (!needMore) {
                when (engine.handshakeStatus) {
                    javax.net.ssl.SSLEngineResult.HandshakeStatus.NEED_UNWRAP -> {
                        val raw = clientToServer.toByteArray()
                        if (raw.isEmpty()) { needMore = true; break }
                        val inBuf = ByteBuffer.wrap(raw)
                        val outBuf = ByteBuffer.allocate(TLS_APP_MAX)
                        result = engine.unwrap(inBuf, outBuf)
                        runDelegatedTasks(engine)
                        val consumed = raw.size - inBuf.remaining()
                        if (consumed > 0) {
                            clientToServer.reset()
                            clientToServer.write(raw, consumed, raw.size - consumed)
                        }
                        outBuf.flip()
                        if (outBuf.hasRemaining()) {
                            val appData = ByteArray(outBuf.remaining())
                            outBuf.get(appData)
                            // Handshake data from unwrap is internal, not app data
                        }
                        when (result.handshakeStatus) {
                            javax.net.ssl.SSLEngineResult.HandshakeStatus.FINISHED -> {
                                handshakeDone = true
                                connectToRealServer()
                                Log.d(TAG, "TLS handshake done for $hostname")
                                return serverToClientData()
                            }
                            else -> {}
                        }
                    }
                    javax.net.ssl.SSLEngineResult.HandshakeStatus.NEED_WRAP -> {
                        val outBuf = ByteBuffer.allocate(TLS_APP_MAX)
                        result = engine.wrap(ByteBuffer.allocate(0), outBuf)
                        runDelegatedTasks(engine)
                        outBuf.flip()
                        if (outBuf.hasRemaining()) {
                            val wrapData = ByteArray(outBuf.remaining())
                            outBuf.get(wrapData)
                            serverToClient.write(wrapData)
                        }
                    }
                    javax.net.ssl.SSLEngineResult.HandshakeStatus.NEED_TASK -> {
                        runDelegatedTasks(engine)
                    }
                    javax.net.ssl.SSLEngineResult.HandshakeStatus.NOT_HANDSHAKING -> {
                        handshakeDone = true
                        connectToRealServer()
                        return serverToClientData()
                    }
                    javax.net.ssl.SSLEngineResult.HandshakeStatus.FINISHED -> {
                        handshakeDone = true
                        connectToRealServer()
                        return serverToClientData()
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Handshake error for $hostname: ${e.message}")
            closed = true
        }

        return serverToClientData()
    }

    private fun decryptAndForward(): ByteArray? {
        val engine = serverEngine ?: return null
        val raw = clientToServer.toByteArray()
        if (raw.isEmpty()) return null

        try {
            val inBuf = ByteBuffer.wrap(raw)
            val outBuf = ByteBuffer.allocate(TLS_APP_MAX * 2)
            val result = engine.unwrap(inBuf, outBuf)
            runDelegatedTasks(engine)

            val consumed = raw.size - inBuf.remaining()
            if (consumed > 0) {
                clientToServer.reset()
                if (inBuf.hasRemaining()) {
                    clientToServer.write(raw, raw.size - inBuf.remaining(), inBuf.remaining())
                }
            }

            outBuf.flip()
            if (outBuf.hasRemaining()) {
                val appData = ByteArray(outBuf.remaining())
                outBuf.get(appData)
                httpBuffer.write(appData)

                // Forward to real server
                realSocket?.getOutputStream()?.write(appData)
                realSocket?.getOutputStream()?.flush()

                // Check if we have a complete HTTP request
                if (!requestCaptured) {
                    tryCapturedRequest()
                }
            }

            // Read response from real server
            return readRealResponse()
        } catch (e: Exception) {
            Log.w(TAG, "Decrypt error for $hostname: ${e.message}")
        }
        return null
    }

    private fun readRealResponse(): ByteArray? {
        val socket = realSocket ?: return null
        val buf = realInput ?: return null
        return try {
            val input = socket.inputStream
            val available = input.available()
            if (available <= 0) return null
            val data = ByteArray(available.coerceAtMost(65535))
            val read = input.read(data)
            if (read <= 0) return null

            val response = data.copyOf(read)

            // Try to capture HTTP response
            tryCaptureResponse(response)

            // Re-encrypt for client
            buf.write(response)
            val engine = serverEngine ?: return null
            val plainBuf = ByteBuffer.wrap(response)
            val encBuf = ByteBuffer.allocate(TLS_APP_MAX * 2)
            engine.wrap(plainBuf, encBuf)
            encBuf.flip()
            val encrypted = ByteArray(encBuf.remaining())
            encBuf.get(encrypted)
            encrypted
        } catch (_: Exception) {
            null
        }
    }

    private fun serverToClientData(): ByteArray? {
        val data = serverToClient.toByteArray()
        if (data.isEmpty()) return null
        serverToClient.reset()
        return data
    }

    private fun initServerEngine() {
        val ctx = certManager.createSslContext(hostname) ?: return
        serverEngine = ctx.createSSLEngine(hostname, dstPort)
        serverEngine?.useClientMode = false
        serverEngine?.needClientAuth = false
    }

    private fun connectToRealServer() {
        try {
            val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
                override fun checkClientTrusted(c: Array<X509Certificate>?, a: String?) {}
                override fun checkServerTrusted(c: Array<X509Certificate>?, a: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
            })
            val ctx = SSLContext.getInstance("TLS")
            ctx.init(null, trustAll, SecureRandom())
            val factory = ctx.socketFactory
            val socket = factory.createSocket() as SSLSocket
            protect(socket)
            socket.connect(InetSocketAddress(hostname, 443), 5000)
            socket.startHandshake()
            realSocket = socket
            realInput = ByteArrayOutputStream()
            Log.d(TAG, "Connected to real $hostname:443 via TLS")
        } catch (e: Exception) {
            Log.w(TAG, "Real connect failed for $hostname: ${e.message}")
            closed = true
        }
    }

    private fun tryCapturedRequest() {
        val raw = httpBuffer.toByteArray()
        if (raw.isEmpty()) return
        try {
            val text = String(raw, Charsets.UTF_8)
            if (!text.startsWith("GET ") && !text.startsWith("POST ") &&
                !text.startsWith("PUT ") && !text.startsWith("DELETE ") &&
                !text.startsWith("PATCH ") && !text.startsWith("HEAD ") &&
                !text.startsWith("OPTIONS ")) return
            val lines = text.split("\r\n")
            val requestLine = lines[0].split(" ")
            if (requestLine.size < 2) return

            val method = requestLine[0]
            val url = requestLine[1]
            val host = lines.find { it.startsWith("Host:", ignoreCase = true) }
                ?.substringAfter(":")?.trim() ?: hostname
            val headersEnd = text.indexOf("\r\n\r\n")
            val body = if (headersEnd >= 0 && text.length > headersEnd + 4)
                text.substring(headersEnd + 4) else ""

            Log.d(TAG, "HTTPS $method $url from $hostname")
            CurelVpnService.flutterBridge?.sendCapturedRequest(
                method = method,
                url = "https://$host$url",
                host = host,
                headers = lines.drop(1).takeWhile { it.isNotEmpty() }.joinToString("\n") { it },
                body = body,
                sourceIp = hostname,
                timestamp = System.currentTimeMillis()
            )
            requestCaptured = true
            httpBuffer.reset()
        } catch (_: Exception) {}
    }

    private fun tryCaptureResponse(response: ByteArray) {
        // For now, just log — response capture can be added later
        // The request is what we care about for the .curl export
    }

    private fun runDelegatedTasks(engine: SSLEngine) {
        var task: Runnable?
        task = engine.delegatedTask
        while (task != null) {
            task.run()
            task = engine.delegatedTask
        }
    }

    private fun Int.coerceAtMost(max: Int): Int = if (this > max) max else this
}
