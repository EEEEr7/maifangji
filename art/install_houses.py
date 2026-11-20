"""Convert Seedream house layers into house_list_* / house_result_* XICs."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(r"d:\workspace\XTApp AI\maifangji")
ART = ROOT / "art"
SEEDREAM = ART / "seedream"
INK_PY = Path(r"C:\Users\Administrator\.cursor\skills\doubao-seedream-image\scripts\ink.py")
PNG2XIC = Path(r"d:\workspace\XTApp AI\png2xic-kit\png2xic.py")
PROJECT_JSON = ROOT / "xtapp-studio" / "project.json"

LAYERS = {
    1: SEEDREAM / "houses-a-layer_1.png",
    2: SEEDREAM / "houses-a-layer_3.png",
    3: SEEDREAM / "houses-a-layer_5.png",
    4: SEEDREAM / "houses-a-layer_7.png",
    5: SEEDREAM / "houses-a-layer_9.png",
    6: SEEDREAM / "houses-a-layer_11.png",
    7: SEEDREAM / "houses-b-layer_5.png",
    8: SEEDREAM / "houses-b-layer_6.png",
    9: SEEDREAM / "houses-b-layer_11.png",
    10: SEEDREAM / "houses-b-layer_8.png",
}

LIST_SIZE = (253, 212)
RESULT_SIZE = (347, 289)


def crop_alpha(image: Image.Image, pad: int = 2) -> Image.Image:
    image = image.convert("RGBA")
    alpha = image.split()[-1]
    bbox = alpha.getbbox()
    if not bbox:
        return image
    left, top, right, bottom = bbox
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(image.width, right + pad)
    bottom = min(image.height, bottom + pad)
    return image.crop((left, top, right, bottom))


def to_bw(image: Image.Image) -> Image.Image:
    gray = image.convert("L")
    return gray.point(lambda value: 0 if value < 128 else 255, mode="L").convert("RGB")


def letterbox(image: Image.Image, width: int, height: int, margin: int = 8) -> Image.Image:
    canvas = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    image = crop_alpha(image)
    box_w = max(1, width - margin * 2)
    box_h = max(1, height - margin * 2)
    scale = min(box_w / image.width, box_h / image.height)
    size = (max(1, int(round(image.width * scale))), max(1, int(round(image.height * scale))))
    fitted = image.resize(size, Image.Resampling.NEAREST)
    x = (width - fitted.width) // 2
    y = (height - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return to_bw(canvas)


def run(cmd: list[str], env: dict | None = None) -> None:
    print(">", " ".join(str(part) for part in cmd))
    subprocess.check_call(cmd, env=env)


def ink_layers(sources: list[Path]) -> list[Path]:
    ink_dir = SEEDREAM / "houses-ink"
    if ink_dir.exists():
        shutil.rmtree(ink_dir)
    ink_dir.mkdir(parents=True)
    group = "住房|200|" + ",".join(str(path) for path in sources) + "|atkinson"
    env = dict(**{k: v for k, v in __import__("os").environ.items()})
    env.update(
        {
            "INK_WHITE": "205",
            "INK_BLACK": "40",
            "INK_GAMMA": "0.9",
            "INK_DARK": "0.4",
            "INK_FLOOR": "5",
        }
    )
    run([sys.executable, str(INK_PY), str(ink_dir), group], env=env)
    return [ink_dir / f"{path.stem}_200.png" for path in sources]


def upsert_project_asset(data: dict, key: str, width: int, height: int, digest: str, xic_path: str) -> None:
    refs = data.setdefault("project", {}).setdefault("assetRefs", {})
    refs[key] = {
        "key": key,
        "width": width,
        "height": height,
        "bpp": 1,
        "contentHash": digest,
    }
    assets = data.setdefault("assets", [])
    entry = {
        "key": key,
        "width": width,
        "height": height,
        "bpp": 1,
        "contentHash": digest,
        "process": {},
        "xicPath": xic_path,
        "rawPath": None,
        "rawType": "",
        "xicType": "application/x-xic",
    }
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
    named = SEEDREAM / "houses-named"
    if named.exists():
        shutil.rmtree(named)
    named.mkdir(parents=True)
    sources = []
    for index, source in LAYERS.items():
        if not source.is_file():
            raise SystemExit(f"missing layer: {source}")
        dest = named / f"house_{index:02d}.png"
        shutil.copy2(source, dest)
        sources.append(dest)

    inked = ink_layers(sources)
    final_dir = ART / "final"
    final_dir.mkdir(parents=True, exist_ok=True)
    pngs = []
    for index, ink_path in enumerate(inked, start=1):
        if not ink_path.is_file():
            raise SystemExit(f"ink output missing: {ink_path}")
        ink = Image.open(ink_path)
        list_png = final_dir / f"house_list_{index:02d}.png"
        result_png = final_dir / f"house_result_{index:02d}.png"
        letterbox(ink, *LIST_SIZE).save(list_png)
        letterbox(ink, *RESULT_SIZE).save(result_png)
        pngs.extend([list_png, result_png])

    xic_dir = ART / "xic-houses"
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
    for index in range(1, 11):
        list_key = f"house_list_{index:02d}"
        result_key = f"house_result_{index:02d}"
        upsert_project_asset(data, list_key, *LIST_SIZE, hashes[list_key], f"assets/xic/{list_key}.xic")
        upsert_project_asset(data, result_key, *RESULT_SIZE, hashes[result_key], f"assets/xic/{result_key}.xic")
    preload = data.setdefault("project", {}).setdefault("manifest", {}).setdefault("preload_assets", [])
    keys = [f"house_list_{i:02d}" for i in range(1, 11)] + [f"house_result_{i:02d}" for i in range(1, 11)]
    for key in keys:
        if key not in preload:
            preload.append(key)
    PROJECT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    add_preload(ROOT / "manifest.json", keys)
    add_preload(ROOT / "project-files" / "manifest.json", keys)
    shutil.copy2(ROOT / "project-files" / "index.lua", ROOT / "index.lua")
    print("Installed", ", ".join(sorted(hashes)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
