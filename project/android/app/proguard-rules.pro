# Proguard rules для BLE CAM

# Сохраняем OkHttp классы
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Сохраняем BLE классы Android
-keep class android.bluetooth.** { *; }

# Сохраняем DataStore
-keep class androidx.datastore.** { *; }
