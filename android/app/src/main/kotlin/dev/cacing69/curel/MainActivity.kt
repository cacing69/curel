package dev.cacing69.curel

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.security.KeyChain
import android.util.Log
import dev.cacing69.curel.vpn.CertManager
import dev.cacing69.curel.vpn.CurelVpnService
import dev.cacing69.curel.vpn.VpnFlutterBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vpnRequestCode = 42
    private val certRequestCode = 43

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize CertManager eagerly so installRootCa works before VPN starts
        CertManager(this)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "curel/traffic_capture"
        )
        val bridge = VpnFlutterBridge(channel)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> startVpnCapture(result)
                "stopCapture" -> {
                    stopVpnCapture()
                    result.success(true)
                }
                "isCapturing" -> {
                    result.success(CurelVpnService.isRunning)
                }
                "installRootCa" -> installRootCa(result)
                "isCertReady" -> {
                    val ready = CertManager.instance?.isRootCaReady() ?: false
                    result.success(ready)
                }
                else -> result.notImplemented()
            }
        }

        CurelVpnService.flutterBridge = bridge
    }

    private fun installRootCa(result: MethodChannel.Result) {
        val certBytes = CertManager.instance?.getRootCaBytes()
        if (certBytes == null) {
            result.error("NO_CERT", "Root CA certificate not available", null)
            return
        }
        try {
            val intent = KeyChain.createInstallIntent()
            intent.putExtra(KeyChain.EXTRA_CERTIFICATE, certBytes)
            intent.putExtra(KeyChain.EXTRA_NAME, "Curel MITM Root CA")
            startActivityForResult(intent, certRequestCode)
            result.success("installer")
        } catch (e: Exception) {
            // Emulator / no lock screen — fallback to save file
            Log.w("CurelVpn", "KeyChain failed, saving to Downloads: ${e.message}")
            try {
                val certFile = CertManager.instance?.getRootCaFile()
                if (certFile != null && certFile.exists()) {
                    val downloads = java.io.File(
                        android.os.Environment.getExternalStoragePublicDirectory(
                            android.os.Environment.DIRECTORY_DOWNLOADS
                        ), "curel_root_ca.crt"
                    )
                    certFile.copyTo(downloads, overwrite = true)
                    result.success("downloaded:${downloads.absolutePath}")
                } else {
                    result.error("NO_FILE", "Cert file not found", null)
                }
            } catch (e2: Exception) {
                result.error("SAVE_FAILED", e2.message, null)
            }
        }
    }

    private fun startVpnCapture(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, vpnRequestCode)
            result.success("preparing")
        } else {
            startVpnService()
            result.success(true)
        }
    }

    private fun stopVpnCapture() {
        val intent = Intent(this, CurelVpnService::class.java).apply {
            action = "STOP"
        }
        startService(intent)
    }

    private fun startVpnService() {
        val intent = Intent(this, CurelVpnService::class.java)
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                Log.d("CurelVpn", "VPN permission granted")
            } else {
                Log.d("CurelVpn", "VPN permission denied")
            }
        }
    }
}
