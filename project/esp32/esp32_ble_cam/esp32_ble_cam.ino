/**
 * esp32_ble_cam.ino
 *
 * Прошивка для AI-Thinker ESP32-S3-CAM N16R8
 *
 * Функциональность:
 * - BLE GATT-сервер с кастомными характеристиками
 * - Захват фото с камеры OV3660
 * - Передача JPEG по BLE чанками (notify, 512 байт на чанк)
 * - LED мигает во время передачи
 *
 * Настройки Arduino IDE:
 * - Board: ESP32S3 Dev Module
 * - Flash Size: 16MB (128Mb)
 * - PSRAM: OPI PSRAM
 * - Partition: Huge APP (3MB No OTA/1MB SPIFFS)
 * - CPU Frequency: 240MHz
 * - Upload Speed: 921600
 *
 * Автор: ESP32 BLE CAM Project
 */

#include "esp_camera.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// ПИНЫ КАМЕРЫ — AI-Thinker ESP32-S3-CAM N16R8
// ============================================================
#define PWDN_GPIO_NUM    -1   // Нет пина PWDN
#define RESET_GPIO_NUM   -1   // Нет пина RESET
#define XCLK_GPIO_NUM    15   // Тактовый сигнал камеры
#define SIOD_GPIO_NUM    4    // I2C SDA (SCCB Data)
#define SIOC_GPIO_NUM    5    // I2C SCL (SCCB Clock)
#define Y9_GPIO_NUM      16   // Данные пиксели бит 7 (MSB)
#define Y8_GPIO_NUM      17   // Данные пиксели бит 6
#define Y7_GPIO_NUM      18   // Данные пиксели бит 5
#define Y6_GPIO_NUM      12   // Данные пиксели бит 4
#define Y5_GPIO_NUM      10   // Данные пиксели бит 3
#define Y4_GPIO_NUM      8    // Данные пиксели бит 2
#define Y3_GPIO_NUM      9    // Данные пиксели бит 1
#define Y2_GPIO_NUM      11   // Данные пиксели бит 0 (LSB)
#define VSYNC_GPIO_NUM   6    // Вертикальная синхронизация
#define HREF_GPIO_NUM    7    // Горизонтальная синхронизация
#define PCLK_GPIO_NUM    13   // Тактирование пикселей

// ============================================================
// LED и КНОПКА
// ============================================================
#define LED_GPIO         2    // Встроенный LED
#define BUTTON_GPIO      47   // Тактовая кнопка на GPIO47, INPUT_PULLUP

#define DEBOUNCE_MS      50   // Антидребезг кнопки (мс)

// ============================================================
// BLE UUID — должны совпадать с Android-приложением
// ============================================================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define COMMAND_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define DATA_CHAR_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define EVENT_CHAR_UUID     "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// ============================================================
// ПАРАМЕТРЫ ПЕРЕДАЧИ
// ============================================================
#define CHUNK_SIZE        500   // Размер данных в одном чанке (байт)
                                // MTU 512 → макс. payload 509 → 509 - 3 заголовок = 506, берём 500 с запасом
#define BLE_MTU           517   // Размер MTU для BLE 5.0
#define SEND_DELAY_MS     20    // Задержка между чанками (мс) для стабильности

// ============================================================
// ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
// ============================================================

BLEServer*          pServer          = nullptr;
BLECharacteristic*  pCommandChar     = nullptr;
BLECharacteristic*  pDataChar        = nullptr;
BLECharacteristic*  pEventChar       = nullptr;

// Состояние кнопки для антидребезга
bool     btnLastRaw     = HIGH;
bool     btnState       = HIGH;
uint32_t btnDebounceMs  = 0;

/** Флаг: клиент подключён */
volatile bool       deviceConnected  = false;
/** Флаг: нужно захватить фото (установлен из коллбэка команды) */
volatile bool       captureRequested = false;

// ============================================================
// КОЛЛБЭКИ BLE-СЕРВЕРА
// ============================================================

/**
 * ServerCallbacks — обрабатывает подключение/отключение BLE-клиента.
 */
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        deviceConnected = true;
        Serial.println("[BLE] Клиент подключился");
        // Запрашиваем максимальный MTU для быстрой передачи
        pServer->updateConnParams(pServer->getConnId(), 6, 6, 0, 500);
    }

    void onDisconnect(BLEServer* pServer) override {
        deviceConnected = false;
        captureRequested = false;
        Serial.println("[BLE] Клиент отключился");
        // Перезапускаем рекламу чтобы новый клиент мог подключиться
        BLEDevice::startAdvertising();
        Serial.println("[BLE] Реклама перезапущена");
    }
};

/**
 * CommandCallbacks — обрабатывает запись в COMMAND характеристику.
 * Телефон пишет 0x01 — команда сделать снимок.
 */
class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) override {
        String value = pCharacteristic->getValue();
        if (value.length() > 0) {
            uint8_t cmd = (uint8_t)value[0];
            Serial.printf("[BLE] Получена команда: 0x%02X\n", cmd);

            if (cmd == 0x01) {
                // Команда снимка
                captureRequested = true;
                Serial.println("[CAM] Запрошен снимок");
            }
        }
    }
};

// ============================================================
// ИНИЦИАЛИЗАЦИЯ КАМЕРЫ
// ============================================================

/**
 * Инициализирует OV3660 камеру с оптимальными настройками для JPEG.
 * @return true если успешно, false если ошибка
 */
bool initCamera() {
    Serial.println("[CAM] Инициализируем камеру...");

    camera_config_t config;

    // Пины (заполнены выше через #define)
    config.ledc_channel  = LEDC_CHANNEL_0;
    config.ledc_timer    = LEDC_TIMER_0;
    config.pin_d0        = Y2_GPIO_NUM;
    config.pin_d1        = Y3_GPIO_NUM;
    config.pin_d2        = Y4_GPIO_NUM;
    config.pin_d3        = Y5_GPIO_NUM;
    config.pin_d4        = Y6_GPIO_NUM;
    config.pin_d5        = Y7_GPIO_NUM;
    config.pin_d6        = Y8_GPIO_NUM;
    config.pin_d7        = Y9_GPIO_NUM;
    config.pin_xclk      = XCLK_GPIO_NUM;
    config.pin_pclk      = PCLK_GPIO_NUM;
    config.pin_vsync     = VSYNC_GPIO_NUM;
    config.pin_href      = HREF_GPIO_NUM;
    config.pin_sccb_sda  = SIOD_GPIO_NUM;
    config.pin_sccb_scl  = SIOC_GPIO_NUM;
    config.pin_pwdn      = PWDN_GPIO_NUM;
    config.pin_reset     = RESET_GPIO_NUM;

    // Тактирование камеры
    config.xclk_freq_hz  = 20000000;          // 20 МГц
    config.pixel_format  = PIXFORMAT_JPEG;    // JPEG - экономим память

    // Используем OPI PSRAM для буфера кадра
    // N16R8 имеет 8MB PSRAM — используем ps_malloc
    if (psramFound()) {
        Serial.println("[CAM] OPI PSRAM найдена, используем для буфера кадра");
        config.frame_size   = FRAMESIZE_SVGA; // 800x600
        config.jpeg_quality = 12;             // 0=лучшее, 63=хуже. 12 — хороший баланс
        config.fb_count     = 2;              // Double buffering для скорости
        config.fb_location  = CAMERA_FB_IN_PSRAM;
        config.grab_mode    = CAMERA_GRAB_LATEST; // Всегда свежий кадр
    } else {
        // Fallback на маленькое разрешение без PSRAM
        Serial.println("[CAM] PSRAM не найдена, используем QVGA");
        config.frame_size   = FRAMESIZE_QVGA; // 320x240
        config.jpeg_quality = 15;
        config.fb_count     = 1;
        config.fb_location  = CAMERA_FB_IN_DRAM;
        config.grab_mode    = CAMERA_GRAB_WHEN_EMPTY;
    }

    // Инициализируем
    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("[CAM] Ошибка инициализации: 0x%x\n", err);
        return false;
    }

    // Дополнительные настройки сенсора OV3660
    sensor_t* s = esp_camera_sensor_get();
    if (s != nullptr) {
        s->set_brightness(s, 0);      // яркость (-2..2)
        s->set_contrast(s, 0);        // контраст (-2..2)
        s->set_saturation(s, 0);      // насыщенность (-2..2)
        s->set_sharpness(s, 2);       // резкость — OV3660 поддерживает до 2
        s->set_denoise(s, 1);         // шумоподавление
        s->set_awb_gain(s, 1);        // автобаланс белого
        s->set_gain_ctrl(s, 1);       // автоусиление — включаем для OV3660
        s->set_exposure_ctrl(s, 1);   // автоэкспозиция — включаем для OV3660
        s->set_hmirror(s, 0);         // горизонтальное зеркало
        s->set_vflip(s, 1);           // OV3660 обычно требует vflip=1
        Serial.println("[CAM] Параметры сенсора OV3660 настроены");
    }

    Serial.println("[CAM] Камера инициализирована успешно");
    return true;
}

// ============================================================
// ИНИЦИАЛИЗАЦИЯ BLE
// ============================================================

/**
 * Настраивает BLE GATT-сервер с сервисом камеры.
 */
void initBLE() {
    Serial.println("[BLE] Инициализируем BLE...");

    // Имя устройства в Bluetooth рекламе
    BLEDevice::init("ESP32-CAM");

    // Устанавливаем максимальный MTU (517 байт = 512 данных + 5 заголовок)
    BLEDevice::setMTU(517);

    // Устанавливаем мощность сигнала (максимум для надёжности)
    BLEDevice::setPower(ESP_PWR_LVL_P9);

    // Создаём GATT-сервер
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    // Создаём GATT-сервис
    BLEService* pService = pServer->createService(SERVICE_UUID);

    // ---- COMMAND характеристика (write) ----
    // Телефон пишет 0x01 чтобы запросить снимок
    pCommandChar = pService->createCharacteristic(
        COMMAND_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_WRITE_NR  // Write Without Response для скорости
    );
    pCommandChar->setCallbacks(new CommandCallbacks());

    // ---- DATA характеристика (notify) ----
    // ESP32 отправляет JPEG чанками через notify
    pDataChar = pService->createCharacteristic(
        DATA_CHAR_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pDataChar->addDescriptor(new BLE2902());

    // ---- EVENT характеристика (notify) ----
    // ESP32 отправляет события кнопки: 0x02=нажата, 0x03=отпущена
    pEventChar = pService->createCharacteristic(
        EVENT_CHAR_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pEventChar->addDescriptor(new BLE2902());

    // Запускаем сервис
    pService->start();

    // ---- BLE Advertising (реклама) ----
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID); // Добавляем UUID сервиса
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // Рекомендовано для iOS-совместимости
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[BLE] BLE сервер запущен, ожидаем подключения...");
    Serial.println("[BLE] Имя устройства: ESP32-CAM");
    Serial.println("[BLE] Service UUID: " SERVICE_UUID);
}

// ============================================================
// ЗАХВАТ И ПЕРЕДАЧА ФОТО
// ============================================================

/**
 * Захватывает фото с камеры и отправляет по BLE чанками.
 *
 * Протокол чанка:
 * - Байт 0: старший байт порядкового номера (big-endian)
 * - Байт 1: младший байт порядкового номера
 * - Байт 2: flags (0x00=промежуточный, 0xFF=последний)
 * - Байты 3..N: данные JPEG
 */
void captureAndSend() {
    Serial.println("[CAM] Захватываем фото...");

    // Мигаем LED во время захвата
    digitalWrite(LED_GPIO, HIGH);

    // Сбрасываем старые буферизованные кадры, чтобы получить свежий снимок
    for (int i = 0; i < 3; i++) {
        camera_fb_t* old = esp_camera_fb_get();
        if (old) esp_camera_fb_return(old);
    }

    // Захватываем свежий кадр
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("[CAM] Ошибка захвата кадра!");
        digitalWrite(LED_GPIO, LOW);
        return;
    }

    Serial.printf("[CAM] Фото захвачено: %zu байт, %dx%d\n",
                  fb->len, fb->width, fb->height);

    if (!deviceConnected) {
        Serial.println("[BLE] Клиент отключился, прерываем передачу");
        esp_camera_fb_return(fb);
        digitalWrite(LED_GPIO, LOW);
        return;
    }

    // Вычисляем количество чанков
    size_t totalBytes = fb->len;
    uint16_t totalChunks = (totalBytes + CHUNK_SIZE - 1) / CHUNK_SIZE;

    Serial.printf("[BLE] Начинаем передачу: %zu байт, %d чанков\n",
                  totalBytes, totalChunks);

    // Буфер для одного чанка: 3 байта заголовка + CHUNK_SIZE данных
    uint8_t chunkBuf[3 + CHUNK_SIZE];
    size_t bytesSent = 0;
    uint16_t seqNum = 0;

    while (bytesSent < totalBytes) {
        if (!deviceConnected) {
            Serial.println("[BLE] Клиент отключился во время передачи!");
            break;
        }

        // Размер данных в этом чанке
        size_t dataSize = min((size_t)CHUNK_SIZE, totalBytes - bytesSent);

        // Флаг последнего чанка
        bool isLast = (bytesSent + dataSize >= totalBytes);

        // Формируем заголовок
        chunkBuf[0] = (uint8_t)(seqNum >> 8);     // seq_high
        chunkBuf[1] = (uint8_t)(seqNum & 0xFF);   // seq_low
        chunkBuf[2] = isLast ? 0xFF : 0x00;        // flags

        // Копируем данные
        memcpy(chunkBuf + 3, fb->buf + bytesSent, dataSize);

        // Отправляем notify
        pDataChar->setValue(chunkBuf, 3 + dataSize);
        pDataChar->notify();

        bytesSent += dataSize;
        seqNum++;

        // Мигаем LED
        digitalWrite(LED_GPIO, seqNum % 2 == 0 ? HIGH : LOW);

        // Небольшая пауза для предотвращения переполнения BLE-стека
        delay(SEND_DELAY_MS);

        // Лог прогресса каждые 20 чанков
        if (seqNum % 20 == 0) {
            Serial.printf("[BLE] Отправлено: %zu/%zu байт (чанк %d/%d)\n",
                          bytesSent, totalBytes, seqNum, totalChunks);
        }
    }

    // Освобождаем буфер кадра (важно!)
    esp_camera_fb_return(fb);

    // Гасим LED
    digitalWrite(LED_GPIO, LOW);

    if (deviceConnected) {
        Serial.printf("[BLE] Передача завершена: отправлено %d чанков, %zu байт\n",
                      seqNum, bytesSent);
    }
}

// ============================================================
// SETUP
// ============================================================

void setup() {
    Serial.begin(115200);
    Serial.println("\n========================================");
    Serial.println("  ESP32-S3 BLE CAM — Запуск прошивки");
    Serial.println("========================================");

    // Настраиваем LED и кнопку
    pinMode(LED_GPIO, OUTPUT);
    digitalWrite(LED_GPIO, LOW);
    pinMode(BUTTON_GPIO, INPUT_PULLUP);

    // Тестовое мигание LED при старте
    for (int i = 0; i < 3; i++) {
        digitalWrite(LED_GPIO, HIGH);
        delay(100);
        digitalWrite(LED_GPIO, LOW);
        delay(100);
    }

    // Проверяем PSRAM
    if (psramFound()) {
        Serial.printf("[SYS] OPI PSRAM найдена: %d байт\n", ESP.getPsramSize());
    } else {
        Serial.println("[SYS] PSRAM НЕ найдена! Работаем без неё.");
    }

    Serial.printf("[SYS] Flash: %d байт, Heap: %d байт\n",
                  ESP.getFlashChipSize(), ESP.getFreeHeap());

    // Инициализируем камеру
    if (!initCamera()) {
        Serial.println("[ERROR] Не удалось инициализировать камеру!");
        Serial.println("[ERROR] Проверьте пины и подключение камеры");
        // Мигаем быстро — ошибка камеры
        while (true) {
            digitalWrite(LED_GPIO, HIGH);
            delay(100);
            digitalWrite(LED_GPIO, LOW);
            delay(100);
        }
    }

    // Инициализируем BLE
    initBLE();

    Serial.println("[SYS] Система готова. Ожидаем BLE-подключения...");
    Serial.printf("[SYS] Свободная память после инициализации: %d байт\n",
                  ESP.getFreeHeap());
}

// ============================================================
// LOOP
// ============================================================

void loop() {
    // Проверяем запрос на захват фото
    if (captureRequested && deviceConnected) {
        captureRequested = false;
        captureAndSend();
    }

    // Антидребезг кнопки и отправка BLE-событий
    bool raw = digitalRead(BUTTON_GPIO);
    if (raw != btnLastRaw) {
        btnDebounceMs = millis();
        btnLastRaw = raw;
    }
    if ((millis() - btnDebounceMs) > DEBOUNCE_MS && raw != btnState) {
        btnState = raw;
        const char* label = (btnState == LOW) ? "Нажата" : "Отпущена";
        Serial.printf("[BTN] %s (GPIO%d)\n", label, BUTTON_GPIO);
        if (deviceConnected && pEventChar) {
            uint8_t evt = (btnState == LOW) ? 0x02 : 0x03;
            pEventChar->setValue(&evt, 1);
            pEventChar->notify();
            Serial.printf("[BTN] BLE событие отправлено: 0x%02X\n", evt);
        }
    }

    delay(10);
}
