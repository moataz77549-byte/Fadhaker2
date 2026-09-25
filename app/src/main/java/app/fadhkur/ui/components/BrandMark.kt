package app.fadhkur.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.fadhkur.ui.theme.*

/**
 * Geometric Brand Mark Composable for Fadhkur (فذكر)
 * Features an open Quran on a wooden Rihal stand with an acoustic soundwave recitation arc.
 */
@Composable
fun FadhkurBrandMarkComposable(
    modifier: Modifier = Modifier,
    sizeDp: Int = 48,
    isRadio: Boolean = false,
) {
    val primary = DeepIndigoPrimary
    val teal = AcousticTeal
    val copper = CopperAccent
    val pearl = PearlBackground

    Canvas(modifier = modifier.size(sizeDp.dp).testTag("brand_mark")) {
        val w = size.width
        val h = size.height

        // 1. Background Shield
        drawRoundRect(
            color = primary,
            size = Size(w, h),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(w * 0.22f, h * 0.22f)
        )

        // 2. Recitation Soundwave Arc (Teal)
        val outerArcPath = Path().apply {
            arcTo(
                rect = Rect(
                    offset = Offset(w * 0.22f, h * 0.16f),
                    size = Size(w * 0.56f, h * 0.56f)
                ),
                startAngleDegrees = 200f,
                sweepAngleDegrees = 140f,
                forceMoveTo = false
            )
        }
        drawPath(
            path = outerArcPath,
            color = teal,
            style = Stroke(width = w * 0.038f, cap = StrokeCap.Round)
        )

        // Inner Recitation Arc (Copper)
        val innerArcPath = Path().apply {
            arcTo(
                rect = Rect(
                    offset = Offset(w * 0.32f, h * 0.26f),
                    size = Size(w * 0.36f, h * 0.36f)
                ),
                startAngleDegrees = 210f,
                sweepAngleDegrees = 120f,
                forceMoveTo = false
            )
        }
        drawPath(
            path = innerArcPath,
            color = copper,
            style = Stroke(width = w * 0.03f, cap = StrokeCap.Round)
        )

        if (isRadio) {
            val radioPulse = Path().apply {
                arcTo(
                    rect = Rect(
                        offset = Offset(w * 0.12f, h * 0.06f),
                        size = Size(w * 0.76f, h * 0.76f)
                    ),
                    startAngleDegrees = 200f,
                    sweepAngleDegrees = 140f,
                    forceMoveTo = false
                )
            }
            drawPath(
                path = radioPulse,
                color = teal.copy(alpha = 0.8f),
                style = Stroke(width = w * 0.024f, cap = StrokeCap.Round)
            )
        }

        // 3. Open Holy Quran Pages
        val leftPage = Path().apply {
            moveTo(w * 0.48f, h * 0.54f)
            quadraticBezierTo(w * 0.38f, h * 0.49f, w * 0.26f, h * 0.53f)
            lineTo(w * 0.26f, h * 0.71f)
            quadraticBezierTo(w * 0.38f, h * 0.67f, w * 0.48f, h * 0.73f)
            close()
        }
        drawPath(path = leftPage, color = pearl)

        val rightPage = Path().apply {
            moveTo(w * 0.52f, h * 0.54f)
            quadraticBezierTo(w * 0.62f, h * 0.49f, w * 0.74f, h * 0.53f)
            lineTo(w * 0.74f, h * 0.71f)
            quadraticBezierTo(w * 0.62f, h * 0.67f, w * 0.52f, h * 0.73f)
            close()
        }
        drawPath(path = rightPage, color = Color.White)

        // 4. Wooden Rihal Stand Base (Copper)
        drawLine(
            color = copper,
            start = Offset(w * 0.38f, h * 0.73f),
            end = Offset(w * 0.62f, h * 0.85f),
            strokeWidth = w * 0.04f,
            cap = StrokeCap.Round
        )
        drawLine(
            color = copper,
            start = Offset(w * 0.62f, h * 0.73f),
            end = Offset(w * 0.38f, h * 0.85f),
            strokeWidth = w * 0.04f,
            cap = StrokeCap.Round
        )
        drawLine(
            color = copper,
            start = Offset(w * 0.30f, h * 0.83f),
            end = Offset(w * 0.70f, h * 0.83f),
            strokeWidth = w * 0.035f,
            cap = StrokeCap.Round
        )

        // 5. Bookmark Ribbon (Teal)
        drawLine(
            color = teal,
            start = Offset(w * 0.50f, h * 0.54f),
            end = Offset(w * 0.50f, h * 0.78f),
            strokeWidth = w * 0.024f,
            cap = StrokeCap.Round
        )
    }
}
