package com.example.blecam.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// ========== ЦВЕТОВАЯ СХЕМА MATERIAL 3 ==========
// Вся схема строго тёмная, никакой светлой темы

private val DarkColorScheme = darkColorScheme(
    primary = AccentBlue,
    onPrimary = BackgroundDark,
    primaryContainer = AccentBlueDim,
    onPrimaryContainer = AccentBlue,

    secondary = StatusConnected,
    onSecondary = BackgroundDark,

    background = BackgroundDark,
    onBackground = TextPrimary,

    surface = SurfaceDark,
    onSurface = TextPrimary,
    surfaceVariant = SurfaceElevated,
    onSurfaceVariant = TextSecondary,

    error = Color(0xFFFF4444),
    onError = BackgroundDark,
)

@Composable
fun BleCamTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = AppTypography,
        content = content
    )
}
