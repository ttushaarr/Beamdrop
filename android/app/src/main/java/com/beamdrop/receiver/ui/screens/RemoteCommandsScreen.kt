package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel

data class CommandUI(
    val id: String,
    val title: String,
    val description: String,
    val icon: ImageVector
)

@Composable
fun RemoteCommandsScreen(viewModel: MainViewModel) {
    var showUrlDialog by remember { mutableStateOf(false) }
    var urlInput by remember { mutableStateOf("") }
    var lastTriggered by remember { mutableStateOf<String?>(null) }

    val commands = remember {
        listOf(
            CommandUI("lock_screen", "Lock Mac", "Lock screen immediately", Icons.Default.Lock),
            CommandUI("unlock_mac", "Unlock Mac", "Biometric Mac unlock", Icons.Default.Fingerprint),
            CommandUI("sleep", "Sleep Mac", "Put MacBook to sleep", Icons.Default.Bedtime),
            CommandUI("screenshot", "Screenshot", "Save to Mac Desktop", Icons.Default.CameraAlt),
            CommandUI("mute", "Mute Audio", "Toggle system sound", Icons.Default.VolumeMute),
            CommandUI("empty_trash", "Empty Trash", "Clean Mac trash bin", Icons.Default.Delete),
            CommandUI("terminal", "Open Terminal", "Launch macOS Terminal", Icons.Default.Terminal),
            CommandUI("ring_mac", "Ring MacBook", "Play locating sound on Mac", Icons.Default.NotificationsActive),
            CommandUI("open_url", "Send URL / Tab", "Open web link in Mac browser", Icons.Default.OpenInBrowser)
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "Remote Commands",
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
            )
            Text(
                text = "Trigger Mac actions and workflows with a single tap",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        lastTriggered?.let {
            Card(
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "✓ Triggered: $it on MacBook",
                    modifier = Modifier.padding(12.dp),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        // Grid of Commands
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.weight(1f)
        ) {
            items(commands) { cmd ->
                ElevatedCard(
                    onClick = {
                        if (cmd.id == "open_url") {
                            showUrlDialog = true
                        } else if (cmd.id == "ring_mac") {
                            viewModel.sendRingMac()
                            lastTriggered = "Ring MacBook"
                        } else if (cmd.id == "unlock_mac") {
                            viewModel.unlockMacBiometric { ok ->
                                lastTriggered = if (ok) "Mac Unlocked via Biometric" else "Unlock request failed"
                            }
                        } else {
                            viewModel.sendRemoteCommand(cmd.id)
                            lastTriggered = cmd.title
                        }
                    },
                    shape = RoundedCornerShape(16.dp),
                    modifier = Modifier.fillMaxWidth().height(115.dp)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = cmd.icon,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(28.dp)
                            )
                            Icon(
                                imageVector = Icons.Default.ChevronRight,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                modifier = Modifier.size(18.dp)
                            )
                        }

                        Column {
                            Text(cmd.title, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            Text(cmd.description, fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                        }
                    }
                }
            }
        }
    }

    // Open URL Dialog
    if (showUrlDialog) {
        AlertDialog(
            onDismissRequest = { showUrlDialog = false },
            title = { Text("Open URL on MacBook") },
            text = {
                OutlinedTextField(
                    value = urlInput,
                    onValueChange = { urlInput = it },
                    label = { Text("URL (e.g. https://google.com)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                Button(onClick = {
                    if (urlInput.isNotBlank()) {
                        val formatted = if (!urlInput.startsWith("http://") && !urlInput.startsWith("https://")) "https://$urlInput" else urlInput
                        viewModel.openUrlOnMac(formatted)
                        lastTriggered = "Open $formatted"
                        showUrlDialog = false
                        urlInput = ""
                    }
                }) {
                    Text("Open on Mac")
                }
            },
            dismissButton = {
                TextButton(onClick = { showUrlDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}
