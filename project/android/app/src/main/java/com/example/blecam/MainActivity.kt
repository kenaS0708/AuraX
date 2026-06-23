package com.example.blecam

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.blecam.ui.theme.*
import com.example.blecam.viewmodel.MainViewModel
import com.example.blecam.viewmodel.UiPhase
import kotlinx.coroutines.launch

/**
 * MainActivity — единственная Activity приложения.
 *
 * Запрашивает BLE-разрешения при старте и отображает полноэкранный Compose UI.
 */
class MainActivity : ComponentActivity() {

    // ========== PERMISSION REQUEST ==========

    /** Список необходимых разрешений */
    private val requiredPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT
        )
    } else {
        arrayOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_ADMIN,
            Manifest.permission.ACCESS_FINE_LOCATION
        )
    }

    /** Результат запроса разрешений */
    private var onPermissionsResult: ((Boolean) -> Unit)? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        onPermissionsResult?.invoke(allGranted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Полноэкранный режим — скрываем системные бары
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.setDecorFitsSystemWindows(false)

        setContent {
            BleCamTheme {
                val viewModel: MainViewModel = viewModel()

                // Запрашиваем разрешения при запуске
                LaunchedEffect(Unit) {
                    requestBlePermissions()
                }

                BleCamApp(
                    viewModel = viewModel,
                    onRequestPermissions = { requestBlePermissions() }
                )
            }
        }
    }

    /** Запрашивает BLE разрешения если не выданы */
    private fun requestBlePermissions() {
        val notGranted = requiredPermissions.filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
        if (notGranted.isNotEmpty()) {
            permissionLauncher.launch(notGranted.toTypedArray())
        }
    }
}

// ========== COMPOSE UI ==========

/**
 * Корневой Compose-экран приложения.
 * Полностью иммерсивный — без AppBar, без меню.
 */
@Composable
fun BleCamApp(
    viewModel: MainViewModel,
    onRequestPermissions: () -> Unit
) {
    val uiPhase by viewModel.uiPhase.collectAsState()
    val statusText by viewModel.statusText.collectAsState()
    val lastPhoto by viewModel.lastPhoto.collectAsState()
    val aiResponse by viewModel.aiResponse.collectAsState()
    val isBleConnected by viewModel.isBleConnected.collectAsState()
    val receiveProgress by viewModel.receiveProgress.collectAsState()

    // Состояние экрана настроек
    var showSettings by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BackgroundDark)
    ) {
        // ---- СЛОЙ 1: Размытое превью фото (задний план) ----
        lastPhoto?.let { photoBytes ->
            PhotoBackground(photoBytes = photoBytes)
        }

        // ---- СЛОЙ 2: Градиентный оверлей поверх фото ----
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color.Transparent,
                            BackgroundDark.copy(alpha = 0.85f)
                        ),
                        radius = 900f
                    )
                )
        )

        // ---- СЛОЙ 3: Основной UI ----
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Spacer(modifier = Modifier.height(40.dp))

            // ---- Центральная кнопка ----
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                CaptureButton(
                    phase = uiPhase,
                    progress = receiveProgress,
                    onClick = { viewModel.onCaptureButtonClick() }
                )
            }

            // ---- Карточка ответа ИИ ----
            AnimatedVisibility(
                visible = aiResponse != null,
                enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
                exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
            ) {
                aiResponse?.let { text ->
                    AiResponseCard(
                        text = text,
                        onDismiss = { viewModel.dismissAiResponse() }
                    )
                }
            }

            // ---- Статусная полоса внизу ----
            StatusBar(
                statusText = statusText,
                isBleConnected = isBleConnected,
                onLongPress = { showSettings = true }
            )
        }

        // ---- Экран настроек (поверх всего) ----
        if (showSettings) {
            SettingsScreen(
                viewModel = viewModel,
                onDismiss = { showSettings = false }
            )
        }
    }
}

/**
 * Размытый фон с последним снятым фото.
 * Появляется с fade-in анимацией.
 */
@Composable
fun PhotoBackground(photoBytes: ByteArray) {
    val bitmap = remember(photoBytes) {
        BitmapFactory.decodeByteArray(photoBytes, 0, photoBytes.size)
    }

    AnimatedVisibility(
        visible = bitmap != null,
        enter = fadeIn(animationSpec = tween(800))
    ) {
        bitmap?.let {
            Image(
                bitmap = it.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxSize()
                    .blur(radius = 24.dp)
                    .alpha(0.35f),
                contentScale = ContentScale.Crop
            )
        }
    }
}

/**
 * Главная кнопка захвата — большая круглая с анимациями.
 *
 * Состояния:
 * - IDLE: пульсирующее кольцо
 * - SCANNING/CONNECTING: вращающийся индикатор
 * - CAPTURING/RECEIVING: прогресс
 * - UPLOADING: мерцание
 * - ERROR: красный оттенок
 */
@Composable
fun CaptureButton(
    phase: UiPhase,
    progress: Int,
    onClick: () -> Unit
) {
    // ---- Пульсация в IDLE ----
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.12f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = EaseInOutSine),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse_scale"
    )
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 0.7f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = EaseInOutSine),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse_alpha"
    )

    // ---- Вращение при сканировании ----
    val rotationAngle by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = LinearEasing)
        ),
        label = "rotation"
    )

    // ---- Мерцание при загрузке ----
    val blinkAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(600),
            repeatMode = RepeatMode.Reverse
        ),
        label = "blink"
    )

    // ---- Цвет кнопки зависит от фазы ----
    val buttonColor by animateColorAsState(
        targetValue = when (phase) {
            UiPhase.ERROR -> Color(0xFFFF4444)
            UiPhase.SPEAKING -> StatusConnected
            else -> AccentBlue
        },
        animationSpec = tween(400),
        label = "button_color"
    )

    Box(
        modifier = Modifier.size(200.dp),
        contentAlignment = Alignment.Center
    ) {
        // ---- Пульсирующее внешнее кольцо (только в IDLE) ----
        if (phase == UiPhase.IDLE) {
            Box(
                modifier = Modifier
                    .size(200.dp * pulseScale)
                    .clip(CircleShape)
                    .background(AccentBlue.copy(alpha = pulseAlpha * 0.15f))
            )
            Box(
                modifier = Modifier
                    .size(180.dp * pulseScale)
                    .clip(CircleShape)
                    .background(AccentBlue.copy(alpha = pulseAlpha * 0.1f))
            )
        }

        // ---- Вращающийся CircularProgressIndicator (сканирование/подключение) ----
        if (phase == UiPhase.SCANNING || phase == UiPhase.CONNECTING) {
            CircularProgressIndicator(
                modifier = Modifier.size(200.dp),
                color = buttonColor.copy(alpha = 0.5f),
                strokeWidth = 2.dp
            )
        }

        // ---- Прогресс получения JPEG ----
        if (phase == UiPhase.RECEIVING) {
            CircularProgressIndicator(
                progress = { progress / 100f },
                modifier = Modifier.size(200.dp),
                color = buttonColor,
                trackColor = buttonColor.copy(alpha = 0.2f),
                strokeWidth = 3.dp
            )
        }

        // ---- Основная круглая кнопка ----
        Box(
            modifier = Modifier
                .size(160.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            buttonColor.copy(alpha = if (phase == UiPhase.UPLOADING) blinkAlpha else 1f),
                            buttonColor.copy(alpha = (if (phase == UiPhase.UPLOADING) blinkAlpha else 1f) * 0.7f)
                        )
                    )
                )
                .clickable(
                    enabled = phase !in listOf(
                        UiPhase.SCANNING, UiPhase.CONNECTING,
                        UiPhase.CAPTURING, UiPhase.RECEIVING, UiPhase.UPLOADING
                    ),
                    onClick = onClick
                ),
            contentAlignment = Alignment.Center
        ) {
            // Иконка/текст внутри кнопки
            ButtonContent(phase = phase, progress = progress)
        }
    }
}

/**
 * Контент внутри кнопки — иконка или текст в зависимости от фазы.
 */
@Composable
fun ButtonContent(phase: UiPhase, progress: Int) {
    when (phase) {
        UiPhase.IDLE, UiPhase.CONNECTED -> {
            // Иконка камеры (unicode)
            Text(
                text = "◉",
                fontSize = 48.sp,
                color = BackgroundDark
            )
        }
        UiPhase.SCANNING -> {
            Text(
                text = "⟳",
                fontSize = 42.sp,
                color = BackgroundDark
            )
        }
        UiPhase.CONNECTING -> {
            Text(
                text = "⌁",
                fontSize = 42.sp,
                color = BackgroundDark
            )
        }
        UiPhase.CAPTURING -> {
            Text(
                text = "⚡",
                fontSize = 42.sp,
                color = BackgroundDark
            )
        }
        UiPhase.RECEIVING -> {
            Text(
                text = "$progress%",
                fontSize = 28.sp,
                color = BackgroundDark,
                fontFamily = JetBrainsMono
            )
        }
        UiPhase.UPLOADING -> {
            Text(
                text = "↑",
                fontSize = 48.sp,
                color = BackgroundDark
            )
        }
        UiPhase.SPEAKING -> {
            Text(
                text = "♪",
                fontSize = 42.sp,
                color = BackgroundDark
            )
        }
        UiPhase.ERROR -> {
            Text(
                text = "!",
                fontSize = 52.sp,
                color = BackgroundDark
            )
        }
    }
}

/**
 * Карточка с ответом ИИ — всплывает снизу.
 * Смахивается вниз для закрытия.
 */
@Composable
fun AiResponseCard(
    text: String,
    onDismiss: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clickable(onClick = onDismiss),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(
            containerColor = SurfaceElevated.copy(alpha = 0.95f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
    ) {
        Column(
            modifier = Modifier.padding(20.dp)
        ) {
            // Заголовок карточки
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = "ИИ",
                    style = MaterialTheme.typography.labelMedium,
                    color = AccentBlue
                )
                Text(
                    text = "× нажмите чтобы закрыть",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextHint
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            // Текст ответа
            Text(
                text = text,
                style = MaterialTheme.typography.headlineMedium,
                color = TextPrimary,
                maxLines = 6,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/**
 * Статусная полоса внизу экрана.
 * Длинное нажатие открывает настройки.
 */
@Composable
fun StatusBar(
    statusText: String,
    isBleConnected: Boolean,
    onLongPress: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .pointerInput(Unit) {
                detectTapGestures(onLongPress = { onLongPress() })
            }
            .padding(horizontal = 24.dp, vertical = 20.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Текст статуса
        Text(
            text = statusText,
            style = MaterialTheme.typography.labelMedium,
            color = TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )

        Spacer(modifier = Modifier.width(12.dp))

        // BLE индикатор
        BleIndicator(isConnected = isBleConnected)
    }
}

/**
 * Маленький BLE индикатор — зелёный если подключено, серый если нет.
 */
@Composable
fun BleIndicator(isConnected: Boolean) {
    val color by animateColorAsState(
        targetValue = if (isConnected) StatusConnected else StatusDisconnected,
        animationSpec = tween(500),
        label = "ble_color"
    )

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // Точка-индикатор
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Text(
            text = "BLE",
            style = MaterialTheme.typography.labelSmall,
            color = color
        )
    }
}

/**
 * Экран настроек — открывается долгим нажатием на статусбар.
 * Полупрозрачный оверлей с полями ввода.
 */
@Composable
fun SettingsScreen(
    viewModel: MainViewModel,
    onDismiss: () -> Unit
) {
    val serverUrl by viewModel.serverUrl.collectAsState(initial = "http://192.168.1.100:8080/upload")
    val bleDeviceName by viewModel.bleDeviceName.collectAsState(initial = "ESP32-CAM")

    var urlInput by remember { mutableStateOf(serverUrl) }
    var bleInput by remember { mutableStateOf(bleDeviceName) }

    // Обновляем поля когда загрузились из DataStore
    LaunchedEffect(serverUrl) { urlInput = serverUrl }
    LaunchedEffect(bleDeviceName) { bleInput = bleDeviceName }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BackgroundDark.copy(alpha = 0.95f))
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.Center
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp)
                .clickable { /* поглощаем клики, не закрываем */ },
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
        ) {
            Column(
                modifier = Modifier.padding(28.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                // Заголовок
                Text(
                    text = "Настройки",
                    style = MaterialTheme.typography.headlineMedium,
                    color = TextPrimary
                )

                // URL сервера
                OutlinedTextField(
                    value = urlInput,
                    onValueChange = { urlInput = it },
                    label = {
                        Text(
                            "URL сервера",
                            style = MaterialTheme.typography.labelMedium
                        )
                    },
                    placeholder = {
                        Text(
                            "http://192.168.1.100:8080/upload",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextHint
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AccentBlue,
                        unfocusedBorderColor = SurfaceElevated,
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextSecondary,
                        cursorColor = AccentBlue
                    )
                )

                // Имя BLE-устройства
                OutlinedTextField(
                    value = bleInput,
                    onValueChange = { bleInput = it },
                    label = {
                        Text(
                            "Имя BLE-устройства",
                            style = MaterialTheme.typography.labelMedium
                        )
                    },
                    placeholder = {
                        Text(
                            "ESP32-CAM",
                            style = MaterialTheme.typography.labelSmall,
                            color = TextHint
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AccentBlue,
                        unfocusedBorderColor = SurfaceElevated,
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextSecondary,
                        cursorColor = AccentBlue
                    )
                )

                // Кнопки
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // Отмена
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f),
                        border = BorderStroke(1.dp, TextHint),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Отмена", color = TextSecondary)
                    }

                    // Сохранить
                    Button(
                        onClick = {
                            viewModel.saveSettings(urlInput, bleInput)
                            onDismiss()
                        },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Text("Сохранить", color = BackgroundDark)
                    }
                }

                // Подсказка
                Text(
                    text = "Долгое нажатие на статусбар для открытия настроек",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextHint,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

