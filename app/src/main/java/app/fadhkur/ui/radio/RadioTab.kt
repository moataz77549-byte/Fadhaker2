package app.fadhkur.ui.radio

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.service.PlaybackState
import app.fadhkur.service.FadhkurAudioHandler
import app.fadhkur.ui.components.FadhkurBrandMarkComposable
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.ui.theme.CopperAccent
import app.fadhkur.ui.theme.DeepIndigoDark
import app.fadhkur.ui.theme.DeepIndigoPrimary

@Composable
fun RadioTab(
    repository: FadhkurRepository,
    playbackState: PlaybackState,
    favorites: Set<String>,
    onToggleFavorite: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        item {
            Card(
                colors = CardDefaults.cardColors(containerColor = DeepIndigoDark),
                shape = RoundedCornerShape(20.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    FadhkurBrandMarkComposable(sizeDp = 64, isRadio = true)
                    Spacer(modifier = Modifier.height(14.dp))
                    Text(
                        repository.stations.first().nameAr,
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = Color.White
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "الآن: ${repository.stations.first().currentTrack}",
                        color = AcousticTeal,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    Button(
                        onClick = {
                            val s = repository.stations.first()
                            FadhkurAudioHandler.playRadio(s.nameAr, s.currentTrack, s.streamUrl)
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = AcousticTeal),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(
                            imageVector = if (playbackState.isPlaying && playbackState.currentTitle == repository.stations.first().nameAr)
                                Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = null
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("استمع الآن (128 kbps)")
                    }
                }
            }
        }

        item {
            Text(
                "محطات إذاعية أخرى متاحة",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
            )
        }

        items(repository.stations.drop(1)) { station ->
            val isFav = favorites.contains(station.id)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp)
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(Icons.Default.Radio, contentDescription = null, tint = AcousticTeal)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(station.nameAr, fontWeight = FontWeight.Bold)
                        Text(
                            station.currentTrack,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = { onToggleFavorite(station.id) }) {
                        Icon(
                            if (isFav) Icons.Default.Star else Icons.Default.StarBorder,
                            contentDescription = null,
                            tint = CopperAccent
                        )
                    }
                    IconButton(onClick = {
                        FadhkurAudioHandler.playRadio(station.nameAr, station.currentTrack, station.streamUrl)
                    }) {
                        Icon(
                            Icons.Default.PlayCircleFilled,
                            contentDescription = null,
                            tint = DeepIndigoPrimary,
                            modifier = Modifier.size(32.dp)
                        )
                    }
                }
            }
        }
    }
}
