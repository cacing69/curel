package dev.cacing69.curel.vpn

import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket

enum class TcpState { SYN_SENT, ESTABLISHED, CLOSING, CLOSED }

class TcpFlow(
    val srcIp: String,
    val dstIp: String,
    val dstPort: Int,
    private val vpnOutput: FileOutputStream,
    private val protect: (Socket) -> Boolean,
    private val certManager: CertManager
) {
    private val outboundBuffer = ByteArrayOutputStream()
    private var realSocket: Socket? = null
    private var mitmEngine: TlsMitmEngine? = null
    private var sniHostname: String? = null
    private var isHttps = dstPort == 443

    var state: TcpState = TcpState.SYN_SENT
    val isClosed: Boolean get() = state == TcpState.CLOSED

    fun handlePacket(
        packet: ByteArray,
        tcpOffset: Int,
        dataOffset: Int,
        payloadStart: Int,
        payloadLen: Int,
        isPsh: Boolean,
        isFin: Boolean
    ) {
        if (isFin) {
            state = TcpState.CLOSING
            try { realSocket?.close() } catch (_: Exception) {}
            try { mitmEngine?.close() } catch (_: Exception) {}
            mitmEngine = null
        }

        if (payloadLen == 0) return

        if (isHttps && state == TcpState.SYN_SENT && certManager.isRootCaReady()) {
            bufferOutbound(packet, payloadStart, payloadLen)
            if (tryDetectSni()) {
                initMitm()
            }
            return
        }

        if (!isHttps && payloadLen > 0 && state == TcpState.SYN_SENT) {
            establishRealConnection()
        }

        if (isHttps && mitmEngine != null) {
            processMitmOutbound(packet, payloadStart, payloadLen)
        } else if (!isHttps && payloadLen > 0 && realSocket != null) {
            try {
                realSocket?.getOutputStream()?.write(packet, payloadStart, payloadLen)
                realSocket?.getOutputStream()?.flush()
            } catch (e: Exception) {
                Log.w(CurelVpnService.TAG, "TcpFlow write error: ${e.message}")
                state = TcpState.CLOSED
            }
        }

        if (isHttps && mitmEngine == null) {
            bufferOutbound(packet, payloadStart, payloadLen)
        }

        if (isPsh && dstPort == 80) {
            checkHttpRequest()
        }

        if (isFin) {
            state = TcpState.CLOSED
        }
    }

    fun appendToOutbound(packet: ByteArray, start: Int, length: Int) {
        if (dstPort == 80) {
            outboundBuffer.write(packet, start, length)
        }
    }

    fun getPendingResponse(): ByteArray? {
        val engine = mitmEngine
        if (engine != null) {
            return engine.getEncryptedResponse()
        }
        if (realSocket == null || realSocket!!.isClosed) return null
        return try {
            val input = realSocket!!.getInputStream()
            val available = input.available()
            if (available <= 0) return null
            val buf = ByteArray(available.coerceAtMost(65535))
            val read = input.read(buf)
            if (read <= 0) null else buf.copyOf(read)
        } catch (_: Exception) {
            null
        }
    }

    private fun bufferOutbound(packet: ByteArray, start: Int, length: Int) {
        outboundBuffer.write(packet, start, length)
    }

    private fun tryDetectSni(): Boolean {
        val raw = outboundBuffer.toByteArray()
        if (raw.size < 50) return false

        // Look for TLS ClientHello (0x16 0x03 0x0x)
        var pos = 0
        while (pos < raw.size - 5) {
            if (raw[pos] == 0x16.toByte() && raw[pos + 1] == 0x03.toByte()) {
                val recordLen = ((raw[pos + 3].toInt() and 0xFF) shl 8) or (raw[pos + 4].toInt() and 0xFF)
                var inner = pos + 5
                if (inner + recordLen > raw.size) break

                if (raw[inner] == 0x01.toByte()) { // ClientHello
                    // Skip: handshake type(1) + 3 bytes length
                    if (inner + 4 + 2 + 32 > raw.size) break
                    inner += 4 + 2 + 32 // version(2) + random(32)

                    // Session ID
                    val sessionLen = raw[inner].toInt() and 0xFF
                    inner += 1 + sessionLen

                    // Cipher suites
                    if (inner + 2 > raw.size) break
                    val cipherLen = ((raw[inner].toInt() and 0xFF) shl 8) or (raw[inner + 1].toInt() and 0xFF)
                    inner += 2 + cipherLen

                    // Compression
                    if (inner + 1 > raw.size) break
                    val compLen = raw[inner].toInt() and 0xFF
                    inner += 1 + compLen

                    // Extensions
                    if (inner + 2 > raw.size) break
                    val extLen = ((raw[inner].toInt() and 0xFF) shl 8) or (raw[inner + 1].toInt() and 0xFF)
                    var extPos = inner + 2
                    val extEnd = extPos + extLen

                    while (extPos + 4 <= extEnd && extPos + 4 <= raw.size) {
                        val extType = ((raw[extPos].toInt() and 0xFF) shl 8) or (raw[extPos + 1].toInt() and 0xFF)
                        val extDataLen = ((raw[extPos + 2].toInt() and 0xFF) shl 8) or (raw[extPos + 3].toInt() and 0xFF)
                        if (extType == 0x0000) { // SNI
                            if (extPos + 4 + 5 <= raw.size) {
                                var sniPos = extPos + 4 + 2 // skip server name list length(2)
                                val nameType = raw[sniPos].toInt() and 0xFF // 0 = hostname
                                val nameLen = ((raw[sniPos + 1].toInt() and 0xFF) shl 8) or (raw[sniPos + 2].toInt() and 0xFF)
                                if (nameType == 0 && sniPos + 3 + nameLen <= raw.size) {
                                    sniHostname = String(raw, sniPos + 3, nameLen, Charsets.UTF_8)
                                    Log.d(CurelVpnService.TAG, "SNI detected: $sniHostname")
                                    return true
                                }
                            }
                        }
                        extPos += 4 + extDataLen
                    }
                }
                break
            }
            pos++
        }
        return false
    }

    private fun initMitm() {
        val hostname = sniHostname ?: dstIp
        Log.d(CurelVpnService.TAG, "Starting MITM for $hostname:443")
        mitmEngine = TlsMitmEngine(certManager, hostname, dstPort, protect)
        state = TcpState.ESTABLISHED

        // Feed buffered ClientHello to engine
        val raw = outboundBuffer.toByteArray()
        if (raw.isNotEmpty()) {
            val encrypted = mitmEngine?.feedClientData(raw, 0, raw.size)
            outboundBuffer.reset()
            if (encrypted != null) {
                try { vpnOutput.write(encrypted) } catch (_: Exception) {}
            }
        }
    }

    private fun processMitmOutbound(packet: ByteArray, start: Int, length: Int) {
        val engine = mitmEngine ?: return
        if (engine.isClosed()) {
            state = TcpState.CLOSED
            return
        }
        val encrypted = engine.feedClientData(packet, start, length)
        if (encrypted != null) {
            try { vpnOutput.write(encrypted) } catch (_: Exception) {}
        }
    }

    private fun establishRealConnection() {
        try {
            val socket = Socket()
            protect(socket)
            socket.connect(InetSocketAddress(dstIp, dstPort), 5000)
            realSocket = socket
            state = TcpState.ESTABLISHED
            Log.d(CurelVpnService.TAG, "Connected to $dstIp:$dstPort")
        } catch (e: Exception) {
            Log.w(CurelVpnService.TAG, "Connect failed $dstIp:$dstPort: ${e.message}")
            state = TcpState.CLOSED
        }
    }

    private fun checkHttpRequest() {
        val raw = outboundBuffer.toByteArray()
        if (raw.isEmpty()) return
        try {
            val text = String(raw, Charsets.UTF_8)
            val lines = text.split("\r\n")
            if (lines.isEmpty()) return

            val requestLine = lines[0].split(" ")
            if (requestLine.size < 2) return

            val method = requestLine[0].uppercase()
            val url = requestLine[1]
            val host = lines.find { it.startsWith("Host:", ignoreCase = true) }
                ?.substringAfter(":")?.trim() ?: dstIp

            val headersEnd = text.indexOf("\r\n\r\n")
            val body = if (headersEnd >= 0 && text.length > headersEnd + 4)
                text.substring(headersEnd + 4) else ""

            Log.d(CurelVpnService.TAG, "HTTP $method $url from $srcIp")
            CurelVpnService.flutterBridge?.sendCapturedRequest(
                method = method,
                url = url,
                host = host,
                headers = lines.drop(1).takeWhile { it.isNotEmpty() }.joinToString("\n") { it },
                body = body,
                sourceIp = srcIp,
                timestamp = System.currentTimeMillis()
            )

            outboundBuffer.reset()
        } catch (e: Exception) {
            Log.w(CurelVpnService.TAG, "HTTP parse error: ${e.message}")
        }
    }

    private fun Int.coerceAtMost(max: Int): Int = if (this > max) max else this
}
