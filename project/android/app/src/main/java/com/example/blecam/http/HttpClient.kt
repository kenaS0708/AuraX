package com.example.blecam.http

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * HttpClient — отправляет JPEG на сервер и получает текстовое описание.
 *
 * Использует OkHttp3 для multipart/form-data POST запроса.
 * Ответ сервера: {"text": "описание фото"}
 */
class HttpClient {

    companion object {
        private const val TAG = "HttpClient"
        /** Имя поля в multipart форме — должно совпадать с сервером */
        private const val FIELD_NAME = "file"
    }

    /** OkHttp клиент с настроенными таймаутами */
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)  // таймаут подключения
        .writeTimeout(30, TimeUnit.SECONDS)    // таймаут отправки файла
        .readTimeout(60, TimeUnit.SECONDS)     // таймаут ответа (Claude может думать долго)
        .build()

    /**
     * Отправляет JPEG на сервер и возвращает текст описания.
     *
     * @param serverUrl URL сервера, например "http://192.168.1.10:8080/upload"
     * @param jpegBytes байты JPEG-изображения
     * @return текстовое описание или null при ошибке
     */
    suspend fun uploadPhoto(serverUrl: String, jpegBytes: ByteArray): Result<String> {
        return withContext(Dispatchers.IO) {
            try {
                Log.i(TAG, "Отправляем JPEG (${jpegBytes.size} байт) на $serverUrl")

                // Формируем multipart тело запроса
                val requestBody = MultipartBody.Builder()
                    .setType(MultipartBody.FORM)
                    .addFormDataPart(
                        name = FIELD_NAME,
                        filename = "photo_${System.currentTimeMillis()}.jpg",
                        body = jpegBytes.toRequestBody("image/jpeg".toMediaType())
                    )
                    .build()

                val request = Request.Builder()
                    .url(serverUrl)
                    .post(requestBody)
                    .build()

                // Выполняем синхронный запрос (мы уже в IO диспетчере)
                val response = client.newCall(request).execute()

                if (!response.isSuccessful) {
                    val errorBody = response.body?.string() ?: ""
                    Log.e(TAG, "Сервер вернул ошибку ${response.code}: $errorBody")
                    return@withContext Result.failure(
                        IOException("Ошибка сервера: ${response.code}")
                    )
                }

                // Парсим JSON ответ
                val responseBody = response.body?.string() ?: run {
                    Log.e(TAG, "Пустой ответ от сервера")
                    return@withContext Result.failure(IOException("Пустой ответ сервера"))
                }

                Log.i(TAG, "Ответ сервера: $responseBody")

                val json = JSONObject(responseBody)
                val text = json.optString("text", "").trim()

                if (text.isEmpty()) {
                    Log.w(TAG, "Поле 'text' пустое в ответе сервера")
                    return@withContext Result.failure(IOException("Пустой текст в ответе"))
                }

                Log.i(TAG, "Получено описание: $text")
                Result.success(text)

            } catch (e: IOException) {
                Log.e(TAG, "Сетевая ошибка: ${e.message}")
                Result.failure(e)
            } catch (e: Exception) {
                Log.e(TAG, "Неожиданная ошибка: ${e.message}")
                Result.failure(e)
            }
        }
    }
}
