package dev.cacing69.curel.vpn

import android.content.Context
import android.util.Log
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.BasicConstraints
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.Date
import java.util.concurrent.ConcurrentHashMap
import java.security.SecureRandom
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import java.security.cert.Certificate

class CertManager(private val context: Context) {

    companion object {
        const val TAG = "CurelCert"
        const val ROOT_ALIAS = "curel-root-ca"
        const val KEYSTORE_PASS = "curel"
        const val CA_VALIDITY_DAYS = 3650L // 10 years
        const val CERT_VALIDITY_DAYS = 365L

        @Volatile
        var instance: CertManager? = null
    }

    private val certDir = File(context.filesDir, "certs")
    private val keystoreFile = File(certDir, "curel_mitm.p12")
    private val rootCaFile = File(certDir, "curel_root_ca.crt")
    private val keyStore: KeyStore = KeyStore.getInstance("PKCS12")
    private val certCache = ConcurrentHashMap<String, Pair<KeyPair, X509Certificate>>()

    private var rootKeyPair: KeyPair? = null
    private var rootCert: X509Certificate? = null

    init {
        if (instance == null) {
            certDir.mkdirs()
            loadOrCreateRootCa()
            instance = this
        }
    }

    fun getRootCaFile(): File = rootCaFile
    fun isRootCaReady(): Boolean = rootCert != null
    fun getRootCaBytes(): ByteArray? = rootCert?.encoded

    private fun loadOrCreateRootCa() {
        if (keystoreFile.exists()) {
            try {
                FileInputStream(keystoreFile).use { fis ->
                    keyStore.load(fis, KEYSTORE_PASS.toCharArray())
                }
                val entry = keyStore.getEntry(ROOT_ALIAS,
                    KeyStore.PasswordProtection(KEYSTORE_PASS.toCharArray()))
                if (entry is KeyStore.PrivateKeyEntry) {
                    rootKeyPair = KeyPair(entry.certificate.publicKey, entry.privateKey)
                    rootCert = entry.certificate as X509Certificate
                    Log.d(TAG, "Loaded existing root CA")
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to load keystore, regenerating: ${e.message}")
            }
        }
        generateRootCa()
    }

    private fun generateRootCa() {
        try {
            val keyGen = KeyPairGenerator.getInstance("RSA")
            keyGen.initialize(2048, SecureRandom())
            val kp = keyGen.generateKeyPair()

            val now = Date()
            val expires = Date(now.time + CA_VALIDITY_DAYS * 86400000L)
            val issuer = X500Name("CN=Curel MITM Root CA, O=Curel, C=ID")
            val serial = BigInteger(64, SecureRandom())

            val builder = JcaX509v3CertificateBuilder(
                issuer, serial, now, expires, issuer, kp.public
            )
            builder.addExtension(Extension.basicConstraints, true, BasicConstraints(true))

            val signer = JcaContentSignerBuilder("SHA256WithRSA").build(kp.private)
            val cert = JcaX509CertificateConverter().getCertificate(builder.build(signer))

            // Save to keystore
            keyStore.load(null, KEYSTORE_PASS.toCharArray())
            keyStore.setKeyEntry(ROOT_ALIAS, kp.private, KEYSTORE_PASS.toCharArray(),
                arrayOf<Certificate>(cert))
            FileOutputStream(keystoreFile).use { fos ->
                keyStore.store(fos, KEYSTORE_PASS.toCharArray())
            }

            // Export root CA cert for user installation
            FileOutputStream(rootCaFile).use { fos ->
                fos.write(cert.encoded)
            }

            rootKeyPair = kp
            rootCert = cert
            Log.d(TAG, "Generated root CA -> ${rootCaFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate root CA: ${e.message}", e)
        }
    }

    fun getCertForHost(hostname: String): Pair<KeyPair, X509Certificate>? {
        val root = rootCert ?: return null
        val rootKp = rootKeyPair ?: return null

        return certCache.getOrPut(hostname) {
            try {
                val keyGen = KeyPairGenerator.getInstance("RSA")
                keyGen.initialize(2048, SecureRandom())
                val kp = keyGen.generateKeyPair()

                val now = Date()
                val expires = Date(now.time + CERT_VALIDITY_DAYS * 86400000L)
                val subject = X500Name("CN=$hostname, O=Curel MITM")
                val issuer = X500Name(root.subjectX500Principal.name)
                val serial = BigInteger(64, SecureRandom())

                val builder = JcaX509v3CertificateBuilder(
                    issuer, serial, now, expires, subject, kp.public
                )
                val sans = GeneralNames(arrayOf(GeneralName(GeneralName.dNSName, hostname)))
                builder.addExtension(Extension.subjectAlternativeName, false, sans)

                val signer = JcaContentSignerBuilder("SHA256WithRSA").build(rootKp.private)
                val cert = JcaX509CertificateConverter().getCertificate(builder.build(signer))

                Pair(kp, cert)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to generate cert for $hostname: ${e.message}")
                null
            }
        }
    }

    fun createSslContext(hostname: String): SSLContext? {
        val (kp, cert) = getCertForHost(hostname) ?: return null
        return try {
            val ks = KeyStore.getInstance("PKCS12")
            ks.load(null, null)
            ks.setKeyEntry("cert", kp.private, KEYSTORE_PASS.toCharArray(),
                arrayOf<Certificate>(cert))
            val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            kmf.init(ks, KEYSTORE_PASS.toCharArray())
            val ctx = SSLContext.getInstance("TLS")
            ctx.init(kmf.keyManagers, null, SecureRandom())
            ctx
        } catch (e: Exception) {
            Log.e(TAG, "SSLContext failed for $hostname: ${e.message}")
            null
        }
    }
}
