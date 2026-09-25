package app.fadhkur.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.fadhkur.repository.FirebaseAuthRepository
import app.fadhkur.repository.FirestoreRepository
import app.fadhkur.repository.FadhkurRepository
import app.fadhkur.service.FadhkurAudioHandler
import app.fadhkur.ui.auth.AuthScreen
import app.fadhkur.ui.components.MiniPlayerBar
import app.fadhkur.ui.components.FadhkurBrandMarkComposable
import app.fadhkur.ui.downloads.DownloadsTab
import app.fadhkur.ui.favorites.FavoritesTab
import app.fadhkur.ui.home.QuranHomeTab
import app.fadhkur.ui.mushaf.MushafReaderView
import app.fadhkur.ui.playlists.PlaylistsTab
import app.fadhkur.ui.radio.RadioTab
import app.fadhkur.ui.reciters.RecitersTab
import app.fadhkur.ui.theme.AcousticTeal
import app.fadhkur.viewmodel.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainAppScreen(
    viewModel: MainViewModel,
    isDark: Boolean,
    onToggleDark: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    var showSearchDialog by remember { mutableStateOf(false) }
    var showMushafReader by remember { mutableStateOf<Int?>(null) }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }

    val playbackState by viewModel.playbackState.collectAsStateWithLifecycle()
    val favorites by viewModel.favorites.collectAsStateWithLifecycle()
    val playlists by viewModel.playlists.collectAsStateWithLifecycle()
    val downloads by viewModel.downloads.collectAsStateWithLifecycle()
    val featureFlags by viewModel.repository.featureFlags.collectAsStateWithLifecycle()

    if (showMushafReader != null) {
        MushafReaderView(
            pageNumber = showMushafReader!!,
            onClose = { showMushafReader = null }
        )
        return
    }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        FadhkurBrandMarkComposable(sizeDp = 32, isRadio = true)
                        Text("فذكر", fontWeight = FontWeight.Bold)
                    }
                },
                actions = {
                    IconButton(onClick = { showSearchDialog = true }) {
                        Icon(Icons.Default.Search, contentDescription = "بحث")
                    }
                    IconButton(onClick = onToggleDark) {
                        Icon(
                            imageVector = if (isDark) Icons.Default.LightMode else Icons.Default.DarkMode,
                            contentDescription = "المظهر"
                        )
                    }
                }
            )
        },
        bottomBar = {
            Column {
                MiniPlayerBar(
                    playbackState = playbackState,
                    onTogglePlayPause = { viewModel.togglePlayPause() }
                )
                NavigationBar {
                    NavigationBarItem(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        icon = { Icon(Icons.Default.Home, contentDescription = null) },
                        label = { Text("الرئيسية") }
                    )
                    if (featureFlags.radioEnabled) {
                        NavigationBarItem(
                            selected = selectedTab == 1,
                            onClick = { selectedTab = 1 },
                            icon = { Icon(Icons.Default.Radio, contentDescription = null) },
                            label = { Text("الإذاعة") }
                        )
                    }
                    NavigationBarItem(
                        selected = selectedTab == 2,
                        onClick = { selectedTab = 2 },
                        icon = { Icon(Icons.Default.RecordVoiceOver, contentDescription = null) },
                        label = { Text("القراء") }
                    )
                    NavigationBarItem(
                        selected = selectedTab == 3,
                        onClick = { selectedTab = 3 },
                        icon = { Icon(Icons.Default.Star, contentDescription = null) },
                        label = { Text("المفضلة") }
                    )
                    NavigationBarItem(
                        selected = selectedTab == 4,
                        onClick = { selectedTab = 4 },
                        icon = { Icon(Icons.Default.DownloadDone, contentDescription = null) },
                        label = { Text("التنزيلات") }
                    )
                    NavigationBarItem(
                        selected = selectedTab == 5,
                        onClick = { selectedTab = 5 },
                        icon = { Icon(Icons.Default.PlaylistPlay, contentDescription = null) },
                        label = { Text("القوائم") }
                    )
                    NavigationBarItem(
                        selected = selectedTab == 6,
                        onClick = { selectedTab = 6 },
                        icon = { Icon(Icons.Default.Person, contentDescription = null) },
                        label = { Text("الحساب") }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(modifier = Modifier.padding(innerPadding)) {
            when (selectedTab) {
                0 -> QuranHomeTab(
                    repository = viewModel.repository,
                    onOpenMushaf = { page -> showMushafReader = page },
                    onPlaySurah = { num, name -> viewModel.playSurah(num, name) },
                    onDownloadSurah = { num, name -> viewModel.startDownload(num, name) }
                )
                1 -> RadioTab(
                    repository = viewModel.repository,
                    playbackState = playbackState,
                    favorites = favorites,
                    onToggleFavorite = { id -> viewModel.toggleFavorite(id) }
                )
                2 -> RecitersTab(
                    repository = viewModel.repository,
                    favorites = favorites,
                    onToggleFavorite = { id -> viewModel.toggleFavorite(id) },
                    onPlayTrack = { sName, rName, url ->
                        viewModel.playTrack(sName, rName, url)
                    }
                )
                3 -> FavoritesTab(
                    repository = viewModel.repository,
                    favorites = favorites,
                    onToggleFavorite = { id -> viewModel.toggleFavorite(id) }
                )
                4 -> DownloadsTab(
                    downloads = downloads,
                    onPlay = { d ->
                        FadhkurAudioHandler.playOfflineTrack(d.surahNameAr, d.reciterNameAr, d.localPath ?: "")
                    },
                    onDelete = { id -> viewModel.deleteDownload(id) }
                )
                5 -> PlaylistsTab(
                    playlists = playlists,
                    onCreatePlaylist = { showNewPlaylistDialog = true },
                    onDeletePlaylist = { id -> viewModel.deletePlaylist(id) }
                )
                6 -> AuthScreen(
                    authRepository = viewModel.authRepository,
                    firestoreRepository = viewModel.firestoreRepository,
                    onAuthSuccess = { selectedTab = 0 }
                )
            }
        }
    }

    if (showNewPlaylistDialog) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showNewPlaylistDialog = false },
            title = { Text("إنشاء قائمة تشغيل جديدة") },
            text = {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("اسم القائمة") }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    if (name.isNotBlank()) {
                        viewModel.createPlaylist(name)
                        showNewPlaylistDialog = false
                    }
                }) {
                    Text("إنشاء")
                }
            },
            dismissButton = {
                TextButton(onClick = { showNewPlaylistDialog = false }) {
                    Text("إلغاء")
                }
            }
        )
    }

    if (showSearchDialog) {
        var query by remember { mutableStateOf("") }
        val filteredStations = viewModel.repository.stations.filter {
            it.nameAr.contains(query) || it.currentTrack.contains(query)
        }
        val filteredReciters = viewModel.repository.reciters.filter {
            it.nameAr.contains(query) || it.riwaya.contains(query)
        }

        AlertDialog(
            onDismissRequest = { showSearchDialog = false },
            title = { Text("البحث السريع") },
            text = {
                Column {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text("اكتب اسم سورة أو قارئ أو إذاعة") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    if (query.isNotBlank()) {
                        Text("النتائج: ${filteredStations.size + filteredReciters.size}", fontWeight = FontWeight.Bold)
                        filteredStations.forEach { s ->
                            TextButton(onClick = {
                                viewModel.playStation(s.nameAr, s.streamUrl)
                                showSearchDialog = false
                            }) {
                                Text("محطة: ${s.nameAr}")
                            }
                        }
                        filteredReciters.forEach { r ->
                            Text(r.nameAr, color = AcousticTeal, modifier = Modifier.padding(vertical = 4.dp))
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showSearchDialog = false }) { Text("إغلاق") }
            }
        )
    }
}

/**
 * Overload for backward compatibility
 */
@Composable
fun MainAppScreen(
    repository: FadhkurRepository,
    authRepository: FirebaseAuthRepository,
    firestoreRepository: FirestoreRepository,
    isDark: Boolean,
    onToggleDark: () -> Unit
) {
    val viewModel = remember {
        MainViewModel(
            repository = repository,
            authRepository = authRepository,
            firestoreRepository = firestoreRepository
        )
    }
    MainAppScreen(
        viewModel = viewModel,
        isDark = isDark,
        onToggleDark = onToggleDark
    )
}
