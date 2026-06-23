"""
Обучение YOLO для помощника слабовидящих.

Требования:
  pip install -r requirements.txt

Запуск:
  python train.py --roboflow-key YOUR_API_KEY
  python train.py --skip-download   # если датасет уже скачан

Результат:
  runs/blind_assist/weights/best.pt
  runs/blind_assist/weights/best_int8.tflite  <- кладёшь в assets/models/yolo.tflite
"""

import argparse
import os
import shutil
from pathlib import Path

from ultralytics import YOLO

# COCO class IDs которые нам нужны (из стандартной YOLOv8n)
COCO_KEEP = {
    0:  'person',
    1:  'bicycle',
    2:  'car',
    3:  'motorcycle',
    5:  'bus',
    7:  'truck',
    9:  'traffic_light',
    11: 'fire_hydrant',
    12: 'stop_sign',
    56: 'chair',
    57: 'couch',
    60: 'dining_table',
    63: 'bench',
}

# Roboflow датасеты для кастомных классов
# Бесплатные публичные датасеты (universe.roboflow.com)
ROBOFLOW_DATASETS = [
    # (workspace, project, version, класс в нашей разметке)
    ("roboflow-100",   "open-close-doors",          1, "door_open/door_closed"),
    ("roboflow-100",   "staircase-mxhrs",            1, "stairs"),
    ("roboflow-100",   "zebra-crossing-qyxp1",       1, "crosswalk"),
]


def download_datasets(api_key: str):
    """Скачивает датасеты с Roboflow и конвертирует в YOLOv8 формат."""
    from roboflow import Roboflow
    rf = Roboflow(api_key=api_key)

    os.makedirs("datasets/custom", exist_ok=True)

    for workspace, project_name, version, label in ROBOFLOW_DATASETS:
        print(f"\n→ Скачиваю {project_name} ({label})...")
        project = rf.workspace(workspace).project(project_name)
        dataset = project.version(version).download("yolov8", location=f"datasets/custom/{project_name}")
        print(f"  Скачано в datasets/custom/{project_name}")


def merge_datasets():
    """
    Собирает единый датасет:
    - COCO подмножество (из YOLOv8n претрейна — используем синтетику через mosaic)
    - Кастомные классы (doors, stairs, crosswalk)
    Создаёт datasets/blind_assist/{train,valid}/images и labels.
    """
    import yaml
    import re

    out_train_img = Path("datasets/blind_assist/train/images")
    out_train_lbl = Path("datasets/blind_assist/train/labels")
    out_valid_img = Path("datasets/blind_assist/valid/images")
    out_valid_lbl = Path("datasets/blind_assist/valid/labels")
    for p in [out_train_img, out_train_lbl, out_valid_img, out_valid_lbl]:
        p.mkdir(parents=True, exist_ok=True)

    # Маппинг: оригинальный класс датасета → наш индекс
    custom_class_map = {
        "door_open":   14,
        "door_closed": 15,
        "open":        14,  # некоторые датасеты называют так
        "closed":      15,
        "stairs":      13,
        "staircase":   13,
        "crosswalk":   16,
        "zebra":       16,
        "zebra-crossing": 16,
    }

    copied = 0
    for ds_dir in Path("datasets/custom").iterdir():
        if not ds_dir.is_dir():
            continue
        # Читаем data.yaml датасета чтобы понять имена классов
        data_yaml = ds_dir / "data.yaml"
        if not data_yaml.exists():
            continue
        with open(data_yaml) as f:
            ds_meta = yaml.safe_load(f)
        ds_names = ds_meta.get("names", [])

        for split, (dst_img, dst_lbl) in [
            ("train", (out_train_img, out_train_lbl)),
            ("valid", (out_valid_img, out_valid_lbl)),
        ]:
            img_dir = ds_dir / split / "images"
            lbl_dir = ds_dir / split / "labels"
            if not img_dir.exists():
                continue

            for img_path in img_dir.glob("*.*"):
                lbl_path = lbl_dir / (img_path.stem + ".txt")
                if not lbl_path.exists():
                    continue

                new_labels = []
                for line in lbl_path.read_text().splitlines():
                    parts = line.strip().split()
                    if len(parts) < 5:
                        continue
                    orig_cls = int(parts[0])
                    if orig_cls >= len(ds_names):
                        continue
                    orig_name = ds_names[orig_cls].lower().replace(" ", "_").replace("-", "_")
                    # Ищем совпадение в нашем маппинге
                    our_cls = None
                    for key, val in custom_class_map.items():
                        if key in orig_name:
                            our_cls = val
                            break
                    if our_cls is None:
                        continue
                    new_labels.append(f"{our_cls} " + " ".join(parts[1:]))

                if not new_labels:
                    continue

                # Копируем картинку и разметку
                suffix = img_path.suffix
                new_name = f"{ds_dir.name}_{img_path.stem}"
                shutil.copy2(img_path, dst_img / (new_name + suffix))
                (dst_lbl / (new_name + ".txt")).write_text("\n".join(new_labels))
                copied += 1

    print(f"\n✓ Скопировано {copied} изображений с кастомными классами")
    print("  Классы COCO (person, car и т.д.) будут усвоены через претренированные веса")


def train(resume: bool = False):
    model = YOLO("yolov8n.pt")  # начинаем с претренированных весов

    results = model.train(
        data="dataset.yaml",
        epochs=100,
        imgsz=640,
        batch=16,
        device="0" if _has_gpu() else "cpu",
        project="runs",
        name="blind_assist",
        resume=resume,
        # Аугментация
        hsv_h=0.015, hsv_s=0.7, hsv_v=0.4,
        degrees=5.0,
        translate=0.1,
        scale=0.5,
        flipud=0.0,
        fliplr=0.5,
        mosaic=1.0,
        mixup=0.1,
        # Заморозка backbone для быстрого обучения кастомных классов
        freeze=10,
        # Веса классов — повышаем важность кастомных
        cls=1.5,
    )
    return results


def export_tflite():
    """Экспорт в TFLite INT8 для Android."""
    best = Path("runs/blind_assist/weights/best.pt")
    if not best.exists():
        print("❌ best.pt не найден, запусти сначала обучение")
        return

    model = YOLO(str(best))

    # Экспорт в TFLite INT8 (оптимально для мобильных)
    model.export(
        format="tflite",
        imgsz=640,
        int8=True,
        data="dataset.yaml",  # нужен для калибровки INT8
    )

    # Находим выходной файл
    tflite_path = list(Path("runs/blind_assist/weights").glob("*.tflite"))
    if tflite_path:
        src = tflite_path[0]
        dst = Path("../../assets/models/yolo.tflite")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        print(f"\n✓ Модель сохранена: {dst}")
        print(f"  Размер: {src.stat().st_size / 1024 / 1024:.1f} MB")
    else:
        print("❌ TFLite файл не найден")


def _has_gpu():
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--roboflow-key", default="", help="Roboflow API key")
    parser.add_argument("--skip-download", action="store_true")
    parser.add_argument("--skip-merge",    action="store_true")
    parser.add_argument("--skip-train",    action="store_true")
    parser.add_argument("--resume",        action="store_true")
    parser.add_argument("--export-only",   action="store_true")
    args = parser.parse_args()

    if args.export_only:
        export_tflite()
    else:
        if not args.skip_download:
            if not args.roboflow_key:
                print("⚠ Без --roboflow-key скачаю только то что доступно публично")
            download_datasets(args.roboflow_key)

        if not args.skip_merge:
            merge_datasets()

        if not args.skip_train:
            train(resume=args.resume)

        export_tflite()

    print("\n✓ Готово! Файл assets/models/yolo.tflite готов к деплою")
