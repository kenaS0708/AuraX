"""Объединяет 3 датасета в финальный YOLO формат с 9 классами.

Финальные классы:
  0=crosswalk, 1=stairs, 2=door, 3=pothole,
  4=pole, 5=person, 6=vehicle, 7=traffic_light, 8=obstacle
"""
import json, os, shutil, random
from pathlib import Path
from PIL import Image

ROOT  = Path("/Users/nexor/StudioProjects/untitled1/project/yolo/blind_v3")
RAW   = ROOT / "raw"
OUT   = ROOT / "dataset"
random.seed(42)

# ── 1. финальные классы ───────────────────────────
FINAL_NAMES = [
    'crosswalk', 'stairs', 'door', 'pothole',
    'pole', 'person', 'vehicle', 'traffic_light', 'obstacle',
]

# ── 2. маппинги ──────────────────────────────────

# gobara26: COCO category name → YOLO class id (или None чтобы пропустить)
GOBARA_MAP = {
    'crosswalk': 0,
    'stairs': 1,
    'door': 2,
    'pothole': 3,
    # vehicle
    'Bus': 6, 'bus': 6, 'car': 6, 'Truck': 6, 'truck': 6,
    'motorcycle': 6, 'scooter': 6, 'train': 6, 'bicycle': 6,
    # person
    'Person': 5, 'person': 5,
    # traffic light
    'green_light': 7, 'red_light': 7, 'yellow_light': 7, 'traffic light': 7,
    # obstacle
    'traffic_cone': 8, 'fire_hydrant': 8, 'bench': 8, 'stop_sign': 8,
    # skip
    'cars-bikes-people': None, 'Bushes': None, 'backpack': None, 'boat': None,
    'branch': None, 'chair': None, 'clock': None, 'gun': None, 'handbag': None,
    'rat': None, 'sheep': None, 'suitcase': None, 'tree': None, 'umbrella': None,
    'elevator': None,
}

# TW0521 obstacles: row index → YOLO class id  (берём только pole + некоторые obstacles)
TW_NAMES = ["stop_sign","person","bicycle","bus","truck","car","motorbike",
            "reflective_cone","ashcan","warning_column","spherical_roadblock",
            "pole","dog","tricycle","fire_hydrant"]
TW_MAP = {
    11: 4,  # pole
    9:  4,  # warning_column → pole
    1:  5,  # person
    3:  6,  # bus
    4:  6,  # truck
    5:  6,  # car
    6:  6,  # motorbike
    2:  6,  # bicycle → vehicle
    13: 6,  # tricycle
    7:  8,  # reflective_cone → obstacle
    8:  8,  # ashcan → obstacle
    10: 8,  # spherical_roadblock → obstacle
    14: 8,  # fire_hydrant → obstacle
    0:  None, 12: None,  # stop_sign, dog → skip
}

# pothole-voxrl: 1 класс → 3
POTHOLE_MAP = {0: 3}

# MiguelARD doors: 0=door, 1=handle, 2=cabinet door, 3=refrigerator door
MIGUEL_MAP = {0: 2}  # только door

# ── 3. подготовка ────────────────────────────────
def setup():
    if OUT.exists(): shutil.rmtree(OUT)
    for s in ['train', 'val']:
        (OUT / 'images' / s).mkdir(parents=True)
        (OUT / 'labels' / s).mkdir(parents=True)

def write_label(stem: str, lines: list, split: str):
    if not lines: return
    with open(OUT / 'labels' / split / f'{stem}.txt', 'w') as f:
        f.writelines(lines)

def copy_image(src: Path, stem: str, ext: str, split: str):
    dst = OUT / 'images' / split / f'{stem}.{ext}'
    if not dst.exists():
        shutil.copy(src, dst)

# ── 4. gobara26 (COCO) ──────────────────────────
def process_gobara():
    base = RAW / "gobara26" / "Senior-Design-VIAD-4"
    for src_split, dst_split in [('train', 'train'), ('valid', 'val')]:
        anno = json.load(open(base / src_split / "_annotations.coco.json"))
        # map category id → final class
        cat_to_final = {}
        for c in anno['categories']:
            cat_to_final[c['id']] = GOBARA_MAP.get(c['name'])
        # group annotations by image
        per_img = {}
        for a in anno['annotations']:
            cls = cat_to_final.get(a['category_id'])
            if cls is None: continue
            per_img.setdefault(a['image_id'], []).append((cls, a['bbox']))
        # write each image
        n_imgs = 0; n_anns = 0
        for img_meta in anno['images']:
            iid = img_meta['id']
            if iid not in per_img: continue
            w, h = img_meta['width'], img_meta['height']
            stem = f"gob_{iid:06d}"
            ext  = 'jpg'
            src  = base / src_split / img_meta['file_name']
            if not src.exists(): continue
            # COCO bbox: [x, y, w, h] in pixels  →  YOLO: cx,cy,w,h normalized
            lines = []
            for cls, bb in per_img[iid]:
                cx = (bb[0] + bb[2]/2) / w
                cy = (bb[1] + bb[3]/2) / h
                bw = bb[2] / w
                bh = bb[3] / h
                if bw <= 0 or bh <= 0: continue
                lines.append(f"{cls} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n")
                n_anns += 1
            if not lines: continue
            copy_image(src, stem, ext, dst_split)
            write_label(stem, lines, dst_split)
            n_imgs += 1
        print(f"  gobara/{src_split}: {n_imgs} imgs, {n_anns} anns")

# ── 5. TW0521 obstacles (полигон-формат, нужно конвертировать) ───
def process_tw():
    """В TW0521 уже YOLO формат: cls cx cy w h (нормализованные)."""
    base = RAW / "obstacles_tw"
    for src_split, dst_split in [('train', 'train'), ('val', 'val')]:
        img_dir = base / f"img-{src_split}"
        lbl_dir = base / f"label-{src_split}"
        if not lbl_dir.exists():
            print(f"  ⚠️ нет {lbl_dir}"); continue
        n_imgs = 0; n_anns = 0
        for txt in lbl_dir.glob("*.txt"):
            stem_orig = txt.stem
            # Найти соответствующее изображение
            img_path = None
            for ext in ['.jpg', '.png', '.JPG']:
                p = img_dir / f"{stem_orig}{ext}"
                if p.exists():
                    img_path = p; break
            if img_path is None: continue
            new_lines = []
            with open(txt) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) < 5: continue
                    src_cls = int(parts[0])
                    final_cls = TW_MAP.get(src_cls)
                    if final_cls is None: continue
                    new_lines.append(f"{final_cls} {' '.join(parts[1:5])}\n")
            if not new_lines: continue
            stem = f"tw_{stem_orig}"
            copy_image(img_path, stem, img_path.suffix.lstrip('.').lower(), dst_split)
            write_label(stem, new_lines, dst_split)
            n_imgs += 1
            n_anns += len(new_lines)
        print(f"  tw/{src_split}: {n_imgs} imgs, {n_anns} anns")

# ── 6. pothole-voxrl ────────────────────────────
def process_pothole():
    base = RAW / "pothole"
    for src_split, dst_split in [('train', 'train'), ('valid', 'val')]:
        img_dir = base / src_split / "images"
        lbl_dir = base / src_split / "labels"
        if not lbl_dir.exists(): continue
        n = 0; na = 0
        for txt in lbl_dir.glob("*.txt"):
            stem_orig = txt.stem
            img_path = None
            for ext in ['.jpg','.png','.jpeg','.JPG']:
                p = img_dir / f"{stem_orig}{ext}"
                if p.exists(): img_path = p; break
            if img_path is None: continue
            new_lines = []
            with open(txt) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) < 5: continue
                    src_cls = int(parts[0])
                    fc = POTHOLE_MAP.get(src_cls)
                    if fc is None: continue
                    new_lines.append(f"{fc} {' '.join(parts[1:5])}\n")
            if not new_lines: continue
            stem = f"ph_{stem_orig}"
            copy_image(img_path, stem, img_path.suffix.lstrip('.').lower(), dst_split)
            write_label(stem, new_lines, dst_split)
            n += 1; na += len(new_lines)
        print(f"  pothole/{src_split}: {n} imgs, {na} anns")

# ── 7. MiguelARD doors ─────────────────────────
def process_miguel():
    """1213 imgs, разделяем 90/10."""
    base = RAW / "doors_miguel"
    img_dir = base / "images"
    lbl_dir = base / "labels"
    files = sorted([p for p in img_dir.glob("*.jpg")])
    random.shuffle(files)
    cut = int(len(files) * 0.9)
    splits = [(files[:cut], 'train'), (files[cut:], 'val')]
    for fls, dst_split in splits:
        n = 0; na = 0
        for img_path in fls:
            stem_orig = img_path.stem
            txt = lbl_dir / f"{stem_orig}.txt"
            if not txt.exists(): continue
            new_lines = []
            with open(txt) as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) < 5: continue
                    src_cls = int(parts[0])
                    fc = MIGUEL_MAP.get(src_cls)
                    if fc is None: continue
                    new_lines.append(f"{fc} {' '.join(parts[1:5])}\n")
            if not new_lines: continue
            stem = f"mig_{stem_orig}"
            copy_image(img_path, stem, 'jpg', dst_split)
            write_label(stem, new_lines, dst_split)
            n += 1; na += len(new_lines)
        print(f"  miguel/{dst_split}: {n} imgs, {na} anns")

if __name__ == "__main__":
    print("=== Подготовка датасета blind_v3 ===")
    setup()
    print("\n[1/4] gobara26 (26-class):")
    process_gobara()
    print("\n[2/4] TW0521 obstacles:")
    process_tw()
    print("\n[3/4] pothole-voxrl:")
    process_pothole()
    print("\n[4/4] MiguelARD doors:")
    process_miguel()

    # data.yaml
    yaml_text = f"""path: {OUT}
train: images/train
val: images/val

nc: {len(FINAL_NAMES)}
names: {FINAL_NAMES}
"""
    (OUT / "data.yaml").write_text(yaml_text)

    # summary
    n_train = len(list((OUT / 'images' / 'train').glob('*')))
    n_val = len(list((OUT / 'images' / 'val').glob('*')))
    print(f"\n=== ИТОГО ===")
    print(f"  train: {n_train} imgs")
    print(f"  val:   {n_val} imgs")
    print(f"  data.yaml: {OUT}/data.yaml")
