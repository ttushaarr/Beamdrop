package com.beamdrop.receiver

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Slideshow
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.beamdrop.receiver.ui.MainViewModel
import com.beamdrop.receiver.ui.screens.AiSolverScreen
import com.beamdrop.receiver.ui.screens.DashboardScreen
import com.beamdrop.receiver.ui.screens.HistoryScreen
import com.beamdrop.receiver.ui.screens.MediaControlScreen
import com.beamdrop.receiver.ui.screens.PairingScreen
import com.beamdrop.receiver.ui.screens.PresentationScreen
import com.beamdrop.receiver.ui.screens.RemoteCommandsScreen
import com.beamdrop.receiver.ui.screens.ScriptLauncherScreen
import com.beamdrop.receiver.ui.screens.SecondScreenView
import com.beamdrop.receiver.ui.screens.SettingsScreen
import com.beamdrop.receiver.ui.screens.SketchPadScreen
import com.beamdrop.receiver.ui.screens.TrackpadScreen
import com.beamdrop.receiver.ui.screens.WebcamScreen
import com.beamdrop.receiver.ui.theme.BeamDropTheme

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { _ ->
        // Permissions handled
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        checkAndRequestPermissions()
        handleShareIntent(intent)

        setContent {
            BeamDropTheme {
                var selectedTab by remember { mutableIntStateOf(0) }

                Scaffold(
                    modifier = Modifier.fillMaxSize(),
                    bottomBar = {
                        NavigationBar {
                            NavigationBarItem(
                                selected = selectedTab == 0,
                                onClick = { selectedTab = 0 },
                                icon = { Icon(Icons.Default.Download, contentDescription = "Receiver") },
                                label = { Text("Receiver") }
                            )
                            NavigationBarItem(
                                selected = selectedTab == 1,
                                onClick = { selectedTab = 1 },
                                icon = { Icon(Icons.Default.TouchApp, contentDescription = "Trackpad") },
                                label = { Text("Trackpad") }
                            )
                            NavigationBarItem(
                                selected = selectedTab == 2,
                                onClick = { selectedTab = 2 },
                                icon = { Icon(Icons.Default.PlayCircle, contentDescription = "Media") },
                                label = { Text("Media") }
                            )
                            NavigationBarItem(
                                selected = selectedTab == 3,
                                onClick = { selectedTab = 3 },
                                icon = { Icon(Icons.Default.Slideshow, contentDescription = "Present") },
                                label = { Text("Present") }
                            )
                            NavigationBarItem(
                                selected = selectedTab == 4,
                                onClick = { selectedTab = 4 },
                                icon = { Icon(Icons.Default.Bolt, contentDescription = "Commands") },
                                label = { Text("Commands") }
                            )
                            NavigationBarItem(
                                selected = selectedTab == 5,
                                onClick = { selectedTab = 5 },
                                icon = { Icon(Icons.Default.Settings, contentDescription = "More") },
                                label = { Text("More") }
                            )
                        }
                    }
                ) { innerPadding ->
                    Surface(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        color = MaterialTheme.colorScheme.background
                    ) {
                        when (selectedTab) {
                            0 -> DashboardScreen(viewModel = viewModel)
                            1 -> TrackpadScreen(viewModel = viewModel)
                            2 -> MediaControlScreen(viewModel = viewModel)
                            3 -> PresentationScreen(viewModel = viewModel)
                            4 -> RemoteCommandsScreen(viewModel = viewModel)
                            5 -> DeviceAndSettingsScreen(viewModel = viewModel)
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: return

        when (action) {
            Intent.ACTION_SEND -> {
                val uri: android.net.Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                if (uri != null) {
                    viewModel.sendFilesToMac(listOf(uri))
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                }
                if (!uris.isNullOrEmpty()) {
                    viewModel.sendFilesToMac(uris)
                }
            }
        }
    }

    private fun checkAndRequestPermissions() {
        val permissions = mutableListOf(Manifest.permission.CAMERA)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
            permissions.add(Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            permissions.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        val missing = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isNotEmpty()) {
            requestPermissionLauncher.launch(missing.toTypedArray())
        }
    }
}

@Composable
fun DeviceAndSettingsScreen(viewModel: MainViewModel) {
    var subTab by remember { mutableIntStateOf(1) } // Default to 🤖 AI Solver
    Column(modifier = Modifier.fillMaxSize()) {
        ScrollableTabRow(selectedTabIndex = subTab, edgePadding = 12.dp) {
            Tab(selected = subTab == 0, onClick = { subTab = 0 }, text = { Text("Pairing & QR") })
            Tab(selected = subTab == 1, onClick = { subTab = 1 }, text = { Text("🤖 AI Solver") })
            Tab(selected = subTab == 2, onClick = { subTab = 2 }, text = { Text("📹 HD Webcam") })
            Tab(selected = subTab == 3, onClick = { subTab = 3 }, text = { Text("🚀 Scripts & ADB") })
            Tab(selected = subTab == 4, onClick = { subTab = 4 }, text = { Text("✍️ Sketch Pad") })
            Tab(selected = subTab == 5, onClick = { subTab = 5 }, text = { Text("🖥️ Sidecar Display") })
            Tab(selected = subTab == 6, onClick = { subTab = 6 }, text = { Text("History") })
            Tab(selected = subTab == 7, onClick = { subTab = 7 }, text = { Text("Settings") })
        }
        when (subTab) {
            0 -> PairingScreen(viewModel = viewModel)
            1 -> AiSolverScreen(viewModel = viewModel)
            2 -> WebcamScreen(viewModel = viewModel)
            3 -> ScriptLauncherScreen(viewModel = viewModel)
            4 -> SketchPadScreen(viewModel = viewModel)
            5 -> SecondScreenView(viewModel = viewModel)
            6 -> HistoryScreen(viewModel = viewModel)
            7 -> SettingsScreen(viewModel = viewModel)
        }
    }
}
