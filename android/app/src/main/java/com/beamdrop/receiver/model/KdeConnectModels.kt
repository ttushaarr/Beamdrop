package com.beamdrop.receiver.model

data class BatteryInfo(
    val percentage: Int,
    val isCharging: Boolean,
    val timestamp: Long = System.currentTimeMillis()
)

data class RemoteInputPayload(
    val type: String, // "move", "click", "scroll", "key"
    val dx: Float = 0f,
    val dy: Float = 0f,
    val button: String? = null, // "left", "right", "double"
    val key: String? = null, // key code name or character
    val text: String? = null // typed string
)

data class MediaActionPayload(
    val action: String, // "playPause", "next", "prev", "volume", "mute"
    val volume: Float? = null // 0.0 to 1.0
)

data class RemoteCommandItem(
    val id: String,
    val name: String,
    val description: String,
    val iconName: String
)

data class MirroredNotification(
    val id: String,
    val packageName: String,
    val appName: String,
    val title: String,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    val key: String = "",
    val canReply: Boolean = false
)
