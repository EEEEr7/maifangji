"""Crop the two goods sheets and install 112px and 32px 1bpp icons.

Light fills stay white. Dark structure and edges stay black. Only the
112px pictures dither a narrow mid band, so a list thumbnail does not
turn into gray noise.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"d:\workspace\XTApp AI\maifangji")
ART = ROOT / "art"
SEEDREAM = ART / "seedream"
PNG2XIC = Path(r"d:\workspace\XTApp AI\png2xic-kit\png2xic.py")
PROJECT_JSON = ROOT / "xtapp-studio" / "project.json"
LAYERS = SEEDREAM / "goods-real-layers"
HERO = 112
THUMB = 32

SHEETS = [
    (SEEDREAM / "goods-real-a_0.png", 1),
    (SEEDREAM / "goods-real-b_0.png", 5),
]


def run(cmd: list[str], env: dict | None = None) -> None:
    print(">", " ".join(str(part) for part in cmd))
    subprocess.check_call(cmd, env=env)


def isolate(tile: Image.Image) -> Image.Image:
    image = tile.convert("RGBA")
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            red, green, blue, _alpha = pixels[x, y]
            if red > 242 and green > 242 and blue > 242:
                pixels[x, y] = (255, 255, 255, 0)
    bbox = image.split()[-1].getbbox()
    if not bbox:
        raise SystemExit("empty goods tile")
    left, top, right, bottom = bbox
    pad = 8
    return image.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(width, right + pad),
        min(height, bottom + pad),
    ))


def crop_sheets() -> list[Path]:
    if LAYERS.exists():
        shutil.rmtree(LAYERS)
    LAYERS.mkdir(parents=True)
    paths = []
    for sheet_path, first_id in SHEETS:
        sheet = Image.open(sheet_path)
        half_w, half_h = sheet.width // 2, sheet.height // 2
        boxes = [
            (0, 0, half_w, half_h),
            (half_w, 0, sheet.width, half_h),
            (0, half_h, half_w, sheet.height),
            (half_w, half_h, sheet.width, sheet.height),
        ]
        for offset, box in enumerate(boxes):
            goods_id = first_id + offset
            dest = LAYERS / f"goods_{goods_id:02d}.png"
            isolate(sheet.crop(box)).save(dest)
            paths.append(dest)
    return paths


def fit_on_white(image: Image.Image, size: int, margin: int) -> Image.Image:
    canvas = Image.new("RGB", (size, size), (255, 255, 255))
    image = image.convert("RGBA")
    bbox = image.split()[-1].point(lambda value: 255 if value > 16 else 0).getbbox()
    if not bbox:
        raise SystemExit("empty goods tile")
    image = image.crop(bbox)
    box = size - margin * 2
    scale = min(box / image.width, box / image.height)
    fitted = image.resize(
        (max(1, int(round(image.width * scale))), max(1, int(round(image.height * scale)))),
        Image.Resampling.LANCZOS,
    )
    flat = Image.new("RGB", fitted.size, (255, 255, 255))
    flat.paste(fitted, mask=fitted.split()[-1])
    canvas.paste(flat, ((size - flat.width) // 2, (size - flat.height) // 2))
    return canvas.convert("L")


def band_ink(gray: Image.Image, black: float = 85, white: float = 188) -> Image.Image:
    arr = np.asarray(gray, dtype=np.float64)
    result = np.full(arr.shape, 255, dtype=np.uint8)
    result[arr < black] = 0
    mid = (arr >= black) & (arr < white)
    work = np.clip((arr - black) / max(1.0, white - black), 0, 1) * 255
    height, width = arr.shape
    levels = work.copy()
    for y in range(height):
        for x in range(width):
            if not mid[y, x]:
                continue
            old = levels[y, x]
            new = 0.0 if old < 128 else 255.0
            result[y, x] = 0 if new == 0 else 255
            error = old - new
            for dx, dy, weight in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height and mid[ny, nx]:
                    levels[ny, nx] += error * weight
    return Image.fromarray(result, mode="L").convert("RGB")


def thumb_ink(gray: Image.Image) -> Image.Image:
    arr = np.asarray(gray, dtype=np.float64)
    horizontal = np.zeros_like(arr)
    vertical = np.zeros_like(arr)
    horizontal[:, 1:] = np.abs(arr[:, 1:] - arr[:, :-1])
    vertical[1:, :] = np.abs(arr[1:, :] - arr[:-1, :])
    darker = np.zeros_like(arr, dtype=bool)
    darker[:, 1:] |= (horizontal[:, 1:] > 28) & (arr[:, 1:] <= arr[:, :-1])
    darker[:, :-1] |= (horizontal[:, 1:] > 28) & (arr[:, :-1] < arr[:, 1:])
    darker[1:, :] |= (vertical[1:, :] > 28) & (arr[1:, :] <= arr[:-1, :])
    darker[:-1, :] |= (vertical[1:, :] > 28) & (arr[:-1, :] < arr[1:, :])
    result = np.where((arr < 128) | darker, 0, 255).astype(np.uint8)
    return Image.fromarray(result, mode="L").convert("RGB")


def upsert_project_asset(data: dict, key: str, size: int, digest: str) -> None:
    refs = data.setdefault("project", {}).setdefault("assetRefs", {})
    refs[key] = {
        "key": key,
        "width": size,
        "height": size,
        "bpp": 1,
        "contentHash": digest,
    }
    entry = {
        "key": key,
        "width": size,
        "height": size,
        "bpp": 1,
        "contentHash": digest,
        "process": {"source": "seedream goods-real", "ink": "outline"},
        "xicPath": f"assets/xic/{key}.xic",
        "rawPath": None,
        "rawType": "",
        "xicType": "application/x-xic",
    }
    assets = data.setdefault("assets", [])
    for index, item in enumerate(assets):
        if item.get("key") == key:
            assets[index] = entry
            return
    assets.append(entry)


def add_preload(manifest_path: Path, keys: list[str]) -> None:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    preload = data.setdefault("preload_assets", [])
    for key in keys:
        if key not in preload:
            preload.append(key)
    manifest_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    sources = crop_sheets()
    final_dir = ART / "final"
    final_dir.mkdir(parents=True, exist_ok=True)
    pngs = []
    sizes = {}
    for path in sources:
        goods_id = int(path.stem.split("_")[1])
        color = Image.open(path)
        for size, prefix, paint, margin in (
            (HERO, "goods_icon_", band_ink, 3),
            (THUMB, "goods_thumb_", thumb_ink, 1),
        ):
            key = f"{prefix}{goods_id:02d}"
            out = final_dir / f"{key}.png"
            paint(fit_on_white(color, size, margin)).save(out)
            pngs.append(out)
            sizes[key] = size

    xic_dir = ART / "xic-goods-real"
    if xic_dir.exists():
        shutil.rmtree(xic_dir)
    xic_dir.mkdir(parents=True)
    run([sys.executable, str(PNG2XIC), "--mode", "bw", "--out-dir", str(xic_dir), *[str(path) for path in pngs]])

    hashes = {}
    destinations = [ROOT / "assets", ROOT / "assets" / "xic", ART / "xic"]
    for source in sorted(xic_dir.glob("*.xic")):
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        hashes[source.stem] = digest
        for dest_dir in destinations:
            dest_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest_dir / source.name)

    data = json.loads(PROJECT_JSON.read_text(encoding="utf-8"))
    keys = []
    for key, digest in hashes.items():
        upsert_project_asset(data, key, sizes[key], digest)
        keys.append(key)
    preload = data.setdefault("project", {}).setdefault("manifest", {}).setdefault("preload_assets", [])
    for key in keys:
        if key not in preload:
            preload.append(key)
    PROJECT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    add_preload(ROOT / "manifest.json", keys)
    add_preload(ROOT / "project-files" / "manifest.json", keys)
    print("Installed", ", ".join(sorted(hashes)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
