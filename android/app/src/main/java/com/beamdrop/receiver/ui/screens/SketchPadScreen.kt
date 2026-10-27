package com.beamdrop.receiver.ui.screens

import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Paint as AndroidPaint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel
import java.io.ByteArrayOutputStream

data class DrawingPath(
    val path: Path,
    val color: Color,
    val strokeWidth: Float,
    val points: List<Offset> = emptyList()
)

@Composable
fun SketchPadScreen(viewModel: MainViewModel) {
    val paths = remember { mutableStateListOf<DrawingPath>() }
    var currentPath by remember { mutableStateOf<Path?>(null) }
    val currentPoints = remember { mutableStateListOf<Offset>() }
    var selectedColor by remember { mutableStateOf(Color.Black) }
    var strokeWidth by remember { mutableFloatStateOf(6f) }
    var sketchStatus by remember { mutableStateOf<String?>(null) }
    var isSending by remember { mutableStateOf(false) }
    var canvasSize by remember { mutableStateOf(IntSize(1280, 800)) }

    val colors = listOf(
        Color(0xFF000000), // Black
        Color(0xFF1E88E5), // Blue
        Color(0xFFE53935), // Red
        Color(0xFF43A047), // Green
        Color(0xFFFB8C00), // Orange
        Color(0xFF8E24AA)  // Purple
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Top Action Bar
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "✍️ Continuity Sketch Pad",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold
                )
                Text(
                    text = "Draw or sign with finger/stylus to send straight to Mac",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IconButton(
                    onClick = {
                        if (paths.isNotEmpty()) paths.removeAt(paths.size - 1)
                    },
                    enabled = paths.isNotEmpty()
                ) {
                    Icon(Icons.Default.Undo, contentDescription = "Undo")
                }

                IconButton(
                    onClick = {
                        paths.clear()
                        sketchStatus = null
                    },
                    enabled = paths.isNotEmpty()
                ) {
                    Icon(Icons.Default.Delete, contentDescription = "Clear")
                }
            }
        }

        // Color and Stroke Toolbar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Colors
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                colors.forEach { color ->
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(CircleShape)
                            .background(color)
                            .border(
                                width = if (selectedColor == color) 3.dp else 1.dp,
                                color = if (selectedColor == color) MaterialTheme.colorScheme.primary else Color.LightGray,
                                shape = CircleShape
                            )
                            .clickable { selectedColor = color }
                    )
                }
            }

            // Stroke size toggles
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(3f to "Fine", 8f to "Med", 18f to "Bold").forEach { (width, label) ->
                    FilterChip(
                        selected = strokeWidth == width,
                        onClick = { strokeWidth = width },
                        label = { Text(label, fontSize = 11.sp) }
                    )
                }
            }
        }

        // Drawing Canvas Card
        ElevatedCard(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = Color.White)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(selectedColor, strokeWidth) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                val p = Path()
                                p.moveTo(offset.x, offset.y)
                                currentPath = p
                                currentPoints.clear()
                                currentPoints.add(offset)
                            },
                            onDrag = { change, _ ->
                                change.consume()
                                currentPath?.lineTo(change.position.x, change.position.y)
                                currentPoints.add(change.position)
                            },
                            onDragEnd = {
                                currentPath?.let { p ->
                                    paths.add(DrawingPath(p, selectedColor, strokeWidth, currentPoints.toList()))
                                }
                                currentPath = null
                                currentPoints.clear()
                            },
                            onDragCancel = {
                                currentPath = null
                                currentPoints.clear()
                            }
                        )
                    }
            ) {
                Canvas(
                    modifier = Modifier
                        .fillMaxSize()
                        .onGloballyPositioned { coordinates ->
                            if (coordinates.size.width > 0 && coordinates.size.height > 0) {
                                canvasSize = coordinates.size
                            }
                        }
                ) {
                    // Draw committed paths
                    paths.forEach { dp ->
                        drawPath(
                            path = dp.path,
                            color = dp.color,
                            style = Stroke(
                                width = dp.strokeWidth,
                                cap = StrokeCap.Round,
                                join = StrokeJoin.Round
                            )
                        )
                    }

                    // Draw active path
                    currentPath?.let { p ->
                        drawPath(
                            path = p,
                            color = selectedColor,
                            style = Stroke(
                                width = strokeWidth,
                                cap = StrokeCap.Round,
                                join = StrokeJoin.Round
                            )
                        )
                    }
                }

                if (paths.isEmpty() && currentPath == null) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "✍️ Draw signature, diagram, or sketch here",
                            color = Color.LightGray,
                            fontSize = 14.sp
                        )
                    }
                }
            }
        }

        // Action Buttons Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Button(
                onClick = {
                    if (paths.isNotEmpty()) {
                        isSending = true
                        sketchStatus = "Sending to Mac Desktop..."
                        val pngBytes = exportPathsToPng(paths, canvasSize.width, canvasSize.height)
                        viewModel.sendSketchBytesToMac(pngBytes, "Desktop") { success ->
                            isSending = false
                            sketchStatus = if (success) "✓ Saved to MacBook Desktop!" else "Failed to send to Mac"
                        }
                    }
                },
                modifier = Modifier.weight(1f),
                enabled = paths.isNotEmpty() && !isSending,
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.Send, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Insert on Mac")
            }

            OutlinedButton(
                onClick = {
                    if (paths.isNotEmpty()) {
                        isSending = true
                        sketchStatus = "Copying to Mac Pasteboard..."
                        val pngBytes = exportPathsToPng(paths, canvasSize.width, canvasSize.height)
                        viewModel.sendSketchBytesToMac(pngBytes, "Clipboard") { success ->
                            isSending = false
                            sketchStatus = if (success) "✓ Copied to Mac Clipboard (Cmd+V)!" else "Failed to copy to Mac"
                        }
                    }
                },
                modifier = Modifier.weight(1f),
                enabled = paths.isNotEmpty() && !isSending,
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.ContentPaste, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Mac Clipboard")
            }
        }

        sketchStatus?.let { status ->
            Text(
                text = status,
                style = MaterialTheme.typography.bodySmall,
                color = if (status.startsWith("✓")) Color(0xFF2E7D32) else MaterialTheme.colorScheme.primary,
                fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                modifier = Modifier.padding(start = 4.dp)
            )
        }
    }
}

private fun exportPathsToPng(paths: List<DrawingPath>, width: Int, height: Int): ByteArray {
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = AndroidCanvas(bitmap)
    canvas.drawColor(android.graphics.Color.TRANSPARENT)

    paths.forEach { dp ->
        val paint = AndroidPaint().apply {
            color = dp.color.toArgb()
            strokeWidth = dp.strokeWidth * 1.5f
            style = AndroidPaint.Style.STROKE
            strokeCap = AndroidPaint.Cap.ROUND
            strokeJoin = AndroidPaint.Join.ROUND
            isAntiAlias = true
        }

        if (dp.points.size > 1) {
            val androidPath = android.graphics.Path()
            androidPath.moveTo(dp.points[0].x, dp.points[0].y)
            for (i in 1 until dp.points.size) {
                androidPath.lineTo(dp.points[i].x, dp.points[i].y)
            }
            canvas.drawPath(androidPath, paint)
        }
    }

    val stream = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
    return stream.toByteArray()
}
