# BLE CAM — Умная камера на ESP32 с Android-клиентом

Система из трёх компонентов:
- **Android-приложение** — подключается к ESP32 по BLE, получает JPEG, отправляет на сервер, озвучивает ответ ИИ
- **Прошивка ESP32-S3 CAM** — BLE GATT-сервер, захват фото с камеры, стриминг по BLE
- **Python-сервер** — принимает JPEG, описывает через Claude Vision API, возвращает текст

---

## Структура проекта

```
project/
├── android/           ← Android Studio проект
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── java/com/example/blecam/
│   │   │   │   ├── MainActivity.kt
│   │   │   │   ├── ble/BleManager.kt
│   │   │   │   ├── http/HttpClient.kt
│   │   │   │   ├── viewmodel/MainViewModel.kt
│   │   │   │   └── ui/theme/
│   │   │   │       ├── Theme.kt
│   │   │   │       ├── Type.kt
│   │   │   │       └── Color.kt
│   │   │   ├── AndroidManifest.xml
│   │   │   └── res/
│   │   ├── build.gradle.kts
│   │   └── proguard-rules.pro
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   └── gradle/wrapper/
├── esp32/
│   └── esp32_ble_cam/
│       └── esp32_ble_cam.ino
├── server/
│   ├── server.py
│   └── requirements.txt
└── README.md
```

---

## ЧАСТЬ 1 — Сборка Android APK

### Требования
- Android Studio Hedgehog (2023.1.1) или новее
- JDK 17
- Android SDK: minSdk 26, targetSdk 34, compileSdk 34
- Интернет (Gradle скачает зависимости)

### Шаги

1. **Откройте проект в Android Studio:**
   ```
   File → Open → выберите папку project/android/
   ```

2. **Дождитесь синхронизации Gradle** (первый раз ~5 минут, скачивает зависимости)

3. **Проверьте шрифты** — файлы `space_grotesk.ttf` и `jetbrains_mono.ttf` нужно добавить вручную:
   - Скачайте [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) и [JetBrains Mono](https://www.jetbrains.com/lp/mono/)
   - Поместите в `app/src/main/res/font/space_grotesk.ttf` и `jetbrains_mono.ttf`

4. **Соберите APK:**
   ```
   Build → Build Bundle(s) / APK(s) → Build APK(s)
   ```
   APK будет в `app/build/outputs/apk/debug/app-debug.apk`

5. **Установите на телефон:**
   ```bash
   adb install app/build/outputs/apk/debug/app-debug.apk
   ```
   Или через Android Studio: Run → Run 'app'

### Разрешения (запрашиваются при первом запуске)
- `BLUETOOTH_SCAN` — сканирование BLE-устройств
- `BLUETOOTH_CONNECT` — подключение к ESP32
- `INTERNET` — отправка фото на сервер

---

## ЧАСТЬ 2 — Прошивка ESP32-S3

### Оборудование
- AI-Thinker ESP32-S3-CAM N16R8 (16MB Flash, 8MB OPI PSRAM)

### Настройка Arduino IDE

1. **Установите Arduino IDE 2.x**

2. **Добавьте поддержку ESP32:**
   - File → Preferences → Additional boards manager URLs:
     ```
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
     ```
   - Tools → Board → Boards Manager → поищите `esp32` → установите `esp32 by Espressif Systems` (версия ≥ 3.0.0)

3. **Выберите плату и настройки:**
   - Tools → Board → ESP32 Arduino → **ESP32S3 Dev Module**
   - Tools → Flash Size: **16MB (128Mb)**
   - Tools → PSRAM: **OPI PSRAM**
   - Tools → Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**
   - Tools → Upload Speed: **921600**
   - Tools → CPU Frequency: **240MHz (WiFi)**

4. **Откройте скетч:** `esp32/esp32_ble_cam/esp32_ble_cam.ino`

5. **Загрузите прошивку:**
   - Зажмите BOOT, нажмите RESET, отпустите BOOT
   - Нажмите Upload в Arduino IDE
   - После загрузки нажмите RESET

6. **Мониторинг:** Tools → Serial Monitor, 115200 baud

### Пины камеры (AI-Thinker ESP32-S3-CAM N16R8)
```
XCLK=15  SIOD=4   SIOC=5
Y2=11    Y3=9     Y4=8    Y5=10
Y6=12    Y7=18    Y8=17   Y9=16
VSYNC=6  HREF=7   PCLK=13
PWDN=-1  RESET=-1
```

---

## ЧАСТЬ 3 — Python-сервер

### Требования
- Python 3.10+
- Ключ Anthropic API

### Установка и запуск

```bash
cd project/server/

# Создайте виртуальное окружение
python3 -m venv venv
source venv/bin/activate   # Linux/Mac
# или: venv\Scripts\activate  # Windows

# Установите зависимости
pip install -r requirements.txt

# Задайте API-ключ
export ANTHROPIC_API_KEY="sk-ant-..."

# Запустите сервер (порт 8080 по умолчанию)
python server.py

# Или на кастомном порту
PORT=9000 python server.py
```

### Проверка
```bash
curl -X POST http://localhost:8080/upload \
  -F "file=@test.jpg"
# Ответ: {"text": "На фото ..."}
```

### Настройка в Android-приложении
В настройках приложения (долгое нажатие на статусбар) введите:
```
http://192.168.1.XXX:8080/upload
```
(замените IP на IP вашего компьютера)

---

## BLE-протокол

| Параметр | Значение |
|----------|----------|
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` |
| COMMAND char (write) | `beb5483e-36e1-4688-b7f5-ea07361b26a8` |
| DATA char (notify) | `beb5483e-36e1-4688-b7f5-ea07361b26a9` |
| Размер чанка | 512 байт данных + 3 байта заголовок |
| Формат чанка | `[seq_high][seq_low][flags][data...]` |
| flags=0x00 | промежуточный чанк |
| flags=0xFF | последний чанк (конец JPEG) |

---

## Быстрый старт

1. Запустите сервер на компьютере, запомните его IP
2. Прошейте ESP32, убедитесь что он виден в Bluetooth
3. Установите APK на Android-телефон
4. Долгим нажатием на статусбар откройте настройки, введите URL сервера и имя BLE-устройства
5. Нажмите большую кнопку — она просканирует BLE, подключится к ESP32, снимет фото и озвучит описание

---

## Лицензия
MIT
