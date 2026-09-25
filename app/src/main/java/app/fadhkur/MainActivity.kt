package app.fadhkur

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import app.fadhkur.ui.MainAppScreen
import app.fadhkur.ui.theme.FadhkurTheme
import app.fadhkur.viewmodel.MainViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            var isDark by remember { mutableStateOf(false) }
            FadhkurTheme(darkTheme = isDark) {
                MainAppScreen(
                    viewModel = viewModel,
                    isDark = isDark,
                    onToggleDark = { isDark = !isDark }
                )
            }
        }
    }
}

/**
 * Retained for backward screenshot test compatibility
 */
@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(text = "فذكر — $name", modifier = modifier)
}
