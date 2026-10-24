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

    override fun onCleared() {
        super.onCleared()
        if (_isServiceBound.value) {
            try {
                getApplication<Application>().unbindService(serviceConnection)
            } catch (_: Exception) {}
        }
    }
}
