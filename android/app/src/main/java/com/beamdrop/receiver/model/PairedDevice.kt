package com.beamdrop.receiver.model

data class PairedDevice(
    val deviceId: String,
    val deviceName: String,
    val clientAuthToken: String,
    val pairedAt: Long = System.currentTimeMillis(),
    val lastTransferAt: Long = System.currentTimeMillis()
)

data class PairingRequest(
    val senderId: String,
    val senderName: String,
    val pairingSecret: String,
    val clientAuthToken: String
)

data class PairingResponse(
    val status: String,
    val receiverId: String,
    val receiverName: String,
    val serverAuthToken: String
)
