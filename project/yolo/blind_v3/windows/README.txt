=== Обучение blind_v3 на Windows + RTX 4060 ===

ФАЙЛЫ:
- setup.bat            - установка PyTorch CUDA + ultralytics
- train_windows.py     - сам скрипт обучения
- blind_v3_dataset.zip - датасет (на рабочем столе Mac)

ПЛАН:
1. Создай папку, например C:\blind_v3\
2. Скопируй туда:
     - setup.bat
     - train_windows.py
     - blind_v3_dataset.zip
3. Распакуй zip в эту же папку (получится C:\blind_v3\dataset\...)
4. Дабл-клик на setup.bat → подождать установки (~3-5 мин)
5. В консоли запусти: python train_windows.py

ВРЕМЯ:
- ~5-8 минут на эпоху
- 50 эпох максимум, patience=12 (остановится раньше если плато)
- ИТОГО: 2-4 часа

ПОСЛЕ ОБУЧЕНИЯ:
- Файл будет: C:\blind_v3\runs\blind_v3\weights\best.onnx
- Скопируй его обратно на Mac:
    /Users/nexor/StudioProjects/untitled1/assets/models/blind.onnx
- На Mac я тебе соберу APK с новой моделью

ЕСЛИ CUDA НЕТ:
- Установи последний драйвер NVIDIA
- Перезапусти setup.bat
