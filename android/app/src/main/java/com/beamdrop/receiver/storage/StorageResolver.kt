package com.beamdrop.receiver.storage

import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.beamdrop.receiver.model.DestinationType

object StorageResolver {

    private val IMAGE_EXTENSIONS = setOf(
        "jpg", "jpeg", "png", "webp", "heic", "heif", "gif", "avif", "bmp", "tif", "tiff", "raw", "dng"
    )

    private val VIDEO_EXTENSIONS = setOf(
        "mp4", "mkv", "mov", "webm", "avi", "3gp", "m4v", "ts", "flv", "wmv"
    )

    fun resolve(fileName: String, proposedMime: String? = null): StorageDestination {
        val ext = fileName.substringAfterLast('.', "").lowercase()

        val isImage = IMAGE_EXTENSIONS.contains(ext) || proposedMime?.startsWith("image/") == true
        val isVideo = VIDEO_EXTENSIONS.contains(ext) || proposedMime?.startsWith("video/") == true

        return when {
            isImage -> {
                StorageDestination(
                    type = DestinationType.PICTURES,
                    relativePath = "Pictures/LaptopTransfer",
                    contentUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    },
                    mimeType = proposedMime ?: resolveMimeType(ext, "image/jpeg")
                )
            }
            isVideo -> {
                StorageDestination(
                    type = DestinationType.MOVIES,
                    relativePath = "Movies/LaptopTransfer",
                    contentUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    },
                    mimeType = proposedMime ?: resolveMimeType(ext, "video/mp4")
                )
            }
            else -> {
                StorageDestination(
                    type = DestinationType.DOWNLOADS,
                    relativePath = "Download/LaptopTransfer",
                    contentUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        MediaStore.Files.getContentUri("external")
                    },
                    mimeType = proposedMime ?: resolveMimeType(ext, "application/octet-stream")
                )
            }
        }
    }

    private fun resolveMimeType(ext: String, defaultMime: String): String {
        return when (ext) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "heic" -> "image/heic"
            "gif" -> "image/gif"
            "mp4" -> "video/mp4"
            "mov" -> "video/quicktime"
            "mkv" -> "video/x-matroska"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "json" -> "application/json"
            "txt" -> "text/plain"
            else -> defaultMime
        }
    }
}

data class StorageDestination(
    val type: DestinationType,
    val relativePath: String,
    val contentUri: Uri,
    val mimeType: String
)
