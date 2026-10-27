package com.beamdrop.receiver.service

import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.net.URLEncoder

data class OutgoingTransferState(
    val fileName: String,
    val fileSize: Long,
    val bytesSent: Long,
    val speedBytesPerSec: Double,
    val isFinished: Boolean = false,
    val error: String? = null
) {
    val progress: Float
        get() = if (fileSize > 0) (bytesSent.toFloat() / fileSize).coerceIn(0f, 1f) else 0f
}

object FileSenderManager {
    private const val TAG = "FileSenderManager"
    const val MAC_RECEIVER_PORT = 8768
    private const val PREFS_NAME = "beamdrop_sender_prefs"
    private const val KEY_MAC_IP = "last_known_mac_ip"

    private val _outgoingTransfer = MutableStateFlow<OutgoingTransferState?>(null)
    val outgoingTransfer = _outgoingTransfer.asStateFlow()

    private val _lastKnownMacIp = MutableStateFlow<String?>("192.168.1.4")
    val lastKnownMacIp = _lastKnownMacIp.asStateFlow()

    fun init(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KEY_MAC_IP, null)
        if (!saved.isNullOrEmpty()) {
            _lastKnownMacIp.value = saved
        }
    }

    fun setLastKnownMacIp(context: Context, ip: String) {
        if (ip.isEmpty() || ip == "127.0.0.1" || ip.startsWith("::")) return
        if (_lastKnownMacIp.value != ip) {
            _lastKnownMacIp.value = ip
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(KEY_MAC_IP, ip).apply()
            Log.i(TAG, "Recorded active Mac IP: $ip")
        }
    }

    /**
     * Resolves the target Mac IP:
     * 1. Returns current lastKnownMacIp if reachable.
     * 2. Otherwise scans the local /24 subnet for MacReceiver on port 8768.
     */
    suspend fun resolveTargetMac(context: Context, localIp: String): String? = withContext(Dispatchers.IO) {
        init(context)
        val current = _lastKnownMacIp.value
        if (!current.isNullOrEmpty() && isMacReceiverReachable(current)) {
            return@withContext current
        }

        // Subnet scan
        val prefix = if (localIp.contains('.')) {
            localIp.substringBeforeLast('.') + "."
        } else {
            "192.168.1."
        }

        Log.i(TAG, "Scanning subnet $prefix* for Mac receiver port $MAC_RECEIVER_PORT...")
        val foundIp = scanSubnetForReceiver(prefix)
        if (foundIp != null) {
            setLastKnownMacIp(context, foundIp)
            return@withContext foundIp
        }

        return@withContext current // Fallback to last known if scan didn't find (e.g. timeout)
    }

    private fun isMacReceiverReachable(ip: String): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(ip, MAC_RECEIVER_PORT), 400)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun scanSubnetForReceiver(prefix: String): String? = withContext(Dispatchers.IO) {
        val candidates = (1..254).toList()
        var resolved: String? = null

        coroutineScope {
            // Parallel sweep in chunks of 32
            for (chunk in candidates.chunked(32)) {
                val jobs = chunk.map { hostNum ->
                    val targetIp = "$prefix$hostNum"
                    async {
                        if (isMacReceiverReachable(targetIp)) targetIp else null
                    }
                }
                for (job in jobs) {
                    val ip = job.await()
                    if (ip != null) {
                        resolved = ip
                        break
                    }
                }
                if (resolved != null) break
            }
        }
        resolved
    }

    suspend fun sendMultipleUrisToMac(
        context: Context,
        uris: List<Uri>,
        macIp: String,
        targetSubfolder: String = "Downloads"
    ): Int = withContext(Dispatchers.IO) {
        var count = 0
        for (uri in uris) {
            val success = sendUriToMac(context, uri, macIp, targetSubfolder)
            if (success) count++
        }
        count
    }

    suspend fun sendUriToMac(
        context: Context,
        uri: Uri,
        macIp: String,
        targetSubfolder: String = "Downloads"
    ): Boolean = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        var fileName = "file_${System.currentTimeMillis()}"
        var fileSize = -1L
        val mimeType = resolver.getType(uri) ?: "application/octet-stream"

        try {
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        fileName = cursor.getString(nameIndex) ?: fileName
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex != -1) {
                        fileSize = cursor.getLong(sizeIndex)
                    }
                }
            }
        } catch (_: Exception) {}

        if (fileSize <= 0) {
            try {
                resolver.openFileDescriptor(uri, "r")?.use { pfd ->
                    fileSize = pfd.statSize
                }
            } catch (_: Exception) {}
        }

        _outgoingTransfer.value = OutgoingTransferState(fileName, fileSize, 0, 0.0)

        var connection: HttpURLConnection? = null
        try {
            val url = URL("http://$macIp:$MAC_RECEIVER_PORT/api/v1/receive")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 6000
                readTimeout = 60000
                setRequestProperty("X-File-Name", URLEncoder.encode(fileName, "UTF-8"))
                setRequestProperty("X-File-Size", fileSize.toString())
                setRequestProperty("X-File-Type", mimeType)
                setRequestProperty("X-Target-Folder", targetSubfolder)
                if (fileSize > 0) {
                    setFixedLengthStreamingMode(fileSize)
                } else {
                    setChunkedStreamingMode(65536)
                }
            }

            val inputStream = resolver.openInputStream(uri) ?: throw IllegalStateException("Cannot open input stream for $uri")
            val outputStream: OutputStream = connection.outputStream

            val buffer = ByteArray(65536)
            var bytesWritten = 0L
            var lastTime = System.currentTimeMillis()
            var bytesSinceLast = 0L

            inputStream.use { input ->
                outputStream.use { output ->
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        bytesWritten += bytesRead
                        bytesSinceLast += bytesRead

                        val now = System.currentTimeMillis()
                        val elapsed = now - lastTime
                        if (elapsed >= 300) {
                            val speed = (bytesSinceLast * 1000.0) / elapsed
                            _outgoingTransfer.value = OutgoingTransferState(
                                fileName = fileName,
                                fileSize = fileSize,
                                bytesSent = bytesWritten,
                                speedBytesPerSec = speed
                            )
                            lastTime = now
                            bytesSinceLast = 0L
                        }
                    }
                    output.flush()
                }
            }

            val respCode = connection.responseCode
            if (respCode == 200) {
                _outgoingTransfer.value = OutgoingTransferState(
                    fileName = fileName,
                    fileSize = fileSize,
                    bytesSent = fileSize,
                    speedBytesPerSec = 0.0,
                    isFinished = true
                )
                Log.i(TAG, "Successfully sent $fileName to Mac ($macIp)")
                return@withContext true
            } else {
                throw IllegalStateException("Mac returned HTTP $respCode")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send $fileName to Mac: ${e.message}")
            _outgoingTransfer.value = OutgoingTransferState(
                fileName = fileName,
                fileSize = fileSize,
                bytesSent = 0,
                speedBytesPerSec = 0.0,
                error = e.message ?: "Transfer failed"
            )
            return@withContext false
        } finally {
            connection?.disconnect()
        }
    }

    suspend fun backupRecentCameraPhotos(context: Context, macIp: String): Int = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_ADDED
        )
        val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
        var syncedCount = 0

        try {
            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                var count = 0
                while (cursor.moveToNext() && count < 25) { // Sync up to 25 recent photos
                    count++
                    val id = cursor.getLong(idColumn)
                    val contentUri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id.toString())
                    val success = sendUriToMac(context, contentUri, macIp, targetSubfolder = "Pictures/Camera")
                    if (success) syncedCount++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during camera backup: ${e.message}")
        }

        return@withContext syncedCount
    }
}
