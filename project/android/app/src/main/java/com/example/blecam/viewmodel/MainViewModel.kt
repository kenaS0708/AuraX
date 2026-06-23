package com.example.blecam.viewmodel

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.blecam.ble.BleManager
import com.example.blecam.ble.BleState
import com.example.blecam.http.HttpClient
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.Locale

// ========== DATASTORE ==========
// Хранение настроек (URL сервера, имя BLE)

/** DataStore экстеншн для Application */
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/** Ключи DataStore */
private val KEY_SERVER_URL = stringPreferencesKey("server_url")
private val KEY_BLE_DEVICE_NAME = stringPreferencesKey("ble_device_name")

// ========== СОСТОЯНИЯ UI ==========

/**
 * Общее состояние UI — отображается в Compose экране.
 * Derived from BleState + дополнительных полей.
 */
enum class UiPhase {
    IDLE,        // ожидание, кнопка пульсирует
    SCANNING,    // сканирование BLE
    CONNECTING,  // подключение к ESP32
    CONNECTED,   // подключены, готовы
    CAPTURING,   // отправлена команда снимка
    RECEIVING,   // получаем JPEG чанки
    UPLOADING,   // отправляем JPEG на сервер
    SPEAKING,    // воспроизводим TTS ответ
    ERROR        // ошибка
}

/**
 * MainViewModel — вся бизнес-логика приложения.
 *
 * Управляет:
 * - BLE менеджером (scan → connect → capture → receive)
 * - HTTP клиентом (upload JPEG → receive text)
 * - TTS (озвучивание текста)
 * - DataStore (настройки)
 * - UI состоянием (StateFlow для Compose)
 */
class MainViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "MainViewModel"
        /** Дефолтный URL сервера */
        private const val DEFAULT_SERVER_URL = "http://192.168.1.100:8080/upload"
        /** Дефолтное имя BLE-устройства */
        private const val DEFAULT_BLE_NAME = "ESP32-CAM"
    }

    // ========== DEPENDENCIES ==========

    private val bleManager = BleManager(application)
    private val httpClient = HttpClient()
    private var tts: TextToSpeech? = null
    private val vibrator = application.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    // ========== UI STATE ==========

    /** Текущая фаза UI */
    private val _uiPhase = MutableStateFlow(UiPhase.IDLE)
    val uiPhase: StateFlow<UiPhase> = _uiPhase.asStateFlow()

    /** Текст статусной строки */
    private val _statusText = MutableStateFlow("Нажмите для съёмки")
    val statusText: StateFlow<String> = _statusText.asStateFlow()

    /** Последний снятый JPEG (для превью) */
    private val _lastPhoto = MutableStateFlow<ByteArray?>(null)
    val lastPhoto: StateFlow<ByteArray?> = _lastPhoto.asStateFlow()

    /** Текст ответа ИИ */
    private val _aiResponse = MutableStateFlow<String?>(null)
    val aiResponse: StateFlow<String?> = _aiResponse.asStateFlow()

    /** Прогресс получения JPEG (0..100) */
    private val _receiveProgress = MutableStateFlow(0)
    val receiveProgress: StateFlow<Int> = _receiveProgress.asStateFlow()

    /** BLE подключён? (для иконки статуса) */
    val isBleConnected: StateFlow<Boolean> = bleManager.state
        .map { it is BleState.Connected || it is BleState.Capturing || it is BleState.Receiving }
        .stateIn(viewModelScope, SharingStarted.Eagerly, false)

    // ========== SETTINGS ==========

    /** URL сервера */
    val serverUrl: Flow<String> = application.dataStore.data
        .map { prefs -> prefs[KEY_SERVER_URL] ?: DEFAULT_SERVER_URL }

    /** Имя BLE-устройства */
    val bleDeviceName: Flow<String> = application.dataStore.data
        .map { prefs -> prefs[KEY_BLE_DEVICE_NAME] ?: DEFAULT_BLE_NAME }

    // ========== INIT ==========

    init {
        // Подписываемся на состояние BLE и обновляем UI
        viewModelScope.launch {
            bleManager.state.collect { bleState ->
                handleBleState(bleState)
            }
        }

        // Инициализируем TTS
        initTts()
    }

    // ========== PUBLIC API ==========

    /**
     * Главное действие — нажатие на кнопку.
     * Логика зависит от текущего состояния:
     * - IDLE / ERROR / CONNECTED → начинаем цикл съёмки
     * - SCANNING / CONNECTING → игнорируем (уже в процессе)
     */
    fun onCaptureButtonClick() {
        viewModelScope.launch {
            // Haptic feedback — короткая вибрация
            vibrate()

            when (_uiPhase.value) {
                UiPhase.IDLE, UiPhase.ERROR -> {
                    // Нужно сначала подключиться к BLE
                    startBleAndCapture()
                }
                UiPhase.CONNECTED -> {
                    // Уже подключены — просто снимаем
                    capturePhoto()
                }
                else -> {
                    // Идёт процесс — ничего не делаем
                    Log.d(TAG, "Кнопка нажата в состоянии ${_uiPhase.value}, игнорируем")
                }
            }
        }
    }

    /**
     * Сохраняет настройки в DataStore.
     */
    fun saveSettings(newServerUrl: String, newBleName: String) {
        viewModelScope.launch {
            getApplication<Application>().dataStore.edit { prefs ->
                prefs[KEY_SERVER_URL] = newServerUrl.trim()
                prefs[KEY_BLE_DEVICE_NAME] = newBleName.trim()
            }
            Log.i(TAG, "Настройки сохранены: URL=$newServerUrl, BLE=$newBleName")
        }
    }

    /** Закрывает карточку с ответом ИИ */
    fun dismissAiResponse() {
        _aiResponse.value = null
        if (_uiPhase.value == UiPhase.SPEAKING) {
            _uiPhase.value = UiPhase.CONNECTED
            tts?.stop()
        }
    }

    override fun onCleared() {
        super.onCleared()
        tts?.stop()
        tts?.shutdown()
        bleManager.cleanup()
    }

    // ========== PRIVATE METHODS ==========

    /**
     * Запускает BLE сканирование и, при подключении, делает снимок.
     */
    private fun startBleAndCapture() {
        viewModelScope.launch {
            val bleName = bleDeviceName.first()
            Log.i(TAG, "Сканируем BLE, ищем: $bleName")

            // При получении JPEG — загружаем на сервер
            bleManager.scanAndConnect(bleName) { jpegBytes ->
                viewModelScope.launch {
                    uploadAndSpeak(jpegBytes)
                }
            }
        }
    }

    /**
     * Отправляет команду снимка на ESP32.
     * Вызывается когда BLE уже подключён.
     */
    private fun capturePhoto() {
        _aiResponse.value = null // скрываем предыдущий ответ
        bleManager.capturePhoto()
    }

    /**
     * Обрабатывает изменение состояния BLE и обновляет UI.
     */
    private fun handleBleState(bleState: BleState) {
        Log.d(TAG, "BLE состояние: $bleState")
        when (bleState) {
            is BleState.Idle -> {
                _uiPhase.value = UiPhase.IDLE
                _statusText.value = "Нажмите для съёмки"
            }
            is BleState.Scanning -> {
                _uiPhase.value = UiPhase.SCANNING
                _statusText.value = "Поиск ${bleState.deviceName}..."
            }
            is BleState.Connecting -> {
                _uiPhase.value = UiPhase.CONNECTING
                _statusText.value = "Подключение..."
            }
            is BleState.Connected -> {
                if (_uiPhase.value == UiPhase.CONNECTING ||
                    _uiPhase.value == UiPhase.SCANNING) {
                    // Только что подключились — автоматически делаем снимок
                    _uiPhase.value = UiPhase.CONNECTED
                    _statusText.value = "Подключено • Снимаем..."
                    capturePhoto()
                } else {
                    _uiPhase.value = UiPhase.CONNECTED
                    _statusText.value = "Подключено"
                }
            }
            is BleState.Capturing -> {
                _uiPhase.value = UiPhase.CAPTURING
                _statusText.value = "Снимаем фото..."
            }
            is BleState.Receiving -> {
                _uiPhase.value = UiPhase.RECEIVING
                _receiveProgress.value = bleState.progress
                _statusText.value = "Получаем фото: ${bleState.progress}%"
            }
            is BleState.Disconnected -> {
                _uiPhase.value = UiPhase.IDLE
                _statusText.value = if (bleState.reason.isNotEmpty())
                    "Отключено: ${bleState.reason}"
                else
                    "Нажмите для съёмки"
            }
            is BleState.Error -> {
                _uiPhase.value = UiPhase.ERROR
                _statusText.value = "Ошибка: ${bleState.message}"
                Log.e(TAG, "BLE ошибка: ${bleState.message}")
            }
        }
    }

    /**
     * Загружает JPEG на сервер и озвучивает ответ.
     */
    private suspend fun uploadAndSpeak(jpegBytes: ByteArray) {
        Log.i(TAG, "Начинаем загрузку JPEG (${jpegBytes.size} байт)")

        // Сохраняем фото для превью
        _lastPhoto.value = jpegBytes

        // Переходим в состояние загрузки
        _uiPhase.value = UiPhase.UPLOADING
        _statusText.value = "Анализируем фото..."

        val url = serverUrl.first()
        val result = httpClient.uploadPhoto(url, jpegBytes)

        result.fold(
            onSuccess = { text ->
                Log.i(TAG, "Ответ ИИ: $text")
                _aiResponse.value = text
                _uiPhase.value = UiPhase.SPEAKING
                _statusText.value = "Подключено"
                speakText(text)
            },
            onFailure = { error ->
                Log.e(TAG, "Ошибка загрузки: ${error.message}")
                _uiPhase.value = UiPhase.ERROR
                _statusText.value = "Ошибка сервера: ${error.message}"
            }
        )
    }

    /**
     * Озвучивает текст через Android TTS.
     */
    private fun speakText(text: String) {
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ai_response")
    }

    /**
     * Инициализирует TextToSpeech с русским языком.
     */
    private fun initTts() {
        tts = TextToSpeech(getApplication()) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale("ru", "RU"))
                if (result == TextToSpeech.LANG_MISSING_DATA ||
                    result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.w(TAG, "Русский TTS не поддерживается, используем дефолтный")
                    tts?.setLanguage(Locale.getDefault())
                }
                Log.i(TAG, "TTS инициализирован")
            } else {
                Log.e(TAG, "Ошибка инициализации TTS: $status")
            }
        }
    }

    /**
     * Короткая тактильная вибрация при нажатии.
     */
    private fun vibrate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(50)
        }
    }
}
