package com.beamdrop.receiver.camera

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

object CameraHelper {
    private const val TAG = "CameraHelper"

    @SuppressLint("MissingPermission")
    suspend fun captureSnapshot(context: Context): ByteArray? = withTimeoutOrNull(7000) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "Camera permission not granted")
            return@withTimeoutOrNull null
        }

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return@withTimeoutOrNull null

        val cameraIdList = cameraManager.cameraIdList
        if (cameraIdList.isEmpty()) {
            Log.e(TAG, "No cameras available")
            return@withTimeoutOrNull null
        }

        // Try back-facing camera first, then fallback to any available camera
        val sortedCameraIds = cameraIdList.sortedByDescending { id ->
            val chars = try { cameraManager.getCameraCharacteristics(id) } catch (_: Exception) { null }
            val facing = chars?.get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) 2 else 1
        }

        for (targetCameraId in sortedCameraIds) {
            val result = captureFromCameraId(cameraManager, targetCameraId)
            if (result != null && result.isNotEmpty()) {
                return@withTimeoutOrNull result
            }
        }
        null
    }

    @SuppressLint("MissingPermission")
    private suspend fun captureFromCameraId(cameraManager: CameraManager, targetCameraId: String): ByteArray? {
        val chars = try {
            cameraManager.getCameraCharacteristics(targetCameraId)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get characteristics for camera $targetCameraId: ${e.message}")
            return null
        }

        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val jpegSizes = map?.getOutputSizes(ImageFormat.JPEG) ?: emptyArray()
        val chosenSize = jpegSizes.firstOrNull { it.width == 1280 && it.height == 720 }
            ?: jpegSizes.firstOrNull { it.width <= 1920 && it.height <= 1080 }
            ?: jpegSizes.firstOrNull()
            ?: Size(1280, 720)

        Log.i(TAG, "Selected camera $targetCameraId resolution: ${chosenSize.width}x${chosenSize.height}")

        val thread = HandlerThread("CameraBackground").apply { start() }
        val handler = Handler(thread.looper)

        val deferredResult = CompletableDeferred<ByteArray?>()
        var cameraDevice: CameraDevice? = null
        var captureSession: CameraCaptureSession? = null
        var imageReader: ImageReader? = null

        fun cleanup() {
            try {
                captureSession?.close()
                captureSession = null
                cameraDevice?.close()
                cameraDevice = null
                imageReader?.close()
                imageReader = null
                thread.quitSafely()
            } catch (e: Exception) {
                Log.e(TAG, "Error during cleanup: ${e.message}")
            }
        }

        try {
            val reader = ImageReader.newInstance(chosenSize.width, chosenSize.height, ImageFormat.JPEG, 2)
            imageReader = reader

            reader.setOnImageAvailableListener({ ir ->
                try {
                    val image = ir.acquireLatestImage()
                    if (image != null) {
                        val planes = image.planes
                        if (planes.isNotEmpty()) {
                            val buffer = planes[0].buffer
                            val bytes = ByteArray(buffer.remaining())
                            buffer.get(bytes)
                            image.close()
                            Log.i(TAG, "Successfully captured frame of size ${bytes.size} bytes from camera $targetCameraId")
                            if (!deferredResult.isCompleted) {
                                deferredResult.complete(bytes)
                            }
                            return@setOnImageAvailableListener
                        }
                        image.close()
                    }
                    if (!deferredResult.isCompleted) deferredResult.complete(null)
                } catch (e: Exception) {
                    Log.e(TAG, "Error acquiring image: ${e.message}")
                    if (!deferredResult.isCompleted) deferredResult.complete(null)
                }
            }, handler)

            cameraManager.openCamera(targetCameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    try {
                        val surface = reader.surface
                        camera.createCaptureSession(
                            listOf(surface),
                            object : CameraCaptureSession.StateCallback() {
                                override fun onConfigured(session: CameraCaptureSession) {
                                    captureSession = session
                                    try {
                                        // Use TEMPLATE_PREVIEW for universal hardware compatibility without 3A still lockups
                                        val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                            addTarget(surface)
                                            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                                        }
                                        session.capture(captureBuilder.build(), null, handler)
                                        Log.i(TAG, "Capture request dispatched to camera $targetCameraId")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Failed to dispatch capture request: ${e.message}")
                                        if (!deferredResult.isCompleted) deferredResult.complete(null)
                                    }
                                }

                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    Log.e(TAG, "Session configuration failed for camera $targetCameraId")
                                    if (!deferredResult.isCompleted) deferredResult.complete(null)
                                }
                            },
                            handler
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to create capture session: ${e.message}")
                        if (!deferredResult.isCompleted) deferredResult.complete(null)
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera $targetCameraId disconnected")
                    camera.close()
                    if (!deferredResult.isCompleted) deferredResult.complete(null)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera $targetCameraId error: $error")
                    camera.close()
                    if (!deferredResult.isCompleted) deferredResult.complete(null)
                }
            }, handler)

            val result = deferredResult.await()
            cleanup()
            return result
        } catch (e: Exception) {
            Log.e(TAG, "Exception during captureSnapshot on camera $targetCameraId: ${e.message}")
            cleanup()
            return null
        }
    }
}
