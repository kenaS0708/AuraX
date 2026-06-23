package com.example.blecam.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.example.blecam.R

// ========== ШРИФТЫ ==========
// Space Grotesk — для заголовков и крупного текста
// JetBrains Mono — для статусных строк и технических данных

/**
 * Space Grotesk — геометрический гротеск, читается на тёмном фоне
 * Файл: res/font/space_grotesk.ttf
 */
val SpaceGrotesk = FontFamily(
    Font(R.font.space_grotesk, FontWeight.Normal),
    Font(R.font.space_grotesk_bold, FontWeight.Bold),
)

/**
 * JetBrains Mono — моноширинный для технических строк
 * Файл: res/font/jetbrains_mono.ttf
 */
val JetBrainsMono = FontFamily(
    Font(R.font.jetbrains_mono, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
)

// ========== ТИПОГРАФИКА ==========
val AppTypography = Typography(
    // Крупный заголовок (не используется в UI, но нужен для системы)
    displayLarge = TextStyle(
        fontFamily = SpaceGrotesk,
        fontWeight = FontWeight.Bold,
        fontSize = 57.sp,
        color = TextPrimary
    ),
    // Заголовок карточки с ответом ИИ
    headlineMedium = TextStyle(
        fontFamily = SpaceGrotesk,
        fontWeight = FontWeight.Normal,
        fontSize = 22.sp,
        lineHeight = 32.sp,
        color = TextPrimary
    ),
    // Основной текст UI
    bodyLarge = TextStyle(
        fontFamily = SpaceGrotesk,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        color = TextPrimary
    ),
    // Статусные строки (моноширинный)
    labelSmall = TextStyle(
        fontFamily = JetBrainsMono,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        letterSpacing = 0.5.sp,
        color = TextSecondary
    ),
    // Метки и теги
    labelMedium = TextStyle(
        fontFamily = JetBrainsMono,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        letterSpacing = 0.5.sp,
        color = TextSecondary
    ),
)
