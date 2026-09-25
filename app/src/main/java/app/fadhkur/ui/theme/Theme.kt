package app.fadhkur.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val FadhkurDarkColorScheme = darkColorScheme(
  primary = AcousticTeal,
  onPrimary = DeepIndigoDark,
  primaryContainer = DeepIndigoPrimary,
  onPrimaryContainer = Color.White,
  secondary = CopperAccent,
  onSecondary = Color.White,
  tertiary = AcousticTeal,
  onTertiary = Color.White,
  background = NightBackground,
  onBackground = DarkTextPrimary,
  surface = DarkSurface,
  onSurface = DarkTextPrimary,
  surfaceVariant = Color(0xFF1D2C42),
  onSurfaceVariant = DarkTextSecondary,
)

private val FadhkurLightColorScheme = lightColorScheme(
  primary = DeepIndigoPrimary,
  onPrimary = Color.White,
  primaryContainer = Color(0xFFD6E2FB),
  onPrimaryContainer = DeepIndigoDark,
  secondary = AcousticTeal,
  onSecondary = Color.White,
  tertiary = CopperAccent,
  onTertiary = Color.White,
  background = PearlBackground,
  onBackground = LightTextPrimary,
  surface = LightSurface,
  onSurface = LightTextPrimary,
  surfaceVariant = Color(0xFFE5E2DC),
  onSurfaceVariant = LightTextSecondary,
)

@Composable
fun FadhkurTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  val colorScheme = if (darkTheme) FadhkurDarkColorScheme else FadhkurLightColorScheme
  MaterialTheme(
    colorScheme = colorScheme,
    typography = Typography,
    content = content,
  )
}

// Backward-compatible alias for test harness
@Composable
fun MyApplicationTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  dynamicColor: Boolean = false,
  content: @Composable () -> Unit,
) {
  FadhkurTheme(darkTheme = darkTheme, content = content)
}
