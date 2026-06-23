"""
Дообучение YOLOv8n для детекции дверей.
Датасет: https://www.kaggle.com/datasets/ma7eg250/doors-dataset

Требования:
  pip install ultralytics kaggle pyyaml

Настройка Kaggle API (один раз):
  1. kaggle.com → Account → Create API Token → скачать kaggle.json
  2. cp kaggle.json ~/.kaggle/kaggle.json  (Linux/Mac)
     %USERPROFILE%\\.kaggle\\kaggle.json  (Windows)
  3. chmod 600 ~/.kaggle/kaggle.json

Запуск:
  python train_doors.py

Результат:
  runs/doors/weights/best.pt
  → конвертируется в ../../assets/models/door.tflite

Выходные классы модели (внутренние):
  0 = door_open    (открыта / полуоткрыта)
  1 = door_closed  (закрыта)

Flutter classId:
  14 = door_open
  15 = door_closed
"""

import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import yaml

# ── Маппинг имён классов Kaggle → наши внутренние ID ─────────
# 0 = open (открыта / полуоткрыта), 1 = closed (закрыта)
DOOR_CLASS_MAP: dict[str, int] = {
    'open':           0,
    'door_open':      0,
    'opened':         0,
    'semi':           0,   # полуоткрытая → открытая (проход возможен)
    'semi_open':      0,
    'partially_open': 0,
    'ajar':           0,
    'closed':         1,
    'door_closed':    1,
    'shut':           1,
    'semi_closed':    1,
    'partially_closed': 1,
}

OUT_DIR    = Path('datasets/doors')
RAW_DIR    = Path('datasets/doors_raw')
RUNS_DIR   = Path('runs/doors/weights')
ASSET_DST  = Path('../../assets/models/door.tflite')


# ─────────────────────────────────────────────────────────────
# 1. Скачивание
# ─────────────────────────────────────────────────────────────

def download():
    if RAW_DIR.exists() and any(RAW_DIR.iterdir()):
        print(f'[skip] {RAW_DIR} уже существует')
        return

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    print('⬇  Скачиваем doors-dataset с Kaggle...')
    try:
        subprocess.run(
            ['kaggle', 'datasets', 'download',
             '-d', 'ma7eg250/doors-dataset',
             '-p', str(RAW_DIR), '--unzip'],
            check=True,
        )
    except FileNotFoundError:
        print('❌  kaggle CLI не найден. Установи: pip install kaggle')
        print('   Затем настрой ~/.kaggle/kaggle.json')
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f'❌  Ошибка скачивания: {e}')
        print('   Проверь ~/.kaggle/kaggle.json и права (chmod 600)')
        sys.exit(1)
    print(f'✓  Скачано в {RAW_DIR}')


# ─────────────────────────────────────────────────────────────
# 2. Подготовка датасета
# ─────────────────────────────────────────────────────────────

def _find_yaml(root: Path) -> Path | None:
    for p in root.rglob('data.yaml'):
        return p
    return None


def _build_class_map(names: list[str]) -> dict[int, int]:
    cls_map: dict[int, int] = {}
    for orig_id, orig_name in enumerate(names):
        key = orig_name.lower().replace(' ', '_').replace('-', '_')
        # точное совпадение
        if key in DOOR_CLASS_MAP:
            cls_map[orig_id] = DOOR_CLASS_MAP[key]
            continue
        # частичное совпадение
        for pattern, our_id in DOOR_CLASS_MAP.items():
            if pattern in key:
                cls_map[orig_id] = our_id
                break
    return cls_map


def prepare():
    if OUT_DIR.exists() and any(OUT_DIR.iterdir()):
        print(f'[skip] {OUT_DIR} уже существует')
        return

    yaml_path = _find_yaml(RAW_DIR)
    if yaml_path is None:
        # Попробуем найти любой yaml внутри zip-файлов
        for zf in RAW_DIR.glob('*.zip'):
            with zipfile.ZipFile(zf) as z:
                z.extractall(RAW_DIR)
        yaml_path = _find_yaml(RAW_DIR)

    if yaml_path is None:
        raise FileNotFoundError(f'data.yaml не найден в {RAW_DIR}')

    print(f'Найден: {yaml_path}')
    with open(yaml_path) as f:
        meta = yaml.safe_load(f)

    names = meta.get('names', [])
    if isinstance(names, dict):
        names = [names[i] for i in sorted(names)]
    print(f'Классы датасета: {names}')

    cls_map = _build_class_map(names)
    if not cls_map:
        raise ValueError(
            f'Ни один класс не распознан.\n'
            f'Классы датасета: {names}\n'
            f'Поддерживаемые паттерны: {list(DOOR_CLASS_MAP)}'
        )
    for orig_id, our_id in cls_map.items():
        label = 'door_open' if our_id == 0 else 'door_closed'
        print(f'  {orig_id} ({names[orig_id]}) → {our_id} ({label})')

    ds_root = yaml_path.parent
    total = 0

    for split in ['train', 'valid', 'val', 'test']:
        # Поддерживаем разные структуры папок
        for img_dir in [
            ds_root / split / 'images',
            ds_root / split,
            ds_root / 'images' / split,
        ]:
            if img_dir.exists():
                break
        else:
            continue

        lbl_dir = img_dir.parent / 'labels' if img_dir.name == 'images' \
            else img_dir.parent.parent / 'labels' / split

        out_split = 'valid' if split in ('val', 'test') else split
        img_dst = OUT_DIR / out_split / 'images'
        lbl_dst = OUT_DIR / out_split / 'labels'
        img_dst.mkdir(parents=True, exist_ok=True)
        lbl_dst.mkdir(parents=True, exist_ok=True)

        for img in img_dir.glob('*.[jJpPwWbB][pPnNeMmPp][gGgGeEdD4]*'):
            stem = img.stem
            lbl = lbl_dir / f'{stem}.txt'
            if not lbl.exists():
                # Попробуем рядом с картинкой
                lbl = img.with_suffix('.txt')
            if not lbl.exists():
                continue

            new_lines = []
            for line in lbl.read_text().splitlines():
                parts = line.strip().split()
                if len(parts) < 5:
                    continue
                orig_id = int(parts[0])
                if orig_id not in cls_map:
                    continue
                new_lines.append(f'{cls_map[orig_id]} ' + ' '.join(parts[1:]))

            if not new_lines:
                continue

            shutil.copy2(img, img_dst / img.name)
            (lbl_dst / f'{stem}.txt').write_text('\n'.join(new_lines))
            total += 1

    if total == 0:
        raise RuntimeError('0 изображений скопировано — проверь структуру датасета')

    # Финальный data.yaml
    with open(OUT_DIR / 'data.yaml', 'w') as f:
        yaml.dump({
            'path': str(OUT_DIR.resolve()),
            'train': 'train/images',
            'val':   'valid/images',
            'nc':    2,
            'names': ['door_open', 'door_closed'],
        }, f, allow_unicode=True)

    print(f'✓  Подготовлено {total} изображений → {OUT_DIR}')


# ─────────────────────────────────────────────────────────────
# 3. Обучение
# ─────────────────────────────────────────────────────────────

def train():
    from ultralytics import YOLO
    import torch

    device = '0' if torch.cuda.is_available() else 'cpu'
    print(f'\n🚀 Обучаем на устройстве: {device}')
    if device == 'cpu':
        print('   ⚠  CPU — обучение займёт несколько часов')
        print('   💡 Используй Kaggle Notebooks (бесплатный GPU)')

    model = YOLO('yolov8n.pt')  # nano — ~6MB в TFLite, ~5ms на Android

    model.train(
        data=str(OUT_DIR / 'data.yaml'),
        epochs=150,
        imgsz=640,
        batch=16 if device != 'cpu' else 4,
        device=device,
        project='runs',
        name='doors',
        exist_ok=True,
        # Аугментация — важна для тёмных помещений и разных углов
        hsv_h=0.02,
        hsv_s=0.5,
        hsv_v=0.6,      # яркость важна — очки снимают в плохом свете
        degrees=8.0,    # небольшой наклон (человек не всегда ровно стоит)
        translate=0.1,
        scale=0.5,
        fliplr=0.4,     # зеркало — двери бывают слева и справа
        flipud=0.0,     # дверь не бывает вверх тормашками
        mosaic=0.7,
        copy_paste=0.1,
        # Заморозка backbone — быстрее адаптируется к дверям
        freeze=9,
        # Повышаем вес классификации: важно различать open vs closed
        cls=2.0,
        # Patience для ранней остановки
        patience=30,
    )


# ─────────────────────────────────────────────────────────────
# 4. Экспорт в TFLite
# ─────────────────────────────────────────────────────────────

def export():
    from ultralytics import YOLO

    best = RUNS_DIR / 'best.pt'
    if not best.exists():
        print(f'❌  best.pt не найден в {RUNS_DIR}')
        return False

    model = YOLO(str(best))

    # float32 — надёжнее на Android (int8 требует калибровки и может давать баги)
    model.export(
        format='tflite',
        imgsz=640,
        int8=False,
    )

    tflite_files = list(RUNS_DIR.glob('*.tflite'))
    if not tflite_files:
        # ultralytics кладёт в подпапку
        tflite_files = list((RUNS_DIR / 'best_saved_model').glob('*.tflite'))

    if not tflite_files:
        print('❌  TFLite файл не найден')
        return False

    # Берём float32, не int8
    src = next((f for f in tflite_files if 'int8' not in f.name), tflite_files[0])
    ASSET_DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, ASSET_DST)

    mb = src.stat().st_size / 1024 / 1024
    print(f'\n✅ Модель сохранена: {ASSET_DST}')
    print(f'   Размер: {mb:.1f} MB')
    print(f'\nДальнейшие шаги:')
    print(f'  1. Добавь в pubspec.yaml:  - assets/models/door.tflite')
    print(f'  2. flutter pub get')
    print(f'  3. flutter build apk --debug')
    return True


# ─────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--skip-download', action='store_true')
    p.add_argument('--skip-prepare',  action='store_true')
    p.add_argument('--skip-train',    action='store_true')
    p.add_argument('--export-only',   action='store_true')
    args = p.parse_args()

    if args.export_only:
        export()
    else:
        if not args.skip_download:
            download()
        if not args.skip_prepare:
            prepare()
        if not args.skip_train:
            train()
        export()

    print('\n✓ Готово!')
