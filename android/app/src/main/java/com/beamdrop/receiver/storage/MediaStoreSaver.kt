package com.beamdrop.receiver.storage

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.beamdrop.receiver.model.DestinationType
import com.beamdrop.receiver.model.TransferRecord
import java.io.InputStream
import java.io.OutputStream
import java.security.DigestInputStream
import java.security.MessageDigest

class MediaStoreSaver(private val context: Context) {

    private val contentResolver: ContentResolver = context.contentResolver

    /**
     * Resolves a unique filename to prevent silent overwrites.
     * E.g. "photo.jpg" -> "photo (1).jpg" if "photo.jpg" already exists.
     */
    fun resolveUniqueFileName(destination: StorageDestination, desiredName: String): String {
        val baseName = desiredName.substringBeforeLast('.')
        val ext = desiredName.substringAfterLast('.', "")
        val dotExt = if (ext.isNotEmpty()) ".$ext" else ""

        var currentCandidate = desiredName
        var counter = 1

        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"

        while (true) {
            val selectionArgs = arrayOf(currentCandidate, "${destination.relativePath}%")
            val cursor = contentResolver.query(
                destination.contentUri,
                projection,
                selection,
                selectionArgs,
                null
            )

            val exists = cursor?.use { it.count > 0 } ?: false
            if (!exists) {
                return currentCandidate
            }

            currentCandidate = "$baseName ($counter)$dotExt"
            counter++
        }
    }

    /**
     * Streams incoming bytes directly to MediaStore with IS_PENDING = 1,
     * computes running SHA-256, and finalizes with IS_PENDING = 0 on success.
     */
    fun saveStream(
        transferId: String,
        originalName: String,
        totalBytes: Long,
        expectedSha256: String,
        inputStream: InputStream,
        onProgress: (bytesReceived: Long, totalBytes: Long) -> Unit
    ): TransferRecord {
        val destination = StorageResolver.resolve(originalName, null)
        val uniqueName = resolveUniqueFileName(destination, originalName)

        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, uniqueName)
            put(MediaStore.MediaColumns.MIME_TYPE, destination.mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, destination.relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val targetUri: Uri = contentResolver.insert(destination.contentUri, contentValues)
            ?: throw IllegalStateException("Failed to create MediaStore entry for $uniqueName")

        val digest = MessageDigest.getInstance("SHA-256")
        val digestStream = DigestInputStream(inputStream, digest)

        try {
            contentResolver.openOutputStream(targetUri)?.use { outputStream ->
                val buffer = ByteArray(64 * 1024) // 64 KB chunks
                var bytesRead: Int
                var totalRead: Long = 0

                while (digestStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    totalRead += bytesRead
                    onProgress(totalRead, totalBytes)
                }
                outputStream.flush()
            } ?: throw IllegalStateException("Could not open output stream for $targetUri")

            // Verify SHA-256
            val computedHash = digest.digest().joinToString("") { "%02x".format(it) }
            if (!computedHash.equals(expectedSha256, ignoreCase = true)) {
                // Checksum failure - delete corrupted file
                contentResolver.delete(targetUri, null, null)
                throw SecurityException("Checksum verification failed: expected $expectedSha256 but got $computedHash")
            }

            // Publish file (IS_PENDING = 0) so Gallery & Photos index it immediately
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val publishValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                contentResolver.update(targetUri, publishValues, null, null)
            }

            // Trigger MediaScanner for broad compatibility
            MediaScannerConnection.scanFile(
                context,
                arrayOf(destination.relativePath + "/" + uniqueName),
                arrayOf(destination.mimeType),
                null
            )

            return TransferRecord(
                id = transferId,
                fileName = uniqueName,
                fileSize = totalBytes,
                mimeType = destination.mimeType,
                folder = destination.relativePath,
                uri = targetUri.toString(),
                timestamp = System.currentTimeMillis(),
                sha256 = computedHash,
                destinationType = destination.type
            )

        } catch (e: Exception) {
            // Delete incomplete MediaStore record on error or cancellation
            try {
                contentResolver.delete(targetUri, null, null)
            } catch (_: Exception) {}
            throw e
        }
    }
}
