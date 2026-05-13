package dev.cacing69.curel.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import dev.cacing69.curel.MainActivity
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class CurelVpnService : VpnService() {

    companion object {
        const val TAG = "CurelVpn"
        const val CHANNEL_ID = "curel_vpn_capture"
        const val NOTIFICATION_ID = 1001
        const val VPN_ADDRESS = "10.0.0.2"
        const val VPN_ROUTE = "0.0.0.0"
        const val VPN_DNS = "8.8.8.8"
        const val MAX_PACKET = 65535
        const val MTU = 1500
        const val HTTP_PORT = 80

        @Volatile
        var isRunning = false

        @Volatile
        var flutterBridge: VpnFlutterBridge? = null
    }

    private val running = AtomicBoolean(false)
    private val tcpFlows = ConcurrentHashMap<String, TcpFlow>()
    private lateinit var certManager: CertManager

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        certManager = CertManager(this)
        Log.d(TAG, "CertManager initialized, root CA ready: ${certManager.isRootCaReady()}")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running.get()) return START_STICKY

        val action = intent?.action
        if (action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        startVpn()
        return START_STICKY
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun startVpn() {
        startForeground(NOTIFICATION_ID, buildNotification("capturing HTTP traffic..."))
        Log.d(TAG, "Starting CurelVpn")

        val builder = Builder()
            .setSession("Curel HTTP Capture")
            .addAddress(VPN_ADDRESS, 32)
            .addRoute(VPN_ROUTE, 0)
            .addDnsServer(VPN_DNS)
            .setMtu(MTU)
            .setBlocking(true)

        // Exempt curel itself from VPN to avoid capture loop
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {}

        val vpnInterface: ParcelFileDescriptor = builder.establish() ?: run {
            Log.e(TAG, "VPN interface establishment failed")
            stopVpn()
            return
        }

        running.set(true)
        isRunning = true

        val input = FileInputStream(vpnInterface.fileDescriptor)
        val output = FileOutputStream(vpnInterface.fileDescriptor)

        // Packet reader thread
        Thread({
            Log.d(TAG, "[Reader] thread started")
            val buffer = ByteArray(MAX_PACKET)
            while (running.get()) {
                try {
                    val length = input.read(buffer)
                    if (length > 0) {
                        val packet = buffer.copyOf(length)
                        processPacket(packet, output)
                    }
                } catch (e: Exception) {
                    if (running.get()) Log.w(TAG, "[Reader] error: ${e.message}")
                }
            }
            Log.d(TAG, "[Reader] thread stopped")
        }, "VpnReader").start()

        // TCP writer thread — reads real network responses back to VPN
        Thread({
            Log.d(TAG, "[Writer] thread started")
            while (running.get()) {
                try {
                    writePendingTcp(output)
                    Thread.sleep(10)
                } catch (e: Exception) {
                    if (running.get()) Log.w(TAG, "[Writer] error: ${e.message}")
                }
            }
            Log.d(TAG, "[Writer] thread stopped")
        }, "VpnWriter").start()
    }

    private fun stopVpn() {
        running.set(false)
        isRunning = false
        tcpFlows.clear()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.d(TAG, "VPN stopped")
    }

    // ── Packet processing ──────────────────────────────────

    private fun processPacket(packet: ByteArray, vpnOutput: FileOutputStream) {
        if (packet.size < 20) return // Minimum IP header

        val version = (packet[0].toInt() shr 4) and 0x0F
        if (version != 4) return // IPv4 only for MVP

        val headerLength = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < headerLength) return

        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 6) { // Not TCP → forward to real network directly
            forwardUdp(packet, vpnOutput)
            return
        }

        // TCP packet
        val tcpOffset = headerLength
        if (packet.size < tcpOffset + 20) return

        val srcIp = extractIp(packet, 12)
        val dstIp = extractIp(packet, 16)
        val srcPort = extractPort(packet, tcpOffset)
        val dstPort = extractPort(packet, tcpOffset + 2)
        val tcpFlags = packet[tcpOffset + 13].toInt() and 0xFF
        val isSyn = (tcpFlags and 0x02) != 0
        val isPsh = (tcpFlags and 0x08) != 0
        val isFin = (tcpFlags and 0x01) != 0

        val dataOffset = ((packet[tcpOffset + 12].toInt() shr 4) and 0x0F) * 4
        val payloadStart = tcpOffset + dataOffset
        val payloadLen = packet.size - payloadStart

        // Reassemble TCP flow
        val flowKey = "$srcIp:$srcPort-$dstIp:$dstPort"

        if (isSyn && !isPsh) {
            // New connection
            tcpFlows[flowKey] = TcpFlow(srcIp, dstIp, dstPort, vpnOutput,
                { socket -> protect(socket) }, certManager)
        }

        val flow = tcpFlows[flowKey] ?: run {
            // Unknown flow — pass through to VPN output
            try { vpnOutput.write(packet) } catch (_: Exception) {}
            return
        }

        // Feed packet to TCP flow for reassembly
        flow.handlePacket(packet, tcpOffset, dataOffset, payloadStart, payloadLen, isPsh, isFin)

        if (payloadLen > 0 && flow.state == TcpState.ESTABLISHED && dstPort == HTTP_PORT) {
            flow.appendToOutbound(packet, payloadStart, payloadLen)
        }

        if (isFin) {
            tcpFlows.remove(flowKey)
        }
    }

    // ── Forwarding ────────────────────────────────────────

    private fun forwardUdp(packet: ByteArray, vpnOutput: FileOutputStream) {
        // Proxy UDP via protect() socket — echo back for MVP
        try {
            val channel = DatagramChannel.open()
            protect(channel.socket())
            channel.configureBlocking(false)
            channel.close()
        } catch (_: Exception) {}
        // still echo back to VPN for basic connectivity
        try { vpnOutput.write(packet) } catch (_: Exception) {}
    }

    // ── Write pending TCP responses back to VPN ───────────

    private fun writePendingTcp(vpnOutput: FileOutputStream) {
        val iterator = tcpFlows.entries.iterator()
        while (iterator.hasNext()) {
            val (key, flow) = iterator.next()
            val pending = flow.getPendingResponse()
            if (pending != null) {
                vpnOutput.write(pending)
            }
            if (flow.isClosed) {
                iterator.remove()
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────

    private fun extractIp(packet: ByteArray, offset: Int): String {
        return "${packet[offset].toInt() and 0xFF}." +
                "${packet[offset + 1].toInt() and 0xFF}." +
                "${packet[offset + 2].toInt() and 0xFF}." +
                "${packet[offset + 3].toInt() and 0xFF}"
    }

    private fun extractPort(packet: ByteArray, offset: Int): Int {
        return ((packet[offset].toInt() and 0xFF) shl 8) or
                (packet[offset + 1].toInt() and 0xFF)
    }

    // ── Notification ──────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "HTTP Capture",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing traffic capture"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val stopIntent = Intent(this, CurelVpnService::class.java).apply {
            action = "STOP"
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Curel HTTP Capture")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)
            .build()
    }
}
