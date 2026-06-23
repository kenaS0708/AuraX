package com.example.blecam.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.util.Log
import androidx.annotation.RequiresPermission
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID

// ========== BLE UUID ==========
// Согласованы с прошивкой ESP32

/** UUID GATT-сервиса камеры */
val SERVICE_UUID: UUID = UUID.fromString("4fafc201-1fb5-459e-8fcc-c5c9c331914b")

/** UUID характеристики команды — телефон пишет 0x01 для снимка */
val COMMAND_CHAR_UUID: UUID = UUID.fromString("beb5483e-36e1-4688-b7f5-ea07361b26a8")

/** UUID характеристики данных — ESP32 отправляет JPEG чанками через notify */
val DATA_CHAR_UUID: UUID = UUID.fromString("beb5483e-36e1-4688-b7f5-ea07361b26a9")

/** UUID дескриптора Client Characteristic Configuration (стандарт BLE) */
val CCC_DESCRIPTOR_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

// ========== СОСТОЯНИЯ BLE ==========

/** Все возможные состояния BLE-менеджера */
sealed class BleState {
    /** Начальное состояние, BLE не активен */
    object Idle : BleState()
    /** Идёт сканирование устройств */
    data class Scanning(val deviceName: String) : BleState()
    /** Подключаемся к найденному устройству */
    object Connecting : BleState()
    /** Успешно подключены */
    object Connected : BleState()
    /** Отправлена команда снимка, ожидаем данные */
    object Capturing : BleState()
    /** Получаем JPEG-данные (0..100%) */
    data class Receiving(val progress: Int) : BleState()
    /** Отключены / произошла ошибка */
    data class Disconnected(val reason: String = "") : BleState()
    /** Ошибка (BLE недоступен, нет прав, etc) */
    data class Error(val message: String) : BleState()
}

/**
 * BleManager — управляет всем BLE-взаимодействием с ESP32.
 *
 * Жизненный цикл:
 * 1. scanAndConnect(deviceName) — сканирует BLE, ищет устройство по имени
 * 2. При нахождении — автоматически подключается и обнаруживает сервисы
 * 3. capturePhoto() — отправляет команду 0x01, начинает накапливать чанки
 * 4. Собранный JPEG возвращается через callback onJpegReceived
 * 5. disconnect() — закрывает GATT соединение
 */
@SuppressLint("MissingPermission")
class BleManager(private val context: Context) {

    companion object {
        private const val TAG = "BleManager"
        /** Таймаут сканирования BLE — 15 секунд */
        private const val SCAN_TIMEOUT_MS = 15_000L
        /** Таймаут ожидания данных — 30 секунд */
        private const val DATA_TIMEOUT_MS = 30_000L
    }

    // ========== STATE ==========

    private val _state = MutableStateFlow<BleState>(BleState.Idle)
    /** Текущее состояние BLE — наблюдается из ViewModel */
    val state: StateFlow<BleState> = _state

    // ========== ВНУТРЕННЕЕ СОСТОЯНИЕ ==========

    /** GATT-соединение с ESP32 */
    private var gatt: BluetoothGatt? = null

    /** Буфер для сборки JPEG из чанков */
    private val jpegBuffer = mutableListOf<ByteArray>()

    /** Ожидаемое количество байт (динамически обновляется) */
    private var totalExpectedChunks = 0

    /** Коллбэк для передачи собранного JPEG наверх */
    private var onJpegReceived: ((ByteArray) -> Unit)? = null

    /** Корутин scope для асинхронных операций */
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    /** Job таймаута сканирования */
    private var scanTimeoutJob: Job? = null

    /** Job таймаута получения данных */
    private var dataTimeoutJob: Job? = null

    // ========== SCAN CALLBACK ==========

    /**
     * Коллбэк BLE-сканирования.
     * Ищем устройство по имени (игнорируем регистр).
     */
    private inner class BleScanCallback(private val targetName: String) : ScanCallback() {

        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.device.name ?: return
            Log.d(TAG, "Найдено BLE-устройство: $name")

            if (name.equals(targetName, ignoreCase = true)) {
                Log.i(TAG, "Целевое устройство найдено: $name")
                // Останавливаем сканирование и подключаемся
                stopScan()
                connectToDevice(result.device)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Ошибка сканирования BLE: $errorCode")
            _state.value = BleState.Error("Ошибка сканирования BLE (код: $errorCode)")
        }
    }

    private var scanCallback: BleScanCallback? = null

    // ========== GATT CALLBACK ==========

    /**
     * Коллбэк GATT-соединения.
     * Обрабатывает подключение, обнаружение сервисов и уведомления с данными.
     */
    private val gattCallback = object : BluetoothGattCallback() {

        /** Изменение состояния подключения */
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.i(TAG, "GATT подключён, обнаруживаем сервисы...")
                    _state.value = BleState.Connecting
                    // Небольшая задержка перед discoverServices (рекомендация Google)
                    scope.launch {
                        delay(600)
                        gatt.discoverServices()
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.w(TAG, "GATT отключён, status=$status")
                    handleDisconnect("Устройство отключилось")
                }
            }
        }

        /** Сервисы обнаружены — включаем нотификации на DATA характеристике */
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.e(TAG, "Ошибка обнаружения сервисов: $status")
                _state.value = BleState.Error("Не удалось обнаружить сервисы BLE")
                return
            }

            val service = gatt.getService(SERVICE_UUID)
            if (service == null) {
                Log.e(TAG, "Сервис камеры не найден на устройстве!")
                _state.value = BleState.Error("Сервис BLE-камеры не найден")
                return
            }

            val dataChar = service.getCharacteristic(DATA_CHAR_UUID)
            if (dataChar == null) {
                Log.e(TAG, "DATA характеристика не найдена!")
                _state.value = BleState.Error("DATA характеристика не найдена")
                return
            }

            // Включаем нотификации для получения JPEG-чанков
            val notifyEnabled = gatt.setCharacteristicNotification(dataChar, true)
            Log.d(TAG, "setCharacteristicNotification: $notifyEnabled")

            // Записываем CCC дескриптор чтобы ESP32 начал отправлять notify
            val descriptor = dataChar.getDescriptor(CCC_DESCRIPTOR_UUID)
            if (descriptor != null) {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(descriptor)
                Log.d(TAG, "CCC дескриптор записан — notify включён")
            }

            Log.i(TAG, "Подключение установлено, сервисы настроены")
            _state.value = BleState.Connected
        }

        /** Записан дескриптор CCC */
        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            Log.d(TAG, "Дескриптор записан, status=$status")
            // Соединение готово к работе
            _state.value = BleState.Connected
        }

        /** Пришёл новый чанк JPEG (notify от ESP32) */
        @Deprecated("Используется для API < 33, оставляем для совместимости")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == DATA_CHAR_UUID) {
                handleIncomingChunk(characteristic.value)
            }
        }

        /** Пришёл новый чанк JPEG (notify от ESP32) — API 33+ */
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (characteristic.uuid == DATA_CHAR_UUID) {
                handleIncomingChunk(value)
            }
        }

        /** Результат записи команды */
        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.i(TAG, "Команда снимка отправлена успешно")
                _state.value = BleState.Capturing
                // Запускаем таймаут ожидания данных
                startDataTimeout()
            } else {
                Log.e(TAG, "Ошибка записи команды: $status")
                _state.value = BleState.Error("Ошибка отправки команды на ESP32")
            }
        }
    }

    // ========== PUBLIC API ==========

    /**
     * Начинает сканирование BLE и подключается к устройству с указанным именем.
     * @param deviceName имя BLE-устройства (например "ESP32-CAM")
     * @param onJpeg коллбэк, вызываемый когда JPEG полностью собран
     */
    @RequiresPermission(allOf = [Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT])
    fun scanAndConnect(deviceName: String, onJpeg: (ByteArray) -> Unit) {
        onJpegReceived = onJpeg

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter

        if (adapter == null || !adapter.isEnabled) {
            _state.value = BleState.Error("Bluetooth выключен или недоступен")
            return
        }

        Log.i(TAG, "Начинаем сканирование BLE, ищем: $deviceName")
        _state.value = BleState.Scanning(deviceName)

        val scanner = adapter.bluetoothLeScanner
        scanCallback = BleScanCallback(deviceName)

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY) // максимальная скорость сканирования
            .build()

        scanner.startScan(null, settings, scanCallback)

        // Таймаут сканирования — если за 15 сек не нашли, ошибка
        scanTimeoutJob = scope.launch {
            delay(SCAN_TIMEOUT_MS)
            if (_state.value is BleState.Scanning) {
                Log.w(TAG, "Таймаут сканирования BLE")
                stopScan()
                _state.value = BleState.Error("Устройство '$deviceName' не найдено")
            }
        }
    }

    /**
     * Отправляет команду снимка (0x01) на ESP32.
     * Должен быть вызван когда state == Connected.
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun capturePhoto() {
        val currentGatt = gatt ?: run {
            _state.value = BleState.Error("Нет BLE-соединения")
            return
        }

        val service = currentGatt.getService(SERVICE_UUID) ?: run {
            _state.value = BleState.Error("Сервис BLE не найден")
            return
        }

        val commandChar = service.getCharacteristic(COMMAND_CHAR_UUID) ?: run {
            _state.value = BleState.Error("COMMAND характеристика не найдена")
            return
        }

        // Очищаем буфер перед новым снимком
        jpegBuffer.clear()
        totalExpectedChunks = 0

        Log.i(TAG, "Отправляем команду снимка на ESP32")
        commandChar.value = byteArrayOf(0x01)
        commandChar.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        currentGatt.writeCharacteristic(commandChar)
    }

    /**
     * Отключается от ESP32 и освобождает ресурсы.
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun disconnect() {
        Log.i(TAG, "Отключаемся от ESP32")
        dataTimeoutJob?.cancel()
        scanTimeoutJob?.cancel()
        gatt?.disconnect()
        gatt?.close()
        gatt = null
        _state.value = BleState.Disconnected("Отключено пользователем")
    }

    /** Освобождает все ресурсы при уничтожении */
    fun cleanup() {
        scope.cancel()
        gatt?.close()
        gatt = null
    }

    // ========== PRIVATE METHODS ==========

    /**
     * Останавливает BLE-сканирование.
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_SCAN)
    private fun stopScan() {
        scanTimeoutJob?.cancel()
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = bluetoothManager.adapter?.bluetoothLeScanner
        scanCallback?.let { scanner?.stopScan(it) }
        scanCallback = null
        Log.d(TAG, "Сканирование остановлено")
    }

    /**
     * Подключается к конкретному BLE-устройству.
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    private fun connectToDevice(device: BluetoothDevice) {
        Log.i(TAG, "Подключаемся к ${device.name} (${device.address})")
        _state.value = BleState.Connecting

        // autoConnect=false — быстрое прямое подключение
        gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    /**
     * Обрабатывает входящий BLE-чанк с JPEG-данными.
     *
     * Формат чанка: [seq_high][seq_low][flags][data...]
     * flags=0x00 — промежуточный чанк
     * flags=0xFF — последний чанк, сигнал конца JPEG
     */
    private fun handleIncomingChunk(data: ByteArray) {
        if (data.size < 3) {
            Log.w(TAG, "Слишком короткий чанк: ${data.size} байт")
            return
        }

        val seqNum = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
        val flags = data[2].toInt() and 0xFF
        val payload = data.copyOfRange(3, data.size)

        Log.v(TAG, "Чанк #$seqNum, flags=$flags, payload=${payload.size} байт")

        // Сбрасываем таймаут — данные идут
        dataTimeoutJob?.cancel()

        // Добавляем payload в нужную позицию буфера
        // Чанки могут приходить не по порядку (хотя BLE обычно гарантирует порядок)
        while (jpegBuffer.size <= seqNum) {
            jpegBuffer.add(ByteArray(0))
        }
        jpegBuffer[seqNum] = payload

        // Обновляем прогресс получения
        if (flags == 0xFF) {
            // Последний чанк — теперь знаем общее количество
            totalExpectedChunks = seqNum + 1
            Log.i(TAG, "Последний чанк #$seqNum, всего $totalExpectedChunks чанков")
        }

        // Обновляем состояние с прогрессом
        val progress = if (totalExpectedChunks > 0) {
            (jpegBuffer.count { it.isNotEmpty() } * 100) / totalExpectedChunks
        } else {
            (seqNum * 100 / (seqNum + 10)).coerceAtMost(90) // грубая оценка
        }
        _state.value = BleState.Receiving(progress)

        // Если получили последний чанк — собираем JPEG
        if (flags == 0xFF) {
            assembleJpeg()
        } else {
            // Перезапускаем таймаут ожидания следующего чанка
            startDataTimeout()
        }
    }

    /**
     * Собирает все чанки в единый JPEG-байтмассив и вызывает коллбэк.
     */
    private fun assembleJpeg() {
        Log.i(TAG, "Собираем JPEG из ${jpegBuffer.size} чанков...")

        // Суммарный размер
        val totalSize = jpegBuffer.sumOf { it.size }
        Log.i(TAG, "Итоговый размер JPEG: $totalSize байт")

        if (totalSize == 0) {
            _state.value = BleState.Error("Получены пустые данные от камеры")
            return
        }

        // Конкатенируем все чанки
        val jpegBytes = ByteArray(totalSize)
        var offset = 0
        for (chunk in jpegBuffer) {
            chunk.copyInto(jpegBytes, offset)
            offset += chunk.size
        }

        jpegBuffer.clear()

        // Проверяем JPEG-заголовок (должен начинаться с FF D8)
        if (jpegBytes.size >= 2 &&
            jpegBytes[0] == 0xFF.toByte() &&
            jpegBytes[1] == 0xD8.toByte()
        ) {
            Log.i(TAG, "JPEG корректный, передаём наверх")
            _state.value = BleState.Connected // возвращаемся в состояние готовности
            onJpegReceived?.invoke(jpegBytes)
        } else {
            Log.e(TAG, "Некорректный JPEG (заголовок: ${jpegBytes.take(4).map { "%02X".format(it) }})")
            _state.value = BleState.Error("Получены повреждённые данные JPEG")
        }
    }

    /**
     * Обрабатывает отключение от устройства.
     */
    private fun handleDisconnect(reason: String) {
        dataTimeoutJob?.cancel()
        gatt?.close()
        gatt = null
        _state.value = BleState.Disconnected(reason)
    }

    /**
     * Запускает таймаут ожидания данных.
     * Если за 30 секунд не пришёл следующий чанк — ошибка.
     */
    private fun startDataTimeout() {
        dataTimeoutJob?.cancel()
        dataTimeoutJob = scope.launch {
            delay(DATA_TIMEOUT_MS)
            Log.w(TAG, "Таймаут получения данных от ESP32")
            _state.value = BleState.Error("Таймаут: ESP32 не отвечает")
        }
    }
}
