@echo off
REM Установка зависимостей для обучения на Windows + RTX 4060
echo === Создание venv ===
python -m venv venv
call venv\Scripts\activate.bat

echo === Обновление pip ===
python -m pip install --upgrade pip

echo === PyTorch с CUDA 12.1 ===
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

echo === Ultralytics + остальное ===
pip install ultralytics pyyaml

echo.
echo === Проверка CUDA ===
python -c "import torch; print('CUDA:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NONE')"

echo.
echo Готово. Теперь:
echo   1. Распакуй blind_v3_dataset.zip в эту папку
echo   2. Запусти: python train_windows.py
pause
