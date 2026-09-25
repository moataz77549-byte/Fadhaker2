package app.fadhkur.ui.favorites

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.ui.theme.CopperAccent

@Composable
fun FavoritesTab(
    repository: FadhkurRepository,
    favorites: Set<String>,
    onToggleFavorite: (String) -> Unit
) {
    val favStations = repository.stations.filter { favorites.contains(it.id) }
    val favReciters = repository.reciters.filter { favorites.contains(it.id) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 24.dp)
    ) {
        item {
            Text("المحطات المفضلة (${favStations.size})", fontWeight = FontWeight.Bold)
        }
        items(favStations) { s ->
            Card(shape = RoundedCornerShape(14.dp)) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Radio, contentDescription = null, tint = AcousticTeal)
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(s.nameAr, fontWeight = FontWeight.Bold)
                        Text(s.currentTrack, style = MaterialTheme.typography.bodySmall)
                    }
                    IconButton(onClick = { onToggleFavorite(s.id) }) {
                        Icon(Icons.Default.Star, contentDescription = null, tint = CopperAccent)
                    }
                }
            }
        }

        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text("القراء المفضلون (${favReciters.size})", fontWeight = FontWeight.Bold)
        }
        items(favReciters) { r ->
            Card(shape = RoundedCornerShape(14.dp)) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Person, contentDescription = null, tint = AcousticTeal)
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(r.nameAr, fontWeight = FontWeight.Bold)
                        Text(r.riwaya, style = MaterialTheme.typography.bodySmall)
                    }
                    IconButton(onClick = { onToggleFavorite(r.id) }) {
                        Icon(Icons.Default.Star, contentDescription = null, tint = CopperAccent)
                    }
                }
            }
        }
    }
}
