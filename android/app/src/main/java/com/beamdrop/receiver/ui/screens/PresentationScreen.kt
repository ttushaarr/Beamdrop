package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.beamdrop.receiver.ui.MainViewModel
import kotlinx.coroutines.delay

@Composable
fun PresentationScreen(viewModel: MainViewModel) {
    var timerRunning by remember { mutableStateOf(false) }
    var elapsedSeconds by remember { mutableIntStateOf(0) }

    LaunchedEffect(timerRunning) {
        while (timerRunning) {
            delay(1000L)
            elapsedSeconds++
        }
    }

    val minutes = elapsedSeconds / 60
    val seconds = elapsedSeconds % 60
    val timerText = "%02d:%02d".format(minutes, seconds)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "Slide Presentation Remote",
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
                )
                Text(
                    text = "Navigate Keynote, PowerPoint, or PDF presentations",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Fullscreen / Start Presentation Action
            IconButton(onClick = { viewModel.sendKey("F5") }) {
                Icon(Icons.Default.Fullscreen, contentDescription = "Start / Fullscreen", tint = MaterialTheme.colorScheme.primary)
            }
        }

        // Presentation Timer Card
        ElevatedCard(
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("Elapsed Time", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(timerText, style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold))
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(onClick = { timerRunning = !timerRunning }) {
                        Icon(if (timerRunning) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null)
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(if (timerRunning) "Pause" else "Start")
                    }

                    OutlinedButton(onClick = {
                        timerRunning = false
                        elapsedSeconds = 0
                    }) {
                        Text("Reset")
                    }
                }
            }
        }

        // Main Slide Navigation Clicker Buttons
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Next Slide (Big Top Button)
            Button(
                onClick = { viewModel.sendKey("Right") },
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier
                    .weight(1.3f)
                    .fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.ArrowForward, contentDescription = null, modifier = Modifier.size(48.dp))
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("NEXT SLIDE", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Tap anywhere or swipe right", fontSize = 12.sp, color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.8f))
                }
            }

            // Previous Slide (Bottom Button)
            FilledTonalButton(
                onClick = { viewModel.sendKey("Left") },
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier
                    .weight(0.9f)
                    .fillMaxWidth()
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.ArrowBack, contentDescription = null, modifier = Modifier.size(32.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("PREVIOUS SLIDE", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        // Extra Presentation Actions (Black Screen, White Screen, Esc)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = { viewModel.sendKey("B") },
                modifier = Modifier.weight(1f)
            ) {
                Text("Black (B)")
            }

            OutlinedButton(
                onClick = { viewModel.sendKey("Escape") },
                modifier = Modifier.weight(1f)
            ) {
                Text("Exit (Esc)")
            }
        }
    }
}
