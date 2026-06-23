"""Обучение blind_v3 на Windows с RTX 4060.

Шаги перед запуском:
  1. Распаковать blind_v3_dataset.zip в ту же папку где лежит этот скрипт
     Структура должна быть:
       train_windows.py
       dataset/
         images/train/...
         images/val/...
         labels/train/...
         labels/val/...
         data.yaml
  2. Установить зависимости (через setup.bat)
  3. Запустить:  python train_windows.py
"""
from pathlib import Path
import torch
import yaml

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "dataset" / "data.yaml"


def main():
    from ultralytics import YOLO

    print(f"torch={torch.__version__}, cuda={torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"GPU: {torch.cuda.get_device_name(0)}")

    # Подмена пути в data.yaml на актуальный (Windows)
    y = yaml.safe_load(open(DATA))
    y['path'] = str(ROOT / "dataset")
    yaml.safe_dump(y, open(DATA, "w"))

    device = "cuda" if torch.cuda.is_available() else "cpu"

    model = YOLO("yolov8n.pt")

    model.train(
        data    = str(DATA),
        epochs  = 50,
        imgsz   = 640,
        batch   = 32,         # RTX 4060 8GB справится
        device  = device,
        patience= 12,
        project = str(ROOT / "runs"),
        name    = "blind_v3",
        save    = True,
        plots   = True,
        augment = True,
        mosaic  = 1.0,
        mixup   = 0.1,
        workers = 4,          # на Windows меньше = стабильнее
        cache   = False,      # 48ГБ RAM нет, кеш не влезет
        exist_ok= True,
    )

    # Экспорт в ONNX для Flutter
    print("\n=== Экспорт в ONNX (opset=12) ===")
    best = ROOT / "runs" / "blind_v3" / "weights" / "best.pt"
    m = YOLO(str(best))
    onnx_path = m.export(format="onnx", opset=12, simplify=True, dynamic=False)
    print(f"\nONNX готов: {onnx_path}")
    print("Скопируй этот файл обратно на Mac в:")
    print("  /Users/nexor/StudioProjects/untitled1/assets/models/blind.onnx")


if __name__ == "__main__":
    # На Windows обязательно нужно — иначе DataLoader workers падают
    import multiprocessing
    multiprocessing.freeze_support()
    main()
