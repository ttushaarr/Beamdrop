package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel

@Composable
fun TrackpadScreen(viewModel: MainViewModel) {
    var textInput by remember { mutableStateOf("") }
    var showKeyboardSheet by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Remote Trackpad",
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
                )
                Text(
                    text = "Swipe to move cursor • Tap to click • Right strip to scroll",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            IconButton(onClick = { showKeyboardSheet = !showKeyboardSheet }) {
                Icon(
                    imageVector = Icons.Default.Keyboard,
                    contentDescription = "Send Text",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }

        // Quick Text / Keystroke Drawer (if toggled)
        if (showKeyboardSheet) {
            Card(
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = textInput,
                            onValueChange = { textInput = it },
                            placeholder = { Text("Type text to send to Mac...") },
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        Button(onClick = {
                            if (textInput.isNotEmpty()) {
                                viewModel.sendTypedText(textInput)
                                textInput = ""
                            }
                        }) {
                            Text("Send")
                        }
                    }

                    // Special Keys Row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        AssistChip(
                            onClick = { viewModel.sendKey("Return") },
                            label = { Text("Enter ↵") }
                        )
                        AssistChip(
                            onClick = { viewModel.sendKey("Backspace") },
                            label = { Text("⌫ Back") }
                        )
                        AssistChip(
                            onClick = { viewModel.sendKey("Space") },
                            label = { Text("Space") }
                        )
                        AssistChip(
                            onClick = { viewModel.sendKey("Escape") },
                            label = { Text("Esc") }
                        )
                        AssistChip(
                            onClick = { viewModel.sendKey("Tab") },
                            label = { Text("Tab") }
                        )
                    }
                }
            }
        }

        // Main Touchpad Area with Scroll Strip
        Row(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Touchpad
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
                    .pointerInput(Unit) {
                        detectDragGestures { change, dragAmount ->
                            change.consume()
                            viewModel.sendTrackpadMove(dragAmount.x * 1.6f, dragAmount.y * 1.6f)
                        }
                    }
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onTap = { viewModel.sendTrackpadClick("left") },
                            onDoubleTap = { viewModel.sendTrackpadClick("double") },
                            onLongPress = { viewModel.sendTrackpadClick("right") }
                        )
                    },
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = Icons.Default.TouchApp,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                        modifier = Modifier.size(64.dp)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Touchpad Surface",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                    )
                }
            }

            // Vertical Scroll Strip
            Box(
                modifier = Modifier
                    .width(44.dp)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(16.dp))
                    .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f))
                    .pointerInput(Unit) {
                        detectDragGestures { change, dragAmount ->
                            change.consume()
                            viewModel.sendTrackpadScroll(-dragAmount.y * 0.8f)
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.SpaceBetween,
                    modifier = Modifier.fillMaxHeight().padding(vertical = 16.dp)
                ) {
                    Icon(Icons.Default.KeyboardArrowUp, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Icon(Icons.Default.UnfoldMore, contentDescription = "Scroll", tint = MaterialTheme.colorScheme.primary)
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                }
            }
        }

        // Bottom Left & Right Click Buttons
        Row(
            modifier = Modifier.fillMaxWidth().height(64.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            FilledTonalButton(
                onClick = { viewModel.sendTrackpadClick("left") },
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.weight(1f).fillMaxHeight()
            ) {
                Icon(Icons.Default.Mouse, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Left Click", fontWeight = FontWeight.Bold)
            }

            FilledTonalButton(
                onClick = { viewModel.sendTrackpadClick("right") },
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier.weight(1f).fillMaxHeight()
            ) {
                Icon(Icons.Default.Mouse, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Right Click", fontWeight = FontWeight.Bold)
            }
        }
    }
}
