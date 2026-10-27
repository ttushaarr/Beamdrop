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
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

object CameraHelper {
    private const val TAG = "CameraHelper"

    @SuppressLint("MissingPermission")
    suspend fun captureSnapshot(context: Context): ByteArray? = withTimeoutOrNull(6000) {
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

        // Find back-facing camera or fallback to first
        var targetCameraId = cameraIdList[0]
        for (id in cameraIdList) {
            val chars = cameraManager.getCameraCharacteristics(id)
            val facing = chars.get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                targetCameraId = id
                break
            }
        }

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
            val width = 1280
            val height = 720
            val reader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 2)
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
                            Log.i(TAG, "Captured snapshot frame of size ${bytes.size} bytes")
                            deferredResult.complete(bytes)
                            return@setOnImageAvailableListener
                        }
                        image.close()
                    }
                    deferredResult.complete(null)
                } catch (e: Exception) {
                    Log.e(TAG, "Error acquiring image: ${e.message}")
                    deferredResult.complete(null)
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
                                        val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                                            addTarget(surface)
                                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                            set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                                        }
                                        session.capture(captureBuilder.build(), null, handler)
                                        Log.i(TAG, "Capture request dispatched")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Failed to dispatch capture request: ${e.message}")
                                        deferredResult.complete(null)
                                    }
                                }

                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    Log.e(TAG, "Session configuration failed")
                                    deferredResult.complete(null)
                                }
                            },
                            handler
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to create capture session: ${e.message}")
                        deferredResult.complete(null)
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera disconnected")
                    camera.close()
                    deferredResult.complete(null)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera device error: $error")
                    camera.close()
                    deferredResult.complete(null)
                }
            }, handler)

            val result = deferredResult.await()
            cleanup()
            return@withTimeoutOrNull result
        } catch (e: Exception) {
            Log.e(TAG, "Exception during captureSnapshot: ${e.message}")
            cleanup()
            return@withTimeoutOrNull null
        }
    }
}
