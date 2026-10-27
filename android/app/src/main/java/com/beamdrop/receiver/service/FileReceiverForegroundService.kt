package com.beamdrop.receiver.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.beamdrop.receiver.MainActivity
import com.beamdrop.receiver.ai.AiQuestionItem
import com.beamdrop.receiver.ai.GeminiApiService
import com.beamdrop.receiver.model.ActiveTransferState
import com.beamdrop.receiver.model.BatteryInfo
import com.beamdrop.receiver.model.MediaActionPayload
import com.beamdrop.receiver.model.RemoteInputPayload
import com.beamdrop.receiver.model.TransferRecord
import com.beamdrop.receiver.security.PairingManager
import com.beamdrop.receiver.server.BeamDropServer
import com.beamdrop.receiver.server.NsdHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

class FileReceiverForegroundService : Service() {

    private val binder = LocalBinder()
    private var server: BeamDropServer? = null
    private var nsdHelper: NsdHelper? = null
    private lateinit var pairingManager: PairingManager
    private lateinit var clipboardManager: ClipboardManager
    private lateinit var ringtoneHelper: RingtoneHelper
    private val mainHandler = Handler(Looper.getMainLooper())

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var lastSyncedClipboardText: String? = null

    private val _activeTransfer = MutableStateFlow<ActiveTransferState?>(null)
    val activeTransfer = _activeTransfer.asStateFlow()

    private val _transferHistory = MutableStateFlow<List<TransferRecord>>(emptyList())
    val transferHistory = _transferHistory.asStateFlow()

    private val _isServerRunning = MutableStateFlow(false)
    val isServerRunning = _isServerRunning.asStateFlow()

    private val _serverIp = MutableStateFlow("127.0.0.1")
    val serverIp = _serverIp.asStateFlow()

    private val _lastClipboardSynced = MutableStateFlow<String?>(null)
    val lastClipboardSynced = _lastClipboardSynced.asStateFlow()

    private val _tabletBattery = MutableStateFlow<BatteryInfo?>(null)
    val tabletBattery = _tabletBattery.asStateFlow()

    private val _macBattery = MutableStateFlow<BatteryInfo?>(null)
    val macBattery = _macBattery.asStateFlow()

    lateinit var geminiApiService: GeminiApiService
        private set

    private val _currentAiQuestion = MutableStateFlow<AiQuestionItem?>(null)
    val currentAiQuestion = _currentAiQuestion.asStateFlow()

    private val _aiQuestionHistory = MutableStateFlow<List<AiQuestionItem>>(emptyList())
    val aiQuestionHistory = _aiQuestionHistory.asStateFlow()

    private val _isAiSolving = MutableStateFlow(false)
    val isAiSolving = _isAiSolving.asStateFlow()

    val isRinging get() = ringtoneHelper.isRinging

    companion object {
        private const val TAG = "BeamDropService"
        const val CHANNEL_ID = "beamdrop_receiver_channel"
        const val NOTIFICATION_ID = 8765
        const val PORT = 8765
        const val ACTION_SYNC_CLIPBOARD = "com.beamdrop.receiver.action.SYNC_CLIPBOARD"
        const val ACTION_STOP_RING = "com.beamdrop.receiver.action.STOP_RING"
    }

    private val clipChangedListener = ClipboardManager.OnPrimaryClipChangedListener {
        syncCurrentClipboardToMac()
    }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val pct = if (level >= 0 && scale > 0) (level * 100 / scale) else 100
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

                val info = BatteryInfo(pct, isCharging)
                _tabletBattery.value = info
                server?.broadcastBattery(pct, isCharging)
            }
        }
    }

    inner class LocalBinder : Binder() {
        fun getService(): FileReceiverForegroundService = this@FileReceiverForegroundService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        geminiApiService = GeminiApiService(this)
        pairingManager = PairingManager(this)
        nsdHelper = NsdHelper(this)
        ringtoneHelper = RingtoneHelper(this)
        clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardManager.addPrimaryClipChangedListener(clipChangedListener)

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BeamDrop:TransferWakeLock")

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "BeamDrop:WifiLock")

        // Hook up Notification Listener mirror
        BeamDropNotificationListenerService.onNotificationReceivedListener = { mirrored ->
            server?.broadcastNotification(mirrored)
        }

        // Register battery monitor
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SYNC_CLIPBOARD) {
            syncCurrentClipboardToMac()
            return START_STICKY
        } else if (intent?.action == ACTION_STOP_RING) {
            stopTabletRinging()
            return START_STICKY
        }

        startInForeground()
        startServer()
        return START_STICKY
    }

    // MARK: - Actions triggered from Tablet UI

    fun sendRemoteInput(payload: RemoteInputPayload) {
        server?.broadcastRemoteInput(payload)
    }

    fun sendMediaAction(payload: MediaActionPayload) {
        server?.broadcastMediaAction(payload)
    }

    fun sendRemoteCommand(commandId: String) {
        server?.broadcastRemoteCommand(commandId)
    }

    fun sendRingMac() {
        server?.broadcastRingMac()
    }

    fun stopTabletRinging() {
        ringtoneHelper.stopRinging()
        updateNotification("BeamDrop Active", "Listening on :$PORT • KDE Connect Suite Ready")
    }

    fun openUrlOnMac(url: String) {
        server?.broadcastOpenUrlOnMac(url)
    }

    fun syncTextToMac(text: String) {
        mainHandler.post {
            try {
                val clip = ClipData.newPlainText("Gemini Solution", text)
                clipboardManager.setPrimaryClip(clip)
                lastSyncedClipboardText = text
                _lastClipboardSynced.value = text
                server?.broadcastClipboard(text)
                Log.i(TAG, "Explicitly synced text to Mac clipboard (${text.length} chars)")
            } catch (e: Exception) {
                Log.e(TAG, "Error syncing text to Mac: ${e.message}")
            }
        }
    }

    fun syncCurrentClipboardToMac() {
        mainHandler.post {
            try {
                val clip = clipboardManager.primaryClip
                if (clip != null && clip.itemCount > 0) {
                    val text = clip.getItemAt(0)?.text?.toString()
                    if (!text.isNullOrEmpty() && text != lastSyncedClipboardText) {
                        lastSyncedClipboardText = text
                        _lastClipboardSynced.value = text
                        server?.broadcastClipboard(text)
                        Log.i(TAG, "Synced tablet clipboard to Mac (${text.length} chars)")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking clipboard: ${e.message}")
            }
        }
    }

    private fun startInForeground() {
        val notification = createNotification("BeamDrop Active", "Listening on :$PORT • KDE Connect Suite Ready")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val fgsType = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            startForeground(NOTIFICATION_ID, notification, fgsType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startServer() {
        if (_isServerRunning.value) return

        val ip = getLocalIpAddress()
        _serverIp.value = ip

        server = BeamDropServer(
            context = this,
            pairingManager = pairingManager,
            port = PORT,
            onTransferProgress = { state ->
                _activeTransfer.value = state
                acquireLocks()
                updateNotificationWithProgress(state)
            },
            onTransferComplete = { record ->
                _activeTransfer.value = null
                val updated = _transferHistory.value.toMutableList()
                updated.add(0, record)
                _transferHistory.value = updated
                releaseLocks()
                updateNotification(
                    "Received ${record.fileName}",
                    "Saved to ${record.folder} • ${record.destinationType}"
                )
            },
            onTransferError = { _, error ->
                _activeTransfer.value = null
                releaseLocks()
                updateNotification("Transfer Failed", error)
            },
            onClipboardReceived = { text ->
                mainHandler.post {
                    try {
                        lastSyncedClipboardText = text
                        _lastClipboardSynced.value = text
                        val clip = ClipData.newPlainText("BeamDrop", text)
                        clipboardManager.setPrimaryClip(clip)
                        val preview = if (text.length > 40) text.take(40) + "..." else text
                        updateNotification("📋 Synced from MacBook", preview)
                        Log.i(TAG, "Updated tablet clipboard from Mac: $preview")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error setting clipboard: ${e.message}")
                    }
                }
            },
            onRingRequested = {
                mainHandler.post {
                    ringtoneHelper.startRinging()
                    updateNotificationWithRing()
                }
            },
            onRingStopRequested = {
                mainHandler.post {
                    stopTabletRinging()
                }
            },
            onOpenUrl = { url ->
                mainHandler.post {
                    try {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(browserIntent)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening URL: ${e.message}")
                    }
                }
            },
            onMacBatteryReceived = { pct, isCharging ->
                _macBattery.value = BatteryInfo(pct, isCharging)
            },
            onAiSolveRequested = { file, fileName ->
                handleIncomingAiQuestion(file, fileName)
            }
        )

        server?.start()
        nsdHelper?.registerService(PORT)
        _isServerRunning.value = true

        updateNotification("BeamDrop Active", "Ready on $ip:$PORT • KDE Connect Suite Ready")
    }

    fun stopServer() {
        server?.stop()
        server = null
        nsdHelper?.unregisterService()
        _isServerRunning.value = false
        ringtoneHelper.stopRinging()
        releaseLocks()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    fun handleIncomingAiQuestion(file: File, fileName: String) {
        val questionItem = AiQuestionItem(
            imagePath = file.absolutePath,
            fileName = fileName,
            isSolving = true
        )
        _currentAiQuestion.value = questionItem
        _isAiSolving.value = true
        updateNotification("🤖 Solving Question with Gemini...", fileName)

        CoroutineScope(Dispatchers.IO).launch {
            val result = geminiApiService.solveQuestionFromImage(file)
            withContext(Dispatchers.Main) {
                _isAiSolving.value = false
                val updated = questionItem.copy(
                    isSolving = false,
                    solutionMarkdown = result.solutionText,
                    errorMessage = result.errorMessage
                )
                _currentAiQuestion.value = updated
                val history = _aiQuestionHistory.value.toMutableList()
                history.add(0, updated)
                _aiQuestionHistory.value = history

                if (result.success) {
                    updateNotification("✅ Question Solved by Gemini!", fileName)
                } else {
                    updateNotification("⚠️ Gemini Solve Failed", result.errorMessage ?: "Error")
                }
            }
        }
    }

    fun retryAiSolve(item: AiQuestionItem) {
        val file = File(item.imagePath)
        if (!file.exists()) return
        _isAiSolving.value = true
        _currentAiQuestion.value = item.copy(isSolving = true, errorMessage = null)

        CoroutineScope(Dispatchers.IO).launch {
            val result = geminiApiService.solveQuestionFromImage(file)
            withContext(Dispatchers.Main) {
                _isAiSolving.value = false
                val updated = item.copy(
                    isSolving = false,
                    solutionMarkdown = result.solutionText,
                    errorMessage = result.errorMessage
                )
                _currentAiQuestion.value = updated
            }
        }
    }

    fun askAiFollowUp(item: AiQuestionItem, followUp: String) {
        val file = File(item.imagePath)
        if (!file.exists()) return
        _isAiSolving.value = true

        CoroutineScope(Dispatchers.IO).launch {
            val result = geminiApiService.askFollowUp(file, item.solutionMarkdown ?: "", followUp)
            withContext(Dispatchers.Main) {
                _isAiSolving.value = false
                if (result.success) {
                    val combined = (item.solutionMarkdown ?: "") + "\n\n---\n### 💬 Follow-Up\n**Q: $followUp**\n\n" + (result.solutionText ?: "")
                    val updated = item.copy(solutionMarkdown = combined)
                    _currentAiQuestion.value = updated
                } else {
                    val updated = item.copy(errorMessage = result.errorMessage)
                    _currentAiQuestion.value = updated
                }
            }
        }
    }

    fun selectAiQuestion(item: AiQuestionItem) {
        _currentAiQuestion.value = item
    }

    private fun acquireLocks() {
        if (wakeLock?.isHeld != true) wakeLock?.acquire(30 * 60 * 1000L) // 30 min max
        if (wifiLock?.isHeld != true) wifiLock?.acquire()
    }

    private fun releaseLocks() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        if (wifiLock?.isHeld == true) wifiLock?.release()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "BeamDrop Transfers & KDE Connect",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active local Wi-Fi KDE Connect services and file transfers"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(title: String, content: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val syncIntent = Intent(this, FileReceiverForegroundService::class.java).apply {
            action = ACTION_SYNC_CLIPBOARD
        }
        val syncPendingIntent = PendingIntent.getService(
            this, 1, syncIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_send, "📋 Sync Clip to Mac", syncPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(title: String, content: String) {
        val notification = createNotification(title, content)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun updateNotificationWithRing() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, FileReceiverForegroundService::class.java).apply {
            action = ACTION_STOP_RING
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 2, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔔 Ringing Moto Pad")
            .setContentText("MacBook is locating this device! Tap Stop to silence.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "⏹ Stop Alarm", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun updateNotificationWithProgress(state: ActiveTransferState) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val progressPercent = (state.progress * 100).toInt()
        val speedMb = state.speedBytesPerSec / (1024.0 * 1024.0)
        val speedStr = if (speedMb >= 1.0) "%.1f MB/s".format(speedMb) else "%.0f KB/s".format(state.speedBytesPerSec / 1024.0)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Receiving ${state.fileName}")
            .setContentText("$progressPercent% • $speedStr • Saving to ${state.destinationFolder}")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progressPercent, false)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    fun getLocalIpAddress(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (networkInterface.isLoopback || !networkInterface.isUp) continue

                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (address is Inet4Address && !address.isLoopbackAddress) {
                        return address.hostAddress ?: "127.0.0.1"
                    }
                }
            }
        } catch (_: Exception) {}
        return "127.0.0.1"
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            clipboardManager.removePrimaryClipChangedListener(clipChangedListener)
            unregisterReceiver(batteryReceiver)
        } catch (_: Exception) {}
        stopServer()
    }
}
