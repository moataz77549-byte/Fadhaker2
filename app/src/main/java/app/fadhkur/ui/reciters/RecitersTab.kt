package app.fadhkur.ui.reciters

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.ui.theme.CopperAccent
import app.fadhkur.ui.theme.DeepIndigoPrimary

@Composable
fun RecitersTab(
    repository: FadhkurRepository,
    favorites: Set<String>,
    onToggleFavorite: (String) -> Unit,
    onPlayTrack: (String, String, String) -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        items(repository.reciters) { reciter ->
            val isFav = favorites.contains(reciter.id)
            Card(
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(CircleShape)
                                .background(AcousticTeal.copy(alpha = 0.15f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Person, contentDescription = null, tint = AcousticTeal)
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                reciter.nameAr,
                                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                            )
                            Text(
                                reciter.riwaya,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                "${reciter.surahsCount} سورة • ${reciter.audioQuality}",
                                color = CopperAccent,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                        IconButton(onClick = { onToggleFavorite(reciter.id) }) {
                            Icon(
                                if (isFav) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = null,
                                tint = CopperAccent
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        Button(
                            onClick = {
                                onPlayTrack("سورة الكهف", reciter.nameAr, "https://audio.fadhkur.app/018.mp3")
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = DeepIndigoPrimary),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("تشغيل تلاوة عينة")
                        }
                    }
                }
            }
        }
    }
}
