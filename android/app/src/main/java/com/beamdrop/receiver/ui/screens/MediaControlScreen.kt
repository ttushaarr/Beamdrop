package com.beamdrop.receiver.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
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

@Composable
fun MediaControlScreen(viewModel: MainViewModel) {
    var volume by remember { mutableFloatStateOf(0.7f) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        // Header
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "Media Control",
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
            )
            Text(
                text = "Control playback, volume, and tracks on your MacBook",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Large Album Art / Media Symbol Card
        ElevatedCard(
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier.size(200.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
        ) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Default.MusicNote,
                    contentDescription = null,
                    modifier = Modifier.size(96.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer
                )
            }
        }

        Text(
            text = "MacBook Audio Player",
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
        )

        // Playback Controls Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            FilledTonalIconButton(
                onClick = { viewModel.sendMediaAction("prev") },
                modifier = Modifier.size(56.dp)
            ) {
                Icon(Icons.Default.SkipPrevious, contentDescription = "Previous Track", modifier = Modifier.size(28.dp))
            }

            FilledIconButton(
                onClick = { viewModel.sendMediaAction("playPause") },
                shape = CircleShape,
                modifier = Modifier.size(76.dp)
            ) {
                Icon(Icons.Default.PlayArrow, contentDescription = "Play / Pause", modifier = Modifier.size(40.dp))
            }

            FilledTonalIconButton(
                onClick = { viewModel.sendMediaAction("next") },
                modifier = Modifier.size(56.dp)
            ) {
                Icon(Icons.Default.SkipNext, contentDescription = "Next Track", modifier = Modifier.size(28.dp))
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Volume Section
        Card(
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.VolumeUp, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Volume", fontWeight = FontWeight.Bold)
                    }

                    TextButton(onClick = { viewModel.sendMediaAction("mute") }) {
                        Icon(Icons.Default.VolumeOff, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Mute")
                    }
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    IconButton(onClick = {
                        volume = (volume - 0.1f).coerceIn(0f, 1f)
                        viewModel.sendMediaAction("volume", volume)
                    }) {
                        Icon(Icons.Default.VolumeDown, contentDescription = "Volume Down")
                    }

                    Slider(
                        value = volume,
                        onValueChange = {
                            volume = it
                            viewModel.sendMediaAction("volume", it)
                        },
                        modifier = Modifier.weight(1f)
                    )

                    IconButton(onClick = {
                        volume = (volume + 0.1f).coerceIn(0f, 1f)
                        viewModel.sendMediaAction("volume", volume)
                    }) {
                        Icon(Icons.Default.VolumeUp, contentDescription = "Volume Up")
                    }
                }
            }
        }
    }
}
