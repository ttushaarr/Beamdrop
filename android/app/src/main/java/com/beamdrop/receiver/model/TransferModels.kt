package com.beamdrop.receiver.model

import android.net.Uri
import java.util.Date

enum class DestinationType {
    PICTURES,
    MOVIES,
    DOWNLOADS
}

data class InitTransferRequest(
    val transferId: String,
    val fileName: String,
    val fileSize: Long,
    val mimeType: String,
    val sha256: String,
    val timestamp: Long
)

data class InitTransferResponse(
    val transferId: String,
    val status: String,
    val resolvedFileName: String,
    val targetFolder: String
)

data class TransferRecord(
    val id: String,
    val fileName: String,
    val fileSize: Long,
    val mimeType: String,
    val folder: String,
    val uri: String?,
    val timestamp: Long = System.currentTimeMillis(),
    val sha256: String,
    val destinationType: DestinationType
)

data class ActiveTransferState(
    val transferId: String,
    val fileName: String,
    val totalBytes: Long,
    val bytesReceived: Long,
    val speedBytesPerSec: Double,
    val isTransferring: Boolean,
    val destinationFolder: String
) {
    val progress: Float
        get() = if (totalBytes > 0) (bytesReceived.toFloat() / totalBytes).coerceIn(0f, 1f) else 0f
}
