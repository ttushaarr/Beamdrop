package com.beamdrop.receiver.security

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.beamdrop.receiver.model.PairedDevice
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.UUID

class PairingManager(private val context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("beamdrop_pairing", Context.MODE_PRIVATE)
    private val random = SecureRandom()

    val serverAuthToken: String = getOrCreateServerToken()

    companion object {
        private const val TAG = "PairingManager"
        const val DEVICE_NAME = "Moto Pad 60 Pro"
        private const val KEY_SERVER_TOKEN = "server_auth_token"
        private const val KEY_PAIRED_DEVICES = "paired_devices_json"
        private const val KEY_ACTIVE_PIN = "active_pairing_pin"
        private const val KEY_PIN_TIMESTAMP = "active_pin_timestamp"
        private const val PIN_VALIDITY_MS = 60 * 60 * 1000L // 1 hour validity
    }

    private fun getOrCreateServerToken(): String {
        var token = prefs.getString(KEY_SERVER_TOKEN, null)
        if (token == null) {
            token = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "")
            prefs.edit().putString(KEY_SERVER_TOKEN, token).apply()
        }
        return token
    }

    fun getActivePin(): String {
        val savedPin = prefs.getString(KEY_ACTIVE_PIN, null)
        val savedTime = prefs.getLong(KEY_PIN_TIMESTAMP, 0L)
        if (savedPin != null && (System.currentTimeMillis() - savedTime < PIN_VALIDITY_MS)) {
            return savedPin
        }
        return refreshPin()
    }

    fun refreshPin(): String {
        val newPin = generateRandomPin()
        prefs.edit()
            .putString(KEY_ACTIVE_PIN, newPin)
            .putLong(KEY_PIN_TIMESTAMP, System.currentTimeMillis())
            .commit() // Synchronous commit to ensure immediate visibility across instances
        Log.i(TAG, "Generated and persisted new pairing PIN: $newPin")
        return newPin
    }

    private fun generateRandomPin(): String {
        val number = random.nextInt(900000) + 100000
        return number.toString()
    }

    fun getQrCodePayload(localIp: String, port: Int): String {
        val json = JSONObject().apply {
            put("version", 1)
            put("deviceId", getReceiverId())
            put("deviceName", DEVICE_NAME)
            put("ip", localIp)
            put("port", port)
            put("pairingSecret", getActivePin())
        }
        return json.toString()
    }

    fun getReceiverId(): String {
        var id = prefs.getString("receiver_device_id", null)
        if (id == null) {
            id = "moto-pad-60-pro-" + UUID.randomUUID().toString().take(8)
            prefs.edit().putString("receiver_device_id", id).apply()
        }
        return id
    }

    fun validatePairingPin(pin: String): Boolean {
        val expectedPin = getActivePin().replace(" ", "").trim()
        val candidate = pin.replace(" ", "").trim()
        val isValid = expectedPin == candidate
        Log.i(TAG, "Validating PIN candidate '$candidate' against expected '$expectedPin': result=$isValid")
        return isValid
    }

    fun addPairedDevice(senderId: String, senderName: String, clientAuthToken: String) {
        val devices = getPairedDevices().toMutableList()
        devices.removeAll { it.deviceId == senderId }
        devices.add(
            PairedDevice(
                deviceId = senderId,
                deviceName = senderName,
                clientAuthToken = clientAuthToken,
                pairedAt = System.currentTimeMillis()
            )
        )
        savePairedDevices(devices)
    }

    fun isAuthorized(authHeader: String?): Boolean {
        if (authHeader.isNullOrEmpty()) return false
        val token = if (authHeader.startsWith("Bearer ", ignoreCase = true)) {
            authHeader.substring(7).trim()
        } else {
            authHeader.trim()
        }
        return token == serverAuthToken
    }

    fun getPairedDevices(): List<PairedDevice> {
        val jsonString = prefs.getString(KEY_PAIRED_DEVICES, null) ?: return emptyList()
        val list = mutableListOf<PairedDevice>()
        try {
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                list.add(
                    PairedDevice(
                        deviceId = obj.getString("deviceId"),
                        deviceName = obj.getString("deviceName"),
                        clientAuthToken = obj.getString("clientAuthToken"),
                        pairedAt = obj.optLong("pairedAt", System.currentTimeMillis()),
                        lastTransferAt = obj.optLong("lastTransferAt", System.currentTimeMillis())
                    )
                )
            }
        } catch (_: Exception) {}
        return list
    }

    fun revokeDevice(deviceId: String) {
        val devices = getPairedDevices().toMutableList()
        devices.removeAll { it.deviceId == deviceId }
        savePairedDevices(devices)
    }

    private fun savePairedDevices(devices: List<PairedDevice>) {
        val array = JSONArray()
        for (d in devices) {
            val obj = JSONObject().apply {
                put("deviceId", d.deviceId)
                put("deviceName", d.deviceName)
                put("clientAuthToken", d.clientAuthToken)
                put("pairedAt", d.pairedAt)
                put("lastTransferAt", d.lastTransferAt)
            }
            array.put(obj)
        }
        prefs.edit().putString(KEY_PAIRED_DEVICES, array.toString()).apply()
    }
}
