package com.beamdrop.receiver.server

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import android.util.Log
import com.beamdrop.receiver.model.ActiveTransferState
import com.beamdrop.receiver.model.InitTransferRequest
import com.beamdrop.receiver.model.MediaActionPayload
import com.beamdrop.receiver.model.MirroredNotification
import com.beamdrop.receiver.model.RemoteInputPayload
import com.beamdrop.receiver.model.TransferRecord
import com.beamdrop.receiver.security.PairingManager
import com.beamdrop.receiver.storage.MediaStoreSaver
import com.beamdrop.receiver.storage.StorageResolver
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.FilterInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

class BeamDropServer(
    private val context: Context,
    private val pairingManager: PairingManager,
    private val port: Int = 8765,
    private val onTransferProgress: (ActiveTransferState) -> Unit,
    private val onTransferComplete: (TransferRecord) -> Unit,
    private val onTransferError: (String, String) -> Unit,
    private val onClipboardReceived: (String) -> Unit,
    private val onRingRequested: () -> Unit = {},
    private val onRingStopRequested: () -> Unit = {},
    private val onOpenUrl: (String) -> Unit = {},
    private val onMacBatteryReceived: (Int, Boolean) -> Unit = { _, _ -> }
) {
    private var serverSocket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()
    private val mediaStoreSaver = MediaStoreSaver(context)
    private val pendingTransfers = ConcurrentHashMap<String, InitTransferRequest>()
    private val sseClients = CopyOnWriteArrayList<OutputStream>()
    private var isRunning = false

    companion object {
        private const val TAG = "BeamDropServer"
    }

    fun start() {
        if (isRunning) return
        isRunning = true

        try {
            val ss = ServerSocket(port)
            this.serverSocket = ss

            executor.execute {
                while (isRunning && !ss.isClosed) {
                    try {
                        val clientSocket = ss.accept()
                        executor.execute { handleClient(clientSocket) }
                    } catch (e: Exception) {
                        if (isRunning) {
                            Log.e(TAG, "Accept error: ${e.message}")
                        }
                    }
                }
            }
            Log.i(TAG, "BeamDrop Server started on port $port")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start server on port $port: ${e.message}")
        }
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null

        for (client in sseClients) {
            try { client.close() } catch (_: Exception) {}
        }
        sseClients.clear()
        executor.shutdownNow()
        Log.i(TAG, "BeamDrop Server stopped")
    }

    // MARK: - SSE Broadcasting (KDE Connect Events)

    fun broadcastEvent(eventType: String, json: JSONObject) {
        val ssePayload = "event: $eventType\ndata: ${json}\n\n"
        val bytes = ssePayload.toByteArray(Charsets.UTF_8)

        val iterator = sseClients.iterator()
        while (iterator.hasNext()) {
            val clientOut = iterator.next()
            executor.execute {
                try {
                    synchronized(clientOut) {
                        clientOut.write(bytes)
                        clientOut.flush()
                    }
                } catch (e: Exception) {
                    sseClients.remove(clientOut)
                }
            }
        }
    }

    fun broadcastClipboard(text: String) {
        val json = JSONObject().apply {
            put("text", text)
            put("timestamp", System.currentTimeMillis())
            put("source", "tablet")
        }
        broadcastEvent("clipboard", json)
    }

    fun broadcastBattery(percentage: Int, isCharging: Boolean) {
        val json = JSONObject().apply {
            put("percentage", percentage)
            put("isCharging", isCharging)
            put("source", "tablet")
            put("timestamp", System.currentTimeMillis())
        }
        broadcastEvent("battery", json)
    }

    fun broadcastRemoteInput(payload: RemoteInputPayload) {
        val json = JSONObject().apply {
            put("type", payload.type)
            put("dx", payload.dx.toDouble())
            put("dy", payload.dy.toDouble())
            payload.button?.let { put("button", it) }
            payload.key?.let { put("key", it) }
            payload.text?.let { put("text", it) }
        }
        broadcastEvent("remote_input", json)
    }

    fun broadcastMediaAction(payload: MediaActionPayload) {
        val json = JSONObject().apply {
            put("action", payload.action)
            payload.volume?.let { put("volume", it.toDouble()) }
        }
        broadcastEvent("media", json)
    }

    fun broadcastRemoteCommand(commandId: String) {
        val json = JSONObject().apply {
            put("commandId", commandId)
        }
        broadcastEvent("command", json)
    }

    fun broadcastRingMac() {
        val json = JSONObject().apply {
            put("action", "start")
        }
        broadcastEvent("ring_mac", json)
    }

    fun broadcastNotification(notif: MirroredNotification) {
        val json = JSONObject().apply {
            put("id", notif.id)
            put("appName", notif.appName)
            put("title", notif.title)
            put("text", notif.text)
            put("timestamp", notif.timestamp)
            put("key", notif.key)
            put("canReply", notif.canReply)
        }
        broadcastEvent("notification", json)
    }

    fun broadcastOpenUrlOnMac(url: String) {
        val json = JSONObject().apply {
            put("url", url)
        }
        broadcastEvent("open_url_on_mac", json)
    }

    // MARK: - Client Handler

    private fun handleClient(socket: Socket) {
        var isSseConnection = false
        try {
            socket.tcpNoDelay = true
            val remoteIp = socket.inetAddress?.hostAddress
            if (!remoteIp.isNullOrEmpty() && remoteIp != "127.0.0.1" && !remoteIp.startsWith("::")) {
                com.beamdrop.receiver.service.FileSenderManager.setLastKnownMacIp(context, remoteIp)
            }

            val input = socket.getInputStream()
            val output = socket.getOutputStream()

            // 1. Read Request Line
            val requestLine = readLine(input) ?: return
            val parts = requestLine.split(" ")
            if (parts.size < 2) return

            val method = parts[0].uppercase(Locale.ROOT)
            val fullUri = parts[1]
            val path = fullUri.substringBefore('?')
            val queryString = if (fullUri.contains('?')) fullUri.substringAfter('?') else ""

            // 2. Read Headers
            val headers = mutableMapOf<String, String>()
            while (true) {
                val headerLine = readLine(input) ?: break
                if (headerLine.isEmpty()) break
                val colonIdx = headerLine.indexOf(':')
                if (colonIdx > 0) {
                    val key = headerLine.substring(0, colonIdx).trim().lowercase(Locale.ROOT)
                    val value = headerLine.substring(colonIdx + 1).trim()
                    headers[key] = value
                }
            }

            // 3. Dispatch Handlers
            when {
                method == "GET" && path == "/api/v1/ping" -> {
                    handlePing(output)
                }
                method == "POST" && path == "/api/v1/pair" -> {
                    handlePair(input, output, headers)
                }
                method == "POST" && path == "/api/v1/transfer/init" -> {
                    handleTransferInit(input, output, headers)
                }
                method == "POST" && path == "/api/v1/transfer/upload" -> {
                    handleTransferUpload(input, output, headers, queryString)
                }
                method == "POST" && path == "/api/v1/clipboard" -> {
                    handleClipboardPost(input, output, headers)
                }
                method == "GET" && (path == "/api/v1/events" || path == "/api/v1/clipboard/events") -> {
                    isSseConnection = handleEventsStream(output, headers, socket)
                }
                method == "POST" && path == "/api/v1/ring" -> {
                    handleRing(output, headers)
                }
                method == "POST" && path == "/api/v1/ring/stop" -> {
                    handleRingStop(output, headers)
                }
                method == "POST" && path == "/api/v1/open-url" -> {
                    handleOpenUrl(input, output, headers)
                }
                method == "POST" && path == "/api/v1/mac/battery" -> {
                    handleMacBattery(input, output, headers)
                }
                method == "POST" && path == "/api/v1/tablet/action" -> {
                    handleTabletAction(input, output, headers)
                }
                method == "POST" && path == "/api/v1/notifications/reply" -> {
                    handleNotificationReply(input, output, headers)
                }
                method == "GET" && path == "/api/v1/camera/snapshot" -> {
                    handleCameraSnapshot(output, headers)
                }
                method == "POST" && path == "/api/v1/unpair" -> {
                    handleUnpair(input, output, headers)
                }
                else -> {
                    writeResponse(output, 404, "Not Found", "application/json", "{\"error\":\"Not Found\"}".toByteArray())
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling client request: ${e.message}")
        } finally {
            if (!isSseConnection) {
                try {
                    socket.close()
                } catch (_: Exception) {}
            }
        }
    }

    // MARK: - Handlers

    private fun handlePing(output: OutputStream) {
        val stat = StatFs(Environment.getDataDirectory().path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong

        // Read tablet battery info
        val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        val json = JSONObject().apply {
            put("status", "ONLINE")
            put("version", 1)
            put("deviceId", pairingManager.getReceiverId())
            put("deviceName", PairingManager.DEVICE_NAME)
            put("deviceType", "tablet")
            put("freeSpaceBytes", freeBytes)
            put("isServiceActive", true)
            put("supportsClipboardSync", true)
            put("batteryPercentage", batteryPct)
            put("isCharging", isCharging)
            put("features", JSONArray(listOf(
                "clipboard",
                "remote_input",
                "media_control",
                "remote_commands",
                "presentation",
                "ring",
                "battery",
                "notifications",
                "open_url"
            )))
        }
        writeJsonResponse(output, 200, "OK", json)
    }

    private fun handleRing(output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }
        onRingRequested()
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "RINGING") })
    }

    private fun handleRingStop(output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }
        onRingStopRequested()
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "STOPPED") })
    }

    private fun handleOpenUrl(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)
        val url = reqJson.optString("url", "")
        if (url.isNotEmpty()) {
            onOpenUrl(url)
        }
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "OPENED") })
    }

    private fun handleMacBattery(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)
        val pct = reqJson.optInt("percentage", 100)
        val isCharging = reqJson.optBoolean("isCharging", false)
        onMacBatteryReceived(pct, isCharging)
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "SAVED") })
    }

    private fun handleTabletAction(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)
        val eventType = reqJson.optString("eventType", "")
        val data = reqJson.optJSONObject("data") ?: JSONObject()
        if (eventType.isNotEmpty()) {
            broadcastEvent(eventType, data)
        }
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "BROADCASTED") })
    }

    private fun handleClipboardPost(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }

        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)
        val text = reqJson.optString("text", "")

        if (text.isNotEmpty()) {
            onClipboardReceived(text)
        }

        val resp = JSONObject().apply {
            put("status", "SYNCED")
            put("timestamp", System.currentTimeMillis())
        }
        writeJsonResponse(output, 200, "OK", resp)
    }

    private fun handleEventsStream(output: OutputStream, headers: Map<String, String>, socket: Socket): Boolean {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return false
        }

        val sseHeader = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: text/event-stream\r\n" +
                "Cache-Control: no-cache\r\n" +
                "Connection: keep-alive\r\n" +
                "Access-Control-Allow-Origin: *\r\n\r\n"
        output.write(sseHeader.toByteArray(Charsets.US_ASCII))
        output.flush()

        sseClients.add(output)
        Log.i(TAG, "New SSE client subscribed to KDE Connect event stream (active=${sseClients.size})")

        // Initial connect event
        val initEvent = "event: connected\ndata: {\"status\":\"CONNECTED\"}\n\n"
        output.write(initEvent.toByteArray(Charsets.UTF_8))
        output.flush()

        // Send current tablet battery info on connect
        val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

        val batteryJson = JSONObject().apply {
            put("percentage", batteryPct)
            put("isCharging", isCharging)
            put("source", "tablet")
        }
        output.write("event: battery\ndata: ${batteryJson}\n\n".toByteArray(Charsets.UTF_8))
        output.flush()

        // Keep SSE connection open with heartbeat
        executor.execute {
            try {
                while (isRunning && !socket.isClosed) {
                    Thread.sleep(15000)
                    synchronized(output) {
                        output.write(": heartbeat\n\n".toByteArray(Charsets.UTF_8))
                        output.flush()
                    }
                }
            } catch (_: Exception) {
            } finally {
                sseClients.remove(output)
                try { socket.close() } catch (_: Exception) {}
            }
        }
        return true
    }

    private fun handlePair(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)

        val senderId = reqJson.optString("senderId", "")
        val senderName = reqJson.optString("senderName", "MacBook Pro")
        val pin = reqJson.optString("pairingSecret", "")
        val clientToken = reqJson.optString("clientAuthToken", "")

        if (!pairingManager.validatePairingPin(pin)) {
            val err = JSONObject().apply { put("error", "Invalid or expired pairing PIN") }
            writeJsonResponse(output, 403, "Forbidden", err)
            return
        }

        pairingManager.addPairedDevice(
            senderId = senderId,
            senderName = senderName,
            clientAuthToken = clientToken
        )

        val resp = JSONObject().apply {
            put("status", "PAIRED")
            put("receiverId", pairingManager.getReceiverId())
            put("receiverName", PairingManager.DEVICE_NAME)
            put("serverAuthToken", pairingManager.serverAuthToken)
        }
        writeJsonResponse(output, 200, "OK", resp)
    }

    private fun handleTransferInit(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            val err = JSONObject().apply { put("error", "Unauthorized: Device not paired") }
            writeJsonResponse(output, 401, "Unauthorized", err)
            return
        }

        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val bodyBytes = readExactBytes(input, contentLength)
        val bodyStr = String(bodyBytes, Charsets.UTF_8)
        val reqJson = JSONObject(bodyStr)

        val req = InitTransferRequest(
            transferId = reqJson.getString("transferId"),
            fileName = reqJson.getString("fileName"),
            fileSize = reqJson.getLong("fileSize"),
            mimeType = reqJson.optString("mimeType", "application/octet-stream"),
            sha256 = reqJson.getString("sha256"),
            timestamp = reqJson.optLong("timestamp", System.currentTimeMillis())
        )

        val stat = StatFs(Environment.getDataDirectory().path)
        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
        if (freeBytes < req.fileSize + (50 * 1024 * 1024)) {
            val err = JSONObject().apply { put("error", "Insufficient storage space on tablet") }
            writeJsonResponse(output, 507, "Insufficient Storage", err)
            return
        }

        val destination = StorageResolver.resolve(req.fileName, req.mimeType)
        val uniqueName = mediaStoreSaver.resolveUniqueFileName(destination, req.fileName)

        pendingTransfers[req.transferId] = req

        val resp = JSONObject().apply {
            put("transferId", req.transferId)
            put("status", "READY")
            put("resolvedFileName", uniqueName)
            put("targetFolder", destination.relativePath)
        }
        writeJsonResponse(output, 200, "OK", resp)
    }

    private fun handleTransferUpload(
        input: InputStream,
        output: OutputStream,
        headers: Map<String, String>,
        queryString: String
    ) {
        val authHeader = headers["authorization"]
        if (!pairingManager.isAuthorized(authHeader)) {
            writeJsonResponse(output, 401, "Unauthorized", JSONObject().apply { put("error", "Unauthorized") })
            return
        }

        val transferId = queryString.split("&")
            .map { it.split("=") }
            .firstOrNull { it.size == 2 && it[0] == "transferId" }
            ?.get(1)

        if (transferId == null || !pendingTransfers.containsKey(transferId)) {
            writeJsonResponse(output, 400, "Bad Request", JSONObject().apply { put("error", "Invalid or expired transferId") })
            return
        }

        val initReq = pendingTransfers.remove(transferId) ?: run {
            writeJsonResponse(output, 400, "Bad Request", JSONObject().apply { put("error", "Transfer request expired") })
            return
        }

        val destination = StorageResolver.resolve(initReq.fileName, initReq.mimeType)
        val totalBytes = initReq.fileSize

        var lastSpeedTime = System.currentTimeMillis()
        var lastBytes: Long = 0
        var currentSpeed: Double = 0.0

        val boundedStream = BoundedInputStream(input, totalBytes)

        try {
            val record = mediaStoreSaver.saveStream(
                transferId = transferId,
                originalName = initReq.fileName,
                totalBytes = totalBytes,
                expectedSha256 = initReq.sha256,
                inputStream = boundedStream,
                onProgress = { bytesReceived, total ->
                    val now = System.currentTimeMillis()
                    val elapsed = (now - lastSpeedTime) / 1000.0
                    if (elapsed >= 0.3) {
                        val delta = bytesReceived - lastBytes
                        val instantSpeed = delta / elapsed
                        currentSpeed = if (currentSpeed == 0.0) instantSpeed else (0.7 * currentSpeed + 0.3 * instantSpeed)
                        lastSpeedTime = now
                        lastBytes = bytesReceived
                    }

                    onTransferProgress(
                        ActiveTransferState(
                            transferId = transferId,
                            fileName = initReq.fileName,
                            totalBytes = total,
                            bytesReceived = bytesReceived,
                            speedBytesPerSec = currentSpeed,
                            isTransferring = true,
                            destinationFolder = destination.relativePath
                        )
                    )
                }
            )

            onTransferComplete(record)

            val resp = JSONObject().apply {
                put("transferId", transferId)
                put("status", "COMPLETED")
                put("fileName", record.fileName)
                put("folder", record.folder)
                put("bytesReceived", record.fileSize)
                put("sha256", record.sha256)
            }
            writeJsonResponse(output, 200, "OK", resp)

        } catch (e: SecurityException) {
            onTransferError(transferId, e.message ?: "Checksum verification failed")
            writeJsonResponse(output, 422, "Unprocessable Entity", JSONObject().apply { put("error", e.message) })
        } catch (e: Exception) {
            onTransferError(transferId, e.message ?: "Transfer failed")
            writeJsonResponse(output, 500, "Internal Server Error", JSONObject().apply { put("error", e.message) })
        }
    }

    private fun handleUnpair(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        if (contentLength > 0) {
            val bodyBytes = readExactBytes(input, contentLength)
            val reqJson = JSONObject(String(bodyBytes, Charsets.UTF_8))
            val senderId = reqJson.optString("senderId", "")
            if (senderId.isNotEmpty()) {
                pairingManager.revokeDevice(senderId)
            }
        }
        writeJsonResponse(output, 200, "OK", JSONObject().apply { put("status", "UNPAIRED") })
    }

    private fun writeJsonResponse(output: OutputStream, statusCode: Int, statusText: String, json: JSONObject) {
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        writeResponse(output, statusCode, statusText, "application/json", bytes)
    }

    private fun handleNotificationReply(input: InputStream, output: OutputStream, headers: Map<String, String>) {
        if (!pairingManager.isAuthorized(headers["authorization"])) {
            writeResponse(output, 401, "Unauthorized", "application/json", "{\"error\":\"Unauthorized\"}".toByteArray())
            return
        }
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        val body = if (contentLength > 0) {
            val bytes = readExactBytes(input, contentLength)
            String(bytes, Charsets.UTF_8)
        } else ""

        try {
            val json = JSONObject(body)
            val key = json.getString("key")
            val replyText = json.getString("replyText")
            val ok = com.beamdrop.receiver.service.BeamDropNotificationListenerService.sendReply(context, key, replyText)
            if (ok) {
                writeResponse(output, 200, "OK", "application/json", "{\"status\":\"SUCCESS\"}".toByteArray())
            } else {
                writeResponse(output, 400, "Bad Request", "application/json", "{\"error\":\"Failed to dispatch reply\"}".toByteArray())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling notification reply: ${e.message}")
            writeResponse(output, 500, "Internal Server Error", "application/json", "{\"error\":\"${e.message}\"}".toByteArray())
        }
    }

    private fun handleCameraSnapshot(output: OutputStream, headers: Map<String, String>) {
        if (!pairingManager.isAuthorized(headers["authorization"])) {
            writeResponse(output, 401, "Unauthorized", "application/json", "{\"error\":\"Unauthorized\"}".toByteArray())
            return
        }
        try {
            var jpegBytes = kotlinx.coroutines.runBlocking {
                com.beamdrop.receiver.camera.CameraHelper.captureSnapshot(context)
            }
            if (jpegBytes == null) {
                // If backgrounded, bring BeamDrop to foreground and retry
                try {
                    val launchIntent = Intent(context, com.beamdrop.receiver.MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    }
                    context.startActivity(launchIntent)
                    Thread.sleep(800)
                    jpegBytes = kotlinx.coroutines.runBlocking {
                        com.beamdrop.receiver.camera.CameraHelper.captureSnapshot(context)
                    }
                } catch (_: Exception) {}
            }
            if (jpegBytes != null && jpegBytes.isNotEmpty()) {
                writeResponse(output, 200, "OK", "image/jpeg", jpegBytes)
            } else {
                writeResponse(output, 503, "Service Unavailable", "application/json", "{\"error\":\"Camera unavailable or permission denied\"}".toByteArray())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Camera snapshot error: ${e.message}")
            writeResponse(output, 500, "Internal Server Error", "application/json", "{\"error\":\"${e.message}\"}".toByteArray())
        }
    }

    private fun writeResponse(output: OutputStream, statusCode: Int, statusText: String, contentType: String, body: ByteArray) {
        val header = "HTTP/1.1 $statusCode $statusText\r\n" +
                "Content-Type: $contentType\r\n" +
                "Content-Length: ${body.size}\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Connection: close\r\n\r\n"
        output.write(header.toByteArray(Charsets.US_ASCII))
        output.write(body)
        output.flush()
    }

    private fun readLine(input: InputStream): String? {
        val baos = ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b == -1) {
                if (baos.size() == 0) return null
                break
            }
            if (b == '\n'.code) {
                break
            }
            if (b != '\r'.code) {
                baos.write(b)
            }
        }
        return baos.toString(Charsets.UTF_8.name())
    }

    private fun readExactBytes(input: InputStream, count: Int): ByteArray {
        val buffer = ByteArray(count)
        var totalRead = 0
        while (totalRead < count) {
            val read = input.read(buffer, totalRead, count - totalRead)
            if (read == -1) break
            totalRead += read
        }
        return buffer
    }

    private class BoundedInputStream(
        private val inner: InputStream,
        private val maxBytes: Long
    ) : FilterInputStream(inner) {
        private var bytesRemaining = maxBytes

        override fun read(): Int {
            if (bytesRemaining <= 0) return -1
            val res = super.read()
            if (res != -1) bytesRemaining--
            return res
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (bytesRemaining <= 0) return -1
            val toRead = minOf(len.toLong(), bytesRemaining).toInt()
            val res = super.read(b, off, toRead)
            if (res > 0) bytesRemaining -= res
            return res
        }
    }
}
