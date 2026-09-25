package app.fadhkur.ui.downloads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.fadhkur.model.DownloadStatus
import app.fadhkur.model.DownloadTask
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.ui.theme.CopperAccent

@Composable
fun DownloadsTab(
    downloads: List<DownloadTask>,
    onPlay: (DownloadTask) -> Unit,
    onDelete: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        items(downloads) { d ->
            val isCompleted = d.status == DownloadStatus.COMPLETED
            Card(shape = RoundedCornerShape(16.dp)) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(d.surahNameAr, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                        Surface(
                            color = if (isCompleted) AcousticTeal.copy(alpha = 0.15f) else CopperAccent.copy(alpha = 0.15f),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text(
                                text = if (isCompleted) "موثق (SHA-256)" else "تحميل ${d.progressPercent}%",
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                color = if (isCompleted) AcousticTeal else CopperAccent,
                                fontWeight = FontWeight.Bold,
                                fontSize = 11.sp
                            )
                        }
                    }
                    Text(d.reciterNameAr, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                    Spacer(modifier = Modifier.height(10.dp))
                    if (isCompleted) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "الحجم: 28.4 MB • تشغيل محلي",
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Row {
                                IconButton(onClick = { onPlay(d) }) {
                                    Icon(Icons.Default.PlayArrow, contentDescription = null, tint = AcousticTeal)
                                }
                                IconButton(onClick = { onDelete(d.id) }) {
                                    Icon(Icons.Default.Delete, contentDescription = null, tint = Color.Red.copy(alpha = 0.7f))
                                }
                            }
                        }
                    } else {
                        LinearProgressIndicator(
                            progress = { d.progressPercent / 100f },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(4.dp),
                            color = AcousticTeal
                        )
                    }
                }
            }
        }
    }
}
