package app.fadhkur.ui.mushaf

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.fadhkur.ui.theme.DarkTextPrimary
import app.fadhkur.ui.theme.DeepIndigoDark
import app.fadhkur.ui.theme.DeepIndigoPrimary
import app.fadhkur.ui.theme.PearlBackground

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MushafReaderView(
    pageNumber: Int,
    onClose: () -> Unit
) {
    var currentPage by remember { mutableIntStateOf(pageNumber) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("صفحة $currentPage من 604") },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق")
                    }
                }
            )
        },
        bottomBar = {
            Surface(color = DeepIndigoDark) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = { if (currentPage > 1) currentPage-- },
                        enabled = currentPage > 1
                    ) {
                        Icon(Icons.Default.ArrowForward, contentDescription = null, tint = Color.White)
                    }
                    Text("الصفحة $currentPage من 604", color = Color.White, fontWeight = FontWeight.Bold)
                    IconButton(
                        onClick = { if (currentPage < 604) currentPage++ },
                        enabled = currentPage < 604
                    ) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null, tint = Color.White)
                    }
                }
            }
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(PearlBackground)
                .padding(20.dp),
            contentAlignment = Alignment.Center
        ) {
            Card(
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White),
                elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Surface(
                        color = DeepIndigoPrimary.copy(alpha = 0.08f),
                        shape = RoundedCornerShape(8.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("الجزء 15", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                            Text(
                                "سُورَةُ الكَهْفِ",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = DeepIndigoPrimary
                            )
                            Text("الحزب 29", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                        color = DeepIndigoPrimary
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "الْحَمْدُ لِلَّهِ الَّذِي أَنزَلَ عَلَىٰ عَبْدِهِ الْكِتَابَ وَلَمْ يَجْعَل لَّهُ عِوَجًا ﴿١﴾ قَيِّمًا لِّيُنذِرَ بَأْسًا شَدِيدًا مِّن لَّدُنْهُ وَيُبَشِّرَ الْمُؤْمِنِينَ الَّذِينَ يَعْمَلُونَ الصَّالِحَاتِ أَنَّ لَهُمْ أَجْرًا حَسَنًا ﴿٢﴾ مَّاكِثِينَ فِيهِ أَبَدًا ﴿٣﴾ وَيُنذِرَ الَّذِينَ قَالُوا اتَّخَذَ اللَّهُ وَلَدًا ﴿٤﴾",
                        fontSize = 18.sp,
                        lineHeight = 36.sp,
                        textAlign = TextAlign.Justify,
                        color = DarkTextPrimary
                    )
                }
            }
        }
    }
}
