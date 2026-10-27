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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.CopyOnWriteArrayList

object WebcamManager {
    private const val TAG = "WebcamManager"

    private val _isStreaming = MutableStateFlow(false)
    val isStreaming = _isStreaming.asStateFlow()

    private val _isBackCamera = MutableStateFlow(true)
    val isBackCamera = _isBackCamera.asStateFlow()

    private val _isTorchOn = MutableStateFlow(false)
    val isTorchOn = _isTorchOn.asStateFlow()

    private val _fps = MutableStateFlow(0)
    val fps = _fps.asStateFlow()

    @Volatile
    private var latestFrame: ByteArray? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private val frameListeners = CopyOnWriteArrayList<(ByteArray) -> Unit>()
    private var frameCount = 0
    private var lastFpsCalculationTime = 0L

    fun getLatestFrame(): ByteArray? = latestFrame

    fun addFrameListener(listener: (ByteArray) -> Unit) {
        frameListeners.add(listener)
    }

    fun removeFrameListener(listener: (ByteArray) -> Unit) {
        frameListeners.remove(listener)
    }

    @SuppressLint("MissingPermission")
    @Synchronized
    fun startStreaming(context: Context, useBackCamera: Boolean = _isBackCamera.value) {
        if (_isStreaming.value) return

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "Camera permission not granted")
            return
        }

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
        val targetFacing = if (useBackCamera) CameraCharacteristics.LENS_FACING_BACK else CameraCharacteristics.LENS_FACING_FRONT

        var targetCameraId: String? = null
        for (id in cameraManager.cameraIdList) {
            val chars = cameraManager.getCameraCharacteristics(id)
            if (chars.get(CameraCharacteristics.LENS_FACING) == targetFacing) {
                targetCameraId = id
                break
            }
        }
        if (targetCameraId == null) {
            targetCameraId = cameraManager.cameraIdList.firstOrNull() ?: return
        }

        val chars = cameraManager.getCameraCharacteristics(targetCameraId)
        val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val jpegSizes = map?.getOutputSizes(ImageFormat.JPEG) ?: emptyArray()

        // Optimal 720p resolution for high FPS and low Wi-Fi latency
        val chosenSize = jpegSizes.firstOrNull { it.width == 1280 && it.height == 720 }
            ?: jpegSizes.firstOrNull { it.width <= 1280 }
            ?: Size(1280, 720)

        val thread = HandlerThread("WebcamBackground").apply { start() }
        backgroundThread = thread
        val handler = Handler(thread.looper)
        backgroundHandler = handler

        val reader = ImageReader.newInstance(chosenSize.width, chosenSize.height, ImageFormat.JPEG, 3)
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
                        latestFrame = bytes
                        frameCount++

                        val now = System.currentTimeMillis()
                        if (now - lastFpsCalculationTime >= 1000) {
                            _fps.value = frameCount
                            frameCount = 0
                            lastFpsCalculationTime = now
                        }

                        for (listener in frameListeners) {
                            try { listener(bytes) } catch (_: Exception) {}
                        }
                    }
                    image.close()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error acquiring webcam frame: ${e.message}")
            }
        }, handler)

        try {
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
                                        val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                            addTarget(surface)
                                            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                                            if (_isTorchOn.value && useBackCamera) {
                                                set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
                                            }
                                        }
                                        session.setRepeatingRequest(req.build(), null, handler)
                                        _isStreaming.value = true
                                        _isBackCamera.value = useBackCamera
                                        Log.i(TAG, "Webcam streaming started on camera $targetCameraId at ${chosenSize.width}x${chosenSize.height}")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Failed to start repeating webcam request: ${e.message}")
                                        stopStreaming()
                                    }
                                }

                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    Log.e(TAG, "Webcam session configuration failed")
                                    stopStreaming()
                                }
                            },
                            handler
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to create webcam capture session: ${e.message}")
                        stopStreaming()
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Webcam camera disconnected")
                    stopStreaming()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Webcam camera error: $error")
                    stopStreaming()
                }
            }, handler)
        } catch (e: Exception) {
            Log.e(TAG, "Exception opening webcam camera: ${e.message}")
            stopStreaming()
        }
    }

    @Synchronized
    fun stopStreaming() {
        try {
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            imageReader?.close()
            imageReader = null
            backgroundThread?.quitSafely()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping webcam: ${e.message}")
        }
        _isStreaming.value = false
        _fps.value = 0
        Log.i(TAG, "Webcam streaming stopped")
    }

    fun toggleCamera(context: Context) {
        val nextIsBack = !_isBackCamera.value
        stopStreaming()
        startStreaming(context, useBackCamera = nextIsBack)
    }

    fun toggleTorch(context: Context) {
        val newTorch = !_isTorchOn.value
        _isTorchOn.value = newTorch
        if (_isStreaming.value) {
            val isBack = _isBackCamera.value
            stopStreaming()
            startStreaming(context, useBackCamera = isBack)
        }
    }
}
