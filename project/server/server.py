#!/usr/bin/env python3
"""
server.py — HTTP-сервер для анализа фотографий через Claude Vision API

Функциональность:
- POST /upload — принимает JPEG изображение (multipart/form-data, поле 'file')
- Отправляет изображение в Claude Vision API (claude-opus-4-5)
- Возвращает JSON с описанием фото на русском языке
- Сохраняет фото локально в папку uploads/
- Печатает IP-адрес клиента при каждом запросе

Требования:
- Python 3.10+
- pip install anthropic flask python-dotenv

Переменные окружения:
- ANTHROPIC_API_KEY: API ключ Anthropic (обязательно)
- PORT: порт сервера (по умолчанию 8080)
- HOST: адрес для прослушивания (по умолчанию 0.0.0.0)

Запуск:
    export ANTHROPIC_API_KEY="sk-ant-..."
    python server.py
"""

import os
import base64
import logging
import datetime
from pathlib import Path
from typing import Optional

import anthropic
from flask import Flask, request, jsonify

# ============================================================
# НАСТРОЙКИ
# ============================================================

# Папка для сохранения входящих фотографий
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

# Порт и хост из переменных окружения (или дефолты)
PORT = int(os.environ.get("PORT", 8080))
HOST = os.environ.get("HOST", "0.0.0.0")

# Модель Claude для анализа изображений
CLAUDE_MODEL = "claude-opus-4-5"

# Промт для описания фото
VISION_PROMPT = (
    "Опиши что на фото. "
    "Отвечай на русском языке. "
    "Будь лаконичен — 1-2 предложения."
)

# ============================================================
# ЛОГИРОВАНИЕ
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S"
)
log = logging.getLogger("ble-cam-server")

# ============================================================
# FLASK ПРИЛОЖЕНИЕ
# ============================================================

app = Flask(__name__)

# ============================================================
# ANTHROPIC КЛИЕНТ
# ============================================================

def get_anthropic_client() -> anthropic.Anthropic:
    """
    Создаёт клиент Anthropic API.
    Ключ берётся из переменной ANTHROPIC_API_KEY.
    Падает с понятным сообщением если ключ не задан.
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "Не задана переменная ANTHROPIC_API_KEY!\n"
            "Запустите: export ANTHROPIC_API_KEY='sk-ant-...'"
        )
    return anthropic.Anthropic(api_key=api_key)

# ============================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================

def save_photo(jpeg_bytes: bytes) -> str:
    """
    Сохраняет JPEG на диск с уникальным именем на основе timestamp.

    Args:
        jpeg_bytes: байты JPEG изображения

    Returns:
        Путь к сохранённому файлу
    """
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    filename = UPLOAD_DIR / f"photo_{timestamp}.jpg"
    filename.write_bytes(jpeg_bytes)
    log.info(f"Фото сохранено: {filename} ({len(jpeg_bytes)} байт)")
    return str(filename)


def analyze_image(jpeg_bytes: bytes) -> str:
    """
    Отправляет изображение в Claude Vision API и возвращает описание.

    Args:
        jpeg_bytes: байты JPEG изображения

    Returns:
        Текстовое описание изображения на русском языке

    Raises:
        anthropic.APIError: при ошибке API
    """
    client = get_anthropic_client()

    # Кодируем изображение в base64 для API
    image_data = base64.standard_b64encode(jpeg_bytes).decode("utf-8")

    log.info(f"Отправляем изображение в Claude Vision ({len(jpeg_bytes)} байт)...")

    # Формируем запрос с изображением
    message = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=256,  # Достаточно для 1-2 предложений
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_data,
                        },
                    },
                    {
                        "type": "text",
                        "text": VISION_PROMPT
                    }
                ],
            }
        ],
    )

    # Извлекаем текстовый ответ
    response_text = message.content[0].text.strip()
    log.info(f"Ответ Claude: {response_text}")

    return response_text

# ============================================================
# МАРШРУТЫ
# ============================================================

@app.route("/upload", methods=["POST"])
def upload_photo():
    """
    POST /upload — принимает JPEG и возвращает описание.

    Ожидаемый запрос:
        Content-Type: multipart/form-data
        Поле 'file': JPEG файл

    Ответ:
        {"text": "Описание фото на русском языке"}

    Ошибки:
        400 — нет файла в запросе
        415 — файл не является JPEG
        500 — ошибка API или сервера
    """
    # ---- Логируем клиента ----
    client_ip = request.remote_addr
    forwarded_for = request.headers.get("X-Forwarded-For")
    display_ip = forwarded_for or client_ip
    log.info(f"Запрос от IP: {display_ip}")

    # ---- Проверяем наличие файла ----
    if "file" not in request.files:
        log.warning("Запрос без поля 'file'")
        return jsonify({"error": "Поле 'file' не найдено в запросе"}), 400

    file = request.files["file"]

    if file.filename == "":
        log.warning("Пустое имя файла")
        return jsonify({"error": "Файл не выбран"}), 400

    # ---- Читаем байты ----
    jpeg_bytes = file.read()

    if len(jpeg_bytes) == 0:
        log.warning("Получен пустой файл")
        return jsonify({"error": "Пустой файл"}), 400

    # ---- Базовая проверка JPEG (заголовок FF D8) ----
    if len(jpeg_bytes) < 2 or jpeg_bytes[0] != 0xFF or jpeg_bytes[1] != 0xD8:
        log.warning(f"Файл не является JPEG (первые байты: {jpeg_bytes[:4].hex()})")
        return jsonify({"error": "Файл не является корректным JPEG"}), 415

    log.info(f"Получено изображение: {len(jpeg_bytes)} байт")

    # ---- Сохраняем фото ----
    try:
        saved_path = save_photo(jpeg_bytes)
    except OSError as e:
        log.error(f"Ошибка сохранения файла: {e}")
        # Не критично — продолжаем даже если не сохранили
        saved_path = None

    # ---- Анализируем через Claude ----
    try:
        description = analyze_image(jpeg_bytes)
    except EnvironmentError as e:
        log.error(f"Ошибка конфигурации: {e}")
        return jsonify({"error": str(e)}), 500
    except anthropic.APIConnectionError as e:
        log.error(f"Ошибка подключения к Anthropic API: {e}")
        return jsonify({"error": "Не удалось подключиться к Anthropic API"}), 502
    except anthropic.RateLimitError as e:
        log.error(f"Превышен лимит Anthropic API: {e}")
        return jsonify({"error": "Превышен лимит запросов к API"}), 429
    except anthropic.APIStatusError as e:
        log.error(f"Ошибка Anthropic API (статус {e.status_code}): {e.message}")
        return jsonify({"error": f"Ошибка API: {e.message}"}), 500
    except Exception as e:
        log.error(f"Неожиданная ошибка: {e}")
        return jsonify({"error": "Внутренняя ошибка сервера"}), 500

    # ---- Возвращаем результат ----
    return jsonify({"text": description})


@app.route("/health", methods=["GET"])
def health_check():
    """
    GET /health — проверка работоспособности сервера.
    Полезно для мониторинга.
    """
    return jsonify({
        "status": "ok",
        "model": CLAUDE_MODEL,
        "uploads_dir": str(UPLOAD_DIR.absolute()),
        "saved_photos": len(list(UPLOAD_DIR.glob("*.jpg")))
    })


@app.route("/", methods=["GET"])
def index():
    """Главная страница с краткой документацией."""
    return """
    <html>
    <head><title>BLE CAM Server</title></head>
    <body style="font-family: monospace; background: #0a0a0a; color: #00d4ff; padding: 40px;">
        <h1>BLE CAM Server</h1>
        <p>Сервер для анализа фотографий с ESP32 через Claude Vision API</p>
        <hr style="border-color: #333">
        <h2>API</h2>
        <p><b>POST /upload</b> — загрузить фото (multipart/form-data, поле 'file')</p>
        <p><b>GET /health</b> — проверка состояния</p>
        <hr style="border-color: #333">
        <p style="color: #666">Модель: """ + CLAUDE_MODEL + """</p>
    </body>
    </html>
    """

# ============================================================
# ТОЧКА ВХОДА
# ============================================================

if __name__ == "__main__":
    log.info("=" * 50)
    log.info("  BLE CAM Server — Запуск")
    log.info("=" * 50)
    log.info(f"Модель: {CLAUDE_MODEL}")
    log.info(f"Папка для загрузок: {UPLOAD_DIR.absolute()}")

    # Проверяем наличие API ключа при старте
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        log.warning("=" * 50)
        log.warning("ВНИМАНИЕ: ANTHROPIC_API_KEY не задан!")
        log.warning("Запросы к /upload будут возвращать ошибку 500")
        log.warning("Задайте ключ: export ANTHROPIC_API_KEY='sk-ant-...'")
        log.warning("=" * 50)
    else:
        log.info(f"API ключ: sk-ant-...{api_key[-6:]}")

    log.info(f"Запускаем сервер на http://{HOST}:{PORT}")
    log.info("Для остановки нажмите Ctrl+C")
    log.info("=" * 50)

    # Запуск Flask сервера
    # debug=False в продакшене
    app.run(
        host=HOST,
        port=PORT,
        debug=False,
        threaded=True  # Обработка нескольких запросов одновременно
    )
