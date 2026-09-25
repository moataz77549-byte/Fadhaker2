package app.fadhkur.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.fadhkur.model.QuranData
import app.fadhkur.model.Surah
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.ui.theme.*

@Composable
fun QuranHomeTab(
    repository: FadhkurRepository,
    onOpenMushaf: (Int) -> Unit,
    onPlaySurah: (Int, String) -> Unit,
    onDownloadSurah: (Int, String) -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val filteredSurahs = remember(searchQuery) {
        QuranData.searchSurahs(searchQuery)
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        // 1. Daily Reading Card
        item {
            Card(
                colors = CardDefaults.cardColors(containerColor = DeepIndigoPrimary),
                shape = RoundedCornerShape(18.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenMushaf(293) }
            ) {
                Column(modifier = Modifier.padding(18.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("متابعة الورد اليومي", color = AcousticTeal, fontWeight = FontWeight.Bold)
                        Icon(Icons.Default.Bookmark, contentDescription = null, tint = CopperAccent)
                    }
                    Spacer(modifier = Modifier.height(10.dp))
                    Text(
                        "سورة الكهف — صفحة 293",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = Color.White
                    )
                    Text(
                        "آخر قراءة: الآية 10 • الجزء الخامس عشر",
                        style = MaterialTheme.typography.bodySmall,
                        color = DarkTextSecondary
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("فتح المصحف", color = AcousticTeal, fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(
                            Icons.Default.ArrowForward,
                            contentDescription = null,
                            tint = AcousticTeal,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        }

        // 2. Prayer Times Card
        item {
            val pt = repository.prayerTimes
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.AccessTime,
                                contentDescription = null,
                                tint = AcousticTeal,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text("مواقيت الصلاة — ${pt.city}", fontWeight = FontWeight.Bold)
                        }
                        Text(
                            "${pt.nextPrayerName} بعد ${pt.nextPrayerRemaining}",
                            color = CopperAccent,
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceAround
                    ) {
                        PrayerTimeCol("الفجر", pt.fajr)
                        PrayerTimeCol("الظهر", pt.dhuhr)
                        PrayerTimeCol("العصر", pt.asr)
                        PrayerTimeCol("المغرب", pt.maghrib, isNext = true)
                        PrayerTimeCol("العشاء", pt.isha)
                    }
                }
            }
        }

        // 3. Surah Search & Index Header
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "فهرس السور القرآنية (114 سورة)",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "${filteredSurahs.size} سورة",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    placeholder = { Text("ابحث عن سورة بالاسم أو الرقم...") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(Icons.Default.Close, contentDescription = "مسح")
                            }
                        }
                    },
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
            }
        }

        items(filteredSurahs, key = { it.number }) { surah ->
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                shape = RoundedCornerShape(14.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenMushaf(surah.page) }
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(DeepIndigoPrimary.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "${surah.number}",
                            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
                            color = DeepIndigoPrimary
                        )
                    }

                    Column(modifier = Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = surah.nameAr,
                                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Surface(
                                color = DeepIndigoPrimary.copy(alpha = 0.08f),
                                shape = RoundedCornerShape(4.dp)
                            ) {
                                Text(
                                    text = "جزء ${surah.juz}",
                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
                                    fontSize = 10.sp,
                                    color = DeepIndigoPrimary,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                        Text(
                            text = "${surah.versesCount} آية • ${surah.type} • ${surah.nameEn}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    IconButton(onClick = { onPlaySurah(surah.number, surah.nameAr) }) {
                        Icon(Icons.Default.PlayCircleOutline, contentDescription = "تشغيل", tint = AcousticTeal)
                    }

                    IconButton(onClick = { onDownloadSurah(surah.number, surah.nameAr) }) {
                        Icon(Icons.Default.DownloadForOffline, contentDescription = "تنزيل", tint = CopperAccent)
                    }

                    Text(
                        text = "ص ${surah.page}",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                        color = CopperAccent
                    )
                }
            }
        }
    }
}

@Composable
fun PrayerTimeCol(name: String, time: String, isNext: Boolean = false) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = name,
            fontSize = 12.sp,
            color = if (isNext) AcousticTeal else MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = if (isNext) FontWeight.Bold else FontWeight.Normal
        )
        Spacer(modifier = Modifier.height(4.dp))
        Surface(
            color = if (isNext) AcousticTeal.copy(alpha = 0.15f) else Color.Transparent,
            shape = RoundedCornerShape(8.dp)
        ) {
            Text(
                text = time,
                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
                color = if (isNext) AcousticTeal else MaterialTheme.colorScheme.onSurface
            )
        }
    }
}
