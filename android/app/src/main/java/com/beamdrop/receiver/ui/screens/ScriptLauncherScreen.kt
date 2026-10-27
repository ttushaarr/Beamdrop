package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScriptLauncherScreen(viewModel: MainViewModel) {
    val macScripts by viewModel.macScripts.collectAsState()
    val scriptOutput by viewModel.scriptOutput.collectAsState()
    val isRunning by viewModel.isRunningScript.collectAsState()
    val targetMacIp by viewModel.targetMacIp.collectAsState()
    val adbStatus by viewModel.adbStatus.collectAsState()
    val isAdbConnecting by viewModel.isAdbConnecting.collectAsState()

    var showAddDialog by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    var newCommand by remember { mutableStateOf("") }
    var newIcon by remember { mutableStateOf("⚡") }

    var showAdbPairDialog by remember { mutableStateOf(false) }
    var adbPairingPort by remember { mutableStateOf("") }
    var adbPairingCode by remember { mutableStateOf("") }

    val clipboardManager = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.fetchMacScripts()
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        Icons.Default.Terminal,
                        contentDescription = null,
                        modifier = Modifier.size(36.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(16.dp))
                    Column {
                        Text(
                            "Mac Script Launchers & Wireless ADB",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                        Text(
                            if (!targetMacIp.isNullOrEmpty()) "Connected to Mac at $targetMacIp:8768" else "Mac Receiver: Auto-discovering...",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                        )
                    }
                }
            }
        }

        // 1-Click Wireless ADB Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            Icons.Default.Wifi,
                            contentDescription = null,
                            tint = Color(0xFFFF9800)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "⚡ 1-Click Wireless ADB",
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp
                        )
                        Spacer(modifier = Modifier.weight(1f))
                    }

                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "Pair and connect Mac ADB over Wi-Fi without typing adb connect or using a USB cable.",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f)
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { viewModel.connectMacAdb() },
                            enabled = !isAdbConnecting
                        ) {
                            if (isAdbConnecting) {
                                CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White)
                                Spacer(modifier = Modifier.width(6.dp))
                                Text("Connecting...")
                            } else {
                                Icon(Icons.Default.FlashOn, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text("1-Click Connect (Port 5555)")
                            }
                        }

                        OutlinedButton(onClick = { showAdbPairDialog = true }) {
                            Icon(Icons.Default.QrCode, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("Pair with Code")
                        }
                    }

                    if (adbStatus.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            adbStatus,
                            fontSize = 11.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }
        }

        // Script Actions Header
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "🚀 Mac Developer Scripts (${macScripts.size})",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    IconButton(onClick = { viewModel.fetchMacScripts() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                    Button(onClick = { showAddDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Add Script")
                    }
                }
            }
        }

        // Script List
        items(macScripts) { script ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(script.icon, fontSize = 24.sp)
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(script.name, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text(
                            script.command,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            maxLines = 1
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    FilledTonalButton(
                        onClick = { viewModel.runMacScript(script.id) },
                        enabled = !isRunning
                    ) {
                        Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Run")
                    }
                }
            }
        }

        // Terminal Output Console
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E1E))
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("💻 Terminal Output", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            if (isRunning) {
                                Spacer(modifier = Modifier.width(8.dp))
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), color = Color.Green, strokeWidth = 2.dp)
                            }
                        }
                        if (scriptOutput.isNotEmpty()) {
                            IconButton(onClick = {
                                clipboardManager.setText(AnnotatedString(scriptOutput))
                                copied = true
                            }) {
                                Icon(
                                    if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                                    contentDescription = "Copy",
                                    tint = if (copied) Color.Green else Color.White,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 100.dp, max = 250.dp)
                            .background(Color.Black, RoundedCornerShape(6.dp))
                            .padding(8.dp)
                            .verticalScroll(rememberScrollState())
                    ) {
                        Text(
                            text = if (scriptOutput.isNotEmpty()) scriptOutput else "Tap 'Run' on any script above to inspect real-time output from your Mac terminal.",
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            color = if (scriptOutput.isNotEmpty()) Color(0xFF00FF66) else Color.Gray
                        )
                    }
                }
            }
        }
    }

    // Add Script Dialog
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text("Add Custom Mac Script") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("Script Name (e.g. npm run dev)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = newCommand,
                        onValueChange = { newCommand = it },
                        label = { Text("Shell Command") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = newIcon,
                        onValueChange = { newIcon = it },
                        label = { Text("Icon Emoji (e.g. ⚡, 🐙, 🚀)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (newName.isNotBlank() && newCommand.isNotBlank()) {
                            viewModel.createMacScript(newName.trim(), newCommand.trim(), if (newIcon.isBlank()) "⚡" else newIcon.trim())
                            newName = ""
                            newCommand = ""
                            newIcon = "⚡"
                            showAddDialog = false
                        }
                    },
                    enabled = newName.isNotBlank() && newCommand.isNotBlank()
                ) {
                    Text("Save Script")
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Wireless ADB Pairing Dialog
    if (showAdbPairDialog) {
        AlertDialog(
            onDismissRequest = { showAdbPairDialog = false },
            title = { Text("Pair Wireless Debugging") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "On your phone/tablet, open Developer Options > Wireless Debugging > 'Pair device with pairing code'. Enter the details below:",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = adbPairingPort,
                        onValueChange = { adbPairingPort = it },
                        label = { Text("5-digit Pairing Port (e.g. 38472)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = adbPairingCode,
                        onValueChange = { adbPairingCode = it },
                        label = { Text("6-digit Pairing Code (e.g. 123456)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        val port = adbPairingPort.trim().toIntOrNull()
                        val code = adbPairingCode.trim()
                        if (port != null && code.isNotEmpty()) {
                            viewModel.connectMacAdb(pairingPort = port, pairingCode = code)
                            showAdbPairDialog = false
                            adbPairingPort = ""
                            adbPairingCode = ""
                        }
                    },
                    enabled = adbPairingPort.isNotBlank() && adbPairingCode.isNotBlank()
                ) {
                    Text("Pair & Connect")
                }
            },
            dismissButton = {
                TextButton(onClick = { showAdbPairDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}
