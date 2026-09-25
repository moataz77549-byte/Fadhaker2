package app.fadhkur.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.fadhkur.service.PlaybackMode
import app.fadhkur.service.PlaybackState
import app.fadhkur.service.FadhkurAudioHandler
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.ui.theme.DeepIndigoDark
import app.fadhkur.ui.theme.DeepIndigoPrimary

/**
 * Bottom Mini Audio Player Bar
 */
@Composable
fun MiniPlayerBar(
    playbackState: PlaybackState,
    onTogglePlayPause: () -> Unit = { FadhkurAudioHandler.togglePlayPause() }
) {
    Surface(
        color = DeepIndigoDark,
        shadowElevation = 8.dp,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("mini_player_bar")
    ) {
        Column {
            LinearProgressIndicator(
                progress = { 0.42f },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(3.dp),
                color = AcousticTeal,
                trackColor = DeepIndigoPrimary,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                FadhkurBrandMarkComposable(
                    sizeDp = 34,
                    isRadio = playbackState.mode == PlaybackMode.RADIO
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = playbackState.currentTitle,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        maxLines = 1
                    )
                    Text(
                        text = playbackState.currentSubtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = AcousticTeal,
                        maxLines = 1
                    )
                }
                IconButton(onClick = onTogglePlayPause) {
                    Icon(
                        imageVector = if (playbackState.isPlaying) Icons.Default.PauseCircle else Icons.Default.PlayCircle,
                        contentDescription = "تشغيل/إيقاف",
                        tint = AcousticTeal,
                        modifier = Modifier.size(34.dp)
                    )
                }
            }
        }
    }
}
