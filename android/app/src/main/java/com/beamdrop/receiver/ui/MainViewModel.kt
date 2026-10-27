package com.beamdrop.receiver.ui

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.IBinder
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.beamdrop.receiver.ai.AiQuestionItem
import com.beamdrop.receiver.ai.GeminiApiService
import com.beamdrop.receiver.model.ActiveTransferState
import com.beamdrop.receiver.model.BatteryInfo
import com.beamdrop.receiver.model.MediaActionPayload
import com.beamdrop.receiver.model.PairedDevice
import com.beamdrop.receiver.model.RemoteInputPayload
import com.beamdrop.receiver.model.TransferRecord
import com.beamdrop.receiver.security.PairingManager
import com.beamdrop.receiver.service.FileReceiverForegroundService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val pairingManager = PairingManager(application)

    private val _isServiceBound = MutableStateFlow(false)
    val isServiceBound = _isServiceBound.asStateFlow()

    private val _isServerRunning = MutableStateFlow(false)
    val isServerRunning = _isServerRunning.asStateFlow()

    private val _serverIp = MutableStateFlow("127.0.0.1")
    val serverIp = _serverIp.asStateFlow()

    private val _activeTransfer = MutableStateFlow<ActiveTransferState?>(null)
    val activeTransfer = _activeTransfer.asStateFlow()

    private val _transferHistory = MutableStateFlow<List<TransferRecord>>(emptyList())
    val transferHistory = _transferHistory.asStateFlow()

    private val _pairedDevices = MutableStateFlow<List<PairedDevice>>(emptyList())
    val pairedDevices = _pairedDevices.asStateFlow()

    val deviceName: String = pairingManager.deviceName

    private val _activePin = MutableStateFlow(pairingManager.getActivePin())
    val activePin = _activePin.asStateFlow()

    private val _lastClipboard = MutableStateFlow<String?>(null)
    val lastClipboard = _lastClipboard.asStateFlow()

    private val _tabletBattery = MutableStateFlow<BatteryInfo?>(null)
    val tabletBattery = _tabletBattery.asStateFlow()

    private val _macBattery = MutableStateFlow<BatteryInfo?>(null)
    val macBattery = _macBattery.asStateFlow()

    private val _isRinging = MutableStateFlow(false)
    val isRinging = _isRinging.asStateFlow()

    private val geminiApiService = GeminiApiService(application)

    private val _geminiApiKey = MutableStateFlow(geminiApiService.getApiKey())
    val geminiApiKey = _geminiApiKey.asStateFlow()

    private val _currentAiQuestion = MutableStateFlow<AiQuestionItem?>(null)
    val currentAiQuestion = _currentAiQuestion.asStateFlow()

    private val _aiQuestionHistory = MutableStateFlow<List<AiQuestionItem>>(emptyList())
    val aiQuestionHistory = _aiQuestionHistory.asStateFlow()

    private val _isAiSolving = MutableStateFlow(false)
    val isAiSolving = _isAiSolving.asStateFlow()

    val outgoingTransfer = com.beamdrop.receiver.service.FileSenderManager.outgoingTransfer
    val targetMacIp = com.beamdrop.receiver.service.FileSenderManager.lastKnownMacIp

    private val _backupStatus = MutableStateFlow<String?>(null)
    val backupStatus = _backupStatus.asStateFlow()

    private var service: FileReceiverForegroundService? = null

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val localBinder = binder as FileReceiverForegroundService.LocalBinder
            val svc = localBinder.getService()
            service = svc
            _isServiceBound.value = true

            viewModelScope.launch {
                svc.isServerRunning.collect { _isServerRunning.value = it }
            }
            viewModelScope.launch {
                svc.serverIp.collect { _serverIp.value = it }
            }
            viewModelScope.launch {
                svc.activeTransfer.collect { _activeTransfer.value = it }
            }
            viewModelScope.launch {
                svc.transferHistory.collect { _transferHistory.value = it }
            }
            viewModelScope.launch {
                svc.lastClipboardSynced.collect { _lastClipboard.value = it }
            }
            viewModelScope.launch {
                svc.tabletBattery.collect { _tabletBattery.value = it }
            }
            viewModelScope.launch {
                svc.macBattery.collect { _macBattery.value = it }
            }
            viewModelScope.launch {
                svc.isRinging.collect { _isRinging.value = it }
            }
            viewModelScope.launch {
                svc.currentAiQuestion.collect { _currentAiQuestion.value = it }
            }
            viewModelScope.launch {
                svc.aiQuestionHistory.collect { _aiQuestionHistory.value = it }
            }
            viewModelScope.launch {
                svc.isAiSolving.collect { _isAiSolving.value = it }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            _isServiceBound.value = false
        }
    }

    init {
        loadPairedDevices()
        bindService()
    }

    fun bindService() {
        val intent = Intent(getApplication(), FileReceiverForegroundService::class.java)
        getApplication<Application>().startForegroundService(intent)
        getApplication<Application>().bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    fun startReceiver() {
        val intent = Intent(getApplication(), FileReceiverForegroundService::class.java)
        getApplication<Application>().startForegroundService(intent)
    }

    fun stopReceiver() {
        service?.stopServer()
    }

    fun syncClipboardNow() {
        service?.syncCurrentClipboardToMac()
    }

    // MARK: - KDE Connect Remote Control Actions

    fun sendTrackpadMove(dx: Float, dy: Float) {
        service?.sendRemoteInput(RemoteInputPayload(type = "move", dx = dx, dy = dy))
    }

    fun sendTrackpadClick(button: String = "left") {
        service?.sendRemoteInput(RemoteInputPayload(type = "click", button = button))
    }

    fun sendTrackpadScroll(dy: Float) {
        service?.sendRemoteInput(RemoteInputPayload(type = "scroll", dy = dy))
    }

    fun sendKey(key: String) {
        service?.sendRemoteInput(RemoteInputPayload(type = "key", key = key))
    }

    fun sendTypedText(text: String) {
        service?.sendRemoteInput(RemoteInputPayload(type = "text", text = text))
    }

    fun sendMediaAction(action: String, volume: Float? = null) {
        service?.sendMediaAction(MediaActionPayload(action = action, volume = volume))
    }

    fun sendRemoteCommand(commandId: String) {
        service?.sendRemoteCommand(commandId)
    }

    fun sendRingMac() {
        service?.sendRingMac()
    }

    fun stopTabletRinging() {
        service?.stopTabletRinging()
    }

    fun openUrlOnMac(url: String) {
        service?.openUrlOnMac(url)
    }

    fun refreshPin() {
        _activePin.value = pairingManager.refreshPin()
    }

    fun getQrCodePayload(): String {
        return pairingManager.getQrCodePayload(_serverIp.value, FileReceiverForegroundService.PORT)
    }

    fun loadPairedDevices() {
        _pairedDevices.value = pairingManager.getPairedDevices()
    }

    fun revokeDevice(deviceId: String) {
        pairingManager.revokeDevice(deviceId)
        loadPairedDevices()
    }

    fun openFile(record: TransferRecord) {
        val uriStr = record.uri ?: return
        try {
            val uri = Uri.parse(uriStr)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, record.mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            getApplication<Application>().startActivity(intent)
        } catch (_: Exception) {}
    }

    fun sendFilesToMac(uris: List<Uri>) {
        viewModelScope.launch {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value)
            if (mac.isNullOrEmpty()) {
                _backupStatus.value = "Error: Mac receiver not detected on subnet"
                return@launch
            }
            com.beamdrop.receiver.service.FileSenderManager.sendMultipleUrisToMac(app, uris, mac)
        }
    }

    fun backupCameraPhotos() {
        viewModelScope.launch {
            val app = getApplication<Application>()
            _backupStatus.value = "Backing up photos to Mac..."
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value)
            if (mac.isNullOrEmpty()) {
                _backupStatus.value = "Error: Mac receiver not found on subnet"
                return@launch
            }
            val count = com.beamdrop.receiver.service.FileSenderManager.backupRecentCameraPhotos(app, mac)
            _backupStatus.value = "Successfully synced $count photos to Mac!"
        }
    }

    fun setTargetMacIp(ip: String) {
        com.beamdrop.receiver.service.FileSenderManager.setLastKnownMacIp(getApplication(), ip)
    }

    fun sendSketchBytesToMac(bytes: ByteArray, targetFolder: String, callback: (Boolean) -> Unit) {
        viewModelScope.launch {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value)
            if (mac.isNullOrEmpty()) {
                callback(false)
                return@launch
            }
            val fileName = "Sketch_${System.currentTimeMillis()}.png"
            val success = com.beamdrop.receiver.service.FileSenderManager.sendBytesToMac(bytes, fileName, mac, targetFolder)
            callback(success)
        }
    }

    fun sendScreenTouch(normX: Float, normY: Float, type: String = "click") {
        viewModelScope.launch {
            val mac = com.beamdrop.receiver.service.FileSenderManager.lastKnownMacIp.value ?: return@launch
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val url = java.net.URL("http://$mac:8768/api/v1/screen/touch")
                    val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                        requestMethod = "POST"
                        doOutput = true
                        connectTimeout = 1000
                        readTimeout = 1000
                        setRequestProperty("Content-Type", "application/json")
                    }
                    val json = "{\"x\":$normX,\"y\":$normY,\"type\":\"$type\"}"
                    conn.outputStream.write(json.toByteArray())
                    conn.responseCode
                    conn.disconnect()
                } catch (_: Exception) {}
            }
        }
    }

    fun unlockMacBiometric(callback: (Boolean) -> Unit) {
        viewModelScope.launch {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value)
            if (mac.isNullOrEmpty()) {
                callback(false)
                return@launch
            }
            val token = pairingManager.serverAuthToken
            val success = com.beamdrop.receiver.service.FileSenderManager.requestMacUnlock(mac, token)
            callback(success)
        }
    }

    fun saveGeminiApiKey(key: String) {
        geminiApiService.saveApiKey(key)
        _geminiApiKey.value = key.trim()
    }

    fun retryAiSolve(item: AiQuestionItem) {
        service?.retryAiSolve(item)
    }

    fun askAiFollowUp(item: AiQuestionItem, followUp: String) {
        service?.askAiFollowUp(item, followUp)
    }

    fun selectAiQuestion(item: AiQuestionItem) {
        service?.selectAiQuestion(item)
    }

    fun sendClipboardTextToMac(text: String) {
        service?.syncTextToMac(text)
    }

    // MARK: - Wireless ADB & Custom Script Launchers & Webcam

    data class MacScriptItem(
        val id: String,
        val name: String,
        val command: String,
        val icon: String
    )

    private val _macScripts = MutableStateFlow<List<MacScriptItem>>(emptyList())
    val macScripts = _macScripts.asStateFlow()

    private val _scriptOutput = MutableStateFlow<String>("")
    val scriptOutput = _scriptOutput.asStateFlow()

    private val _isRunningScript = MutableStateFlow(false)
    val isRunningScript = _isRunningScript.asStateFlow()

    fun fetchMacScripts() {
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value) ?: return@launch
            try {
                val url = java.net.URL("http://$mac:8768/api/v1/scripts/list")
                val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                    connectTimeout = 3000
                    readTimeout = 3000
                }
                if (conn.responseCode == 200) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    val array = org.json.JSONArray(body)
                    val list = mutableListOf<MacScriptItem>()
                    for (i in 0 until array.length()) {
                        val obj = array.getJSONObject(i)
                        list.add(
                            MacScriptItem(
                                id = obj.getString("id"),
                                name = obj.getString("name"),
                                command = obj.getString("command"),
                                icon = obj.optString("icon", "⚡")
                            )
                        )
                    }
                    _macScripts.value = list
                }
                conn.disconnect()
            } catch (e: Exception) {
                android.util.Log.e("MainViewModel", "Failed to fetch scripts: ${e.message}")
            }
        }
    }

    fun runMacScript(id: String) {
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value) ?: return@launch
            _isRunningScript.value = true
            _scriptOutput.value = "Executing script on Mac ($mac)..."
            try {
                val url = java.net.URL("http://$mac:8768/api/v1/scripts/run")
                val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 30000
                    setRequestProperty("Content-Type", "application/json")
                }
                val reqBody = org.json.JSONObject().apply { put("id", id) }.toString()
                conn.outputStream.write(reqBody.toByteArray())
                val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
                val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
                val json = if (body.isNotEmpty()) org.json.JSONObject(body) else org.json.JSONObject()
                val out = json.optString("output", body)
                val code = json.optInt("exitCode", conn.responseCode)
                _scriptOutput.value = "Exit Code: $code\n\n$out"
                conn.disconnect()
            } catch (e: Exception) {
                _scriptOutput.value = "Execution error: ${e.message}"
            } finally {
                _isRunningScript.value = false
            }
        }
    }

    fun createMacScript(name: String, command: String, icon: String) {
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value) ?: return@launch
            try {
                val url = java.net.URL("http://$mac:8768/api/v1/scripts/save")
                val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 3000
                    readTimeout = 3000
                    setRequestProperty("Content-Type", "application/json")
                }
                val reqBody = org.json.JSONObject().apply {
                    put("name", name)
                    put("command", command)
                    put("icon", icon)
                }.toString()
                conn.outputStream.write(reqBody.toByteArray())
                conn.responseCode
                conn.disconnect()
                fetchMacScripts()
            } catch (e: Exception) {
                android.util.Log.e("MainViewModel", "Failed to save script: ${e.message}")
            }
        }
    }

    private val _adbStatus = MutableStateFlow<String>("")
    val adbStatus = _adbStatus.asStateFlow()
    private val _isAdbConnecting = MutableStateFlow(false)
    val isAdbConnecting = _isAdbConnecting.asStateFlow()

    fun connectMacAdb(pairingPort: Int? = null, pairingCode: String? = null) {
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val app = getApplication<Application>()
            val mac = com.beamdrop.receiver.service.FileSenderManager.resolveTargetMac(app, _serverIp.value) ?: return@launch
            _isAdbConnecting.value = true
            _adbStatus.value = "Connecting Mac ADB to ${_serverIp.value}..."
            try {
                val url = java.net.URL("http://$mac:8768/api/v1/adb/connect")
                val conn = (url.openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 15000
                    setRequestProperty("Content-Type", "application/json")
                }
                val req = org.json.JSONObject().apply {
                    put("host", _serverIp.value)
                    put("port", 5555)
                    if (pairingPort != null && !pairingCode.isNullOrEmpty()) {
                        put("pairingPort", pairingPort)
                        put("pairingCode", pairingCode)
                    }
                }
                conn.outputStream.write(req.toString().toByteArray())
                val stream = if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream
                val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
                val json = if (body.isNotEmpty()) org.json.JSONObject(body) else org.json.JSONObject()
                val msg = json.optString("message", body)
                _adbStatus.value = msg
                conn.disconnect()
            } catch (e: Exception) {
                _adbStatus.value = "ADB Connect failed: ${e.message}"
            } finally {
                _isAdbConnecting.value = false
            }
        }
    }

    val isWebcamStreaming = com.beamdrop.receiver.camera.WebcamManager.isStreaming
    val isWebcamBackCamera = com.beamdrop.receiver.camera.WebcamManager.isBackCamera
    val isWebcamTorchOn = com.beamdrop.receiver.camera.WebcamManager.isTorchOn
    val webcamFps = com.beamdrop.receiver.camera.WebcamManager.fps

    fun startWebcam() {
        com.beamdrop.receiver.camera.WebcamManager.startStreaming(getApplication())
    }

    fun stopWebcam() {
        com.beamdrop.receiver.camera.WebcamManager.stopStreaming()
    }

    fun toggleWebcamCamera() {
        com.beamdrop.receiver.camera.WebcamManager.toggleCamera(getApplication())
    }

    fun toggleWebcamTorch() {
        com.beamdrop.receiver.camera.WebcamManager.toggleTorch(getApplication())
    }

    override fun onCleared() {
        super.onCleared()
        if (_isServiceBound.value) {
            try {
                getApplication<Application>().unbindService(serviceConnection)
            } catch (_: Exception) {}
        }
    }
}
