package com.beamdrop.receiver.ui.screens

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

@Composable
fun SecondScreenView(viewModel: MainViewModel) {
    val targetMacIp by viewModel.targetMacIp.collectAsState()
    var isStreaming by remember { mutableStateOf(false) }
    var currentBitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var fps by remember { mutableIntStateOf(0) }
    var streamError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(isStreaming, targetMacIp) {
        if (!isStreaming || targetMacIp.isNullOrEmpty()) return@LaunchedEffect

        var frameCount = 0
        var lastFpsTime = System.currentTimeMillis()

        withContext(Dispatchers.IO) {
            while (isActive && isStreaming) {
                try {
                    val url = URL("http://$targetMacIp:8768/api/v1/screen/frame")
                    val conn = (url.openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2500
                        readTimeout = 3000
                    }
                    if (conn.responseCode == 200) {
                        val bytes = conn.inputStream.use { it.readBytes() }
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        if (bmp != null) {
                            withContext(Dispatchers.Main) {
                                currentBitmap = bmp
                                streamError = null
                            }
                            frameCount++
                            val now = System.currentTimeMillis()
                            if (now - lastFpsTime >= 1000) {
                                withContext(Dispatchers.Main) { fps = frameCount }
                                frameCount = 0
                                lastFpsTime = now
                            }
                        }
                    } else {
                        withContext(Dispatchers.Main) {
                            streamError = "Mac returned HTTP ${conn.responseCode}"
                        }
                    }
                    conn.disconnect()
                } catch (e: Exception) {
                    withContext(Dispatchers.Main) {
                        streamError = "Connecting to Mac screen..."
                    }
                    delay(500)
                }
                delay(33) // ~30 FPS poll
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Control Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "🖥️ Wireless Second Screen (Sidecar)",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold
                )
                Text(
                    text = if (isStreaming) "Streaming Mac display at $fps FPS • Touch enabled" else "Extend or mirror your MacBook display to this tablet",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Button(
                onClick = { isStreaming = !isStreaming },
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isStreaming) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                ),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(
                    imageVector = if (isStreaming) Icons.Default.Stop else Icons.Default.PlayArrow,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(if (isStreaming) "Stop Stream" else "Start Display")
            }
        }

        // Display Viewport
        ElevatedCard(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = Color.Black)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(targetMacIp, isStreaming) {
                        detectTapGestures(
                            onTap = { offset ->
                                if (isStreaming && !targetMacIp.isNullOrEmpty()) {
                                    val normX = (offset.x / size.width).coerceIn(0f, 1f)
                                    val normY = (offset.y / size.height).coerceIn(0f, 1f)
                                    viewModel.sendScreenTouch(normX, normY, "click")
                                }
                            }
                        )
                    },
                contentAlignment = Alignment.Center
            ) {
                if (currentBitmap != null) {
                    Image(
                        bitmap = currentBitmap!!.asImageBitmap(),
                        contentDescription = "Mac Second Display",
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Fit
                    )
                } else {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.LaptopMac,
                            contentDescription = null,
                            tint = Color.Gray,
                            modifier = Modifier.size(48.dp)
                        )
                        Text(
                            text = streamError ?: "Tap 'Start Display' to stream your MacBook screen",
                            color = Color.LightGray,
                            fontSize = 13.sp
                        )
                    }
                }

                if (isStreaming && currentBitmap != null) {
                    Surface(
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(12.dp),
                        shape = RoundedCornerShape(8.dp),
                        color = Color.Black.copy(alpha = 0.6f)
                    ) {
                        Text(
                            text = "⚡ $fps FPS • Touch Active",
                            color = Color.Green,
                            fontSize = 11.sp,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }
        }
    }
}
