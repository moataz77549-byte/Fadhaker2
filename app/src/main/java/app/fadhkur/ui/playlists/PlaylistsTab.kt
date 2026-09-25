package app.fadhkur.ui.playlists

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontWeight.Companion.SemiBold
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.fadhkur.model.Playlist
import app.fadhkur.service.FadhkurAudioHandler
import app.fadhkur.ui.theme.AcousticTeal

@Composable
fun PlaylistsTab(
    playlists: List<Playlist>,
    onCreatePlaylist: () -> Unit,
    onDeletePlaylist: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        item {
            Button(
                onClick = onCreatePlaylist,
                colors = ButtonDefaults.buttonColors(containerColor = AcousticTeal),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(6.dp))
                Text("إنشاء قائمة تشغيل جديدة")
            }
        }

        items(playlists) { pl ->
            Card(shape = RoundedCornerShape(14.dp)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(pl.name, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        IconButton(onClick = { onDeletePlaylist(pl.id) }) {
                            Icon(Icons.Default.DeleteOutline, contentDescription = null, tint = Color.Red)
                        }
                    }
                    Text(
                        "${pl.items.size} تلاوات في القائمة",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    pl.items.forEach { item ->
                        ListItem(
                            headlineContent = { Text(item.title, fontWeight = SemiBold) },
                            supportingContent = { Text(item.subtitle) },
                            trailingContent = {
                                IconButton(onClick = {
                                    FadhkurAudioHandler.playQuranTrack(item.title, item.subtitle, item.audioUrl)
                                }) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = AcousticTeal)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
