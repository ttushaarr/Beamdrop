package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel

@Composable
fun WebcamScreen(viewModel: MainViewModel) {
    val isStreaming by viewModel.isWebcamStreaming.collectAsState()
    val isBackCamera by viewModel.isWebcamBackCamera.collectAsState()
    val isTorchOn by viewModel.isWebcamTorchOn.collectAsState()
    val fps by viewModel.webcamFps.collectAsState()
    val serverIp by viewModel.serverIp.collectAsState()

    val streamUrl = "http://$serverIp:8765/api/v1/webcam/stream"
    val clipboardManager = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Hero Header Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = if (isStreaming) Color(0xFF1E3A8A) else MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                            .background(if (isStreaming) Color.Red.copy(alpha = 0.2f) else MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
                        contentAlignment = Alignment.Center
                    ) {
                            Icon(
                                Icons.Default.Videocam,
                                contentDescription = null,
                                modifier = Modifier.size(28.dp),
                                tint = if (isStreaming) Color.Red else MaterialTheme.colorScheme.primary
                            )
                    }

                    Spacer(modifier = Modifier.width(16.dp))

                    Column {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                "Wireless HD Webcam",
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (isStreaming) Color.White else MaterialTheme.colorScheme.onPrimaryContainer
                            )
                            if (isStreaming) {
                                Spacer(modifier = Modifier.width(8.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(4.dp))
                                        .background(Color.Red)
                                        .padding(horizontal = 6.dp, vertical = 2.dp)
                                ) {
                                    Text(
                                        "LIVE $fps FPS",
                                        color = Color.White,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Bold
                                    )
                                }
                            }
                        }

                        Text(
                            if (isStreaming) "Streaming 720p 30fps • Low Wi-Fi Latency" else "Stream your camera into Zoom, Meet, or OBS Studio",
                            fontSize = 12.sp,
                            color = if (isStreaming) Color.White.copy(alpha = 0.8f) else MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                        )
                    }
                }
            }
        }

        // Camera Controls
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "Camera Stream Controls",
                        fontWeight = FontWeight.Bold,
                        fontSize = 15.sp
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = {
                                if (isStreaming) viewModel.stopWebcam() else viewModel.startWebcam()
                            },
                            modifier = Modifier.weight(1f),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isStreaming) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                            )
                        ) {
                            Icon(
                                if (isStreaming) Icons.Default.Stop else Icons.Default.PlayArrow,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(if (isStreaming) "Stop Stream" else "Start Stream")
                        }

                        OutlinedButton(
                            onClick = { viewModel.toggleWebcamCamera() },
                            enabled = isStreaming
                        ) {
                            Icon(Icons.Default.FlipCameraAndroid, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(if (isBackCamera) "Front" else "Back")
                        }

                        OutlinedButton(
                            onClick = { viewModel.toggleWebcamTorch() },
                            enabled = isStreaming && isBackCamera
                        ) {
                            Icon(
                                if (isTorchOn) Icons.Default.FlashOn else Icons.Default.FlashOff,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = if (isTorchOn) Color(0xFFFFB300) else LocalContentColor.current
                            )
                        }
                    }
                }
            }
        }

        // Stream URL Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "📡 Live MJPEG Stream URL",
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Add this URL directly into OBS Studio (Browser Source) or any web browser:",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )

                    Spacer(modifier = Modifier.height(10.dp))

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            streamUrl,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 12.sp,
                            modifier = Modifier.weight(1f)
                        )

                        IconButton(onClick = {
                            clipboardManager.setText(AnnotatedString(streamUrl))
                            copied = true
                        }) {
                            Icon(
                                if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                                contentDescription = "Copy",
                                tint = if (copied) Color.Green else MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }
        }

        // How To Use Guide Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        "💡 How to Use as Zoom / Google Meet Virtual Webcam",
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                    Spacer(modifier = Modifier.height(8.dp))

                    val steps = listOf(
                        "1. Tap 'Start Stream' above.",
                        "2. In OBS Studio on your Mac, add a '+' > 'Browser Source'.",
                        "3. Paste the Stream URL above and set Width: 1280, Height: 720.",
                        "4. Click 'Start Virtual Camera' in the OBS controls panel.",
                        "5. In Zoom or Google Meet, choose 'OBS Virtual Camera' as your video camera!"
                    )

                    steps.forEach { step ->
                        Text(
                            step,
                            fontSize = 12.sp,
                            lineHeight = 18.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.9f)
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                    }
                }
            }
        }
    }
}
