"""Обучение blind_v3 на MPS (Apple GPU)."""
from pathlib import Path
from ultralytics import YOLO
import torch

ROOT = Path("/Users/nexor/StudioProjects/untitled1/project/yolo/blind_v3")
DATA = ROOT / "dataset" / "data.yaml"

print(f"torch={torch.__version__}, mps={torch.backends.mps.is_available()}")
# MPS — после патча tal.py (CPU fallback для assigner)
device = "mps" if torch.backends.mps.is_available() else "cpu"

# Резюм с last.pt если есть
last = ROOT / "runs" / "blind_v3" / "weights" / "last.pt"
start = str(last) if last.exists() else "yolov8n.pt"
print(f"start from: {start}")

model = YOLO(start)

results = model.train(
    data    = str(DATA),
    epochs  = 60,
    imgsz   = 640,
    batch   = 16,
    device  = device,
    patience= 12,
    project = str(ROOT / "runs"),
    name    = "blind_v3",
    save    = True,
    plots   = True,
    augment = True,
    mosaic  = 1.0,
    mixup   = 0.1,
    workers = 6,
    cache   = False,
    exist_ok= True,
    resume  = last.exists(),
)

# Экспорт в ONNX
print("\n=== Экспорт в ONNX (opset=12) ===")
best = ROOT / "runs" / "blind_v3" / "weights" / "best.pt"
m = YOLO(str(best))
onnx_path = m.export(format="onnx", opset=12, simplify=True, dynamic=False)
print(f"ONNX: {onnx_path}")
