"""Скачивает все 4 датасета для blind_v3."""
import os, sys, subprocess, shutil
from pathlib import Path

ROOT = Path("/Users/nexor/StudioProjects/untitled1/project/yolo/blind_v3")
RAW  = ROOT / "raw"
RAW.mkdir(parents=True, exist_ok=True)

API_KEY = "KBbDiwYdvDIx8LTan3ET"

def step(msg): print(f"\n=== {msg} ===", flush=True)

# 1. Accessibility Street через Roboflow
def download_accessibility():
    step("1/4 Accessibility Street (Roboflow)")
    target = RAW / "accessibility"
    if target.exists() and any(target.iterdir()):
        print("уже скачан, пропускаю"); return
    from roboflow import Roboflow
    rf = Roboflow(api_key=API_KEY)
    project = rf.workspace("tfg-7qtpm").project("accesibility-street")
    ds = project.version(11).download("yolov8", location=str(target))
    print(f"скачан в {target}")

# 2. DoorDetect-Class-Dataset с GitHub
def download_doors():
    step("2/4 DoorDetect-Class-Dataset (GitHub)")
    target = RAW / "doors_class"
    if target.exists() and any(target.iterdir()):
        print("уже склонирован, пропускаю"); return
    subprocess.run(["git", "clone", "--depth=1",
        "https://github.com/gasparramoa/DoorDetect-Class-Dataset.git", str(target)],
        check=True)

# 3. Pothole от Roboflow Public
def download_pothole():
    step("3/4 Pothole (Roboflow Public)")
    target = RAW / "pothole"
    if target.exists() and any(target.iterdir()):
        print("уже скачан, пропускаю"); return
    from roboflow import Roboflow
    rf = Roboflow(api_key=API_KEY)
    project = rf.workspace("brad-dwyer").project("pothole-voxrl")
    ds = project.version(1).download("yolov8", location=str(target))
    print(f"скачан в {target}")

# 4. Дополнительный obstacle dataset через Roboflow (вместо Google Drive)
def download_obstacle():
    step("4/4 Obstacle (через Roboflow)")
    target = RAW / "obstacle"
    if target.exists() and any(target.iterdir()):
        print("уже скачан, пропускаю"); return
    from roboflow import Roboflow
    rf = Roboflow(api_key=API_KEY)
    # obstacles in public spaces - тот же датасет что был, для столбов/конусов
    try:
        project = rf.workspace("muftirestumahesa").project("obstacles-in-public-spaces-for-dist-yolo")
        ds = project.version(1).download("yolov8", location=str(target))
        print(f"скачан в {target}")
    except Exception as e:
        print(f"⚠️ не удалось: {e}")
        print("    пропускаю — будем использовать только 3 датасета")

if __name__ == "__main__":
    download_accessibility()
    download_doors()
    download_pothole()
    download_obstacle()
    print("\n✅ все датасеты скачаны")
