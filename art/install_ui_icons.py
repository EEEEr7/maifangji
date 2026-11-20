"""Install overlay goods icons and the new-game cash icon."""
from __future__ import annotations

import hashlib
import json
import os
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

GOODS = {index: SEEDREAM / f"goods-icons-layer_{index}.png" for index in range(1, 9)}
CASH = SEEDREAM / "cash-icon-layer_1.png"
GOODS_SIZE = (56, 56)
CASH_SIZE = (48, 48)


def crop_alpha(image: Image.Image, pad: int = 2) -> Image.Image:
    image = image.convert("RGBA")
    bbox = image.split()[-1].getbbox()
    if not bbox:
        return image
    left, top, right, bottom = bbox
    return image.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(image.width, right + pad),
        min(image.height, bottom + pad),
    ))


def to_bw(image: Image.Image) -> Image.Image:
    gray = image.convert("L")
    return gray.point(lambda value: 0 if value < 128 else 255, mode="L").convert("RGB")


def letterbox(image: Image.Image, width: int, height: int, margin: int = 4) -> Image.Image:
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


def ink_layers(sources: list[Path], size: int) -> list[Path]:
    ink_dir = SEEDREAM / "ui-icons-ink"
    ink_dir.mkdir(parents=True, exist_ok=True)
    group = f"图标|{size}|" + ",".join(str(path) for path in sources) + "|atkinson"
    env = dict(os.environ)
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
    return [ink_dir / f"{path.stem}_{size}.png" for path in sources]


def upsert_project_asset(data: dict, key: str, width: int, height: int, digest: str) -> None:
    refs = data.setdefault("project", {}).setdefault("assetRefs", {})
    refs[key] = {
        "key": key,
        "width": width,
        "height": height,
        "bpp": 1,
        "contentHash": digest,
    }
    entry = {
        "key": key,
        "width": width,
        "height": height,
        "bpp": 1,
        "contentHash": digest,
        "process": {},
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
    named = SEEDREAM / "ui-icons-named"
    if named.exists():
        shutil.rmtree(named)
    named.mkdir(parents=True)
    sources = []
    for index, source in GOODS.items():
        if not source.is_file():
            raise SystemExit(f"missing goods layer: {source}")
        dest = named / f"goods_icon_{index:02d}.png"
        shutil.copy2(source, dest)
        sources.append(dest)
    if not CASH.is_file():
        raise SystemExit(f"missing cash layer: {CASH}")
    cash_named = named / "cash_icon.png"
    shutil.copy2(CASH, cash_named)
    sources.append(cash_named)

    inked = ink_layers(sources, 56)
    final_dir = ART / "final"
    final_dir.mkdir(parents=True, exist_ok=True)
    pngs = []
    sizes = {}
    for path in inked:
        if not path.is_file():
            raise SystemExit(f"ink output missing: {path}")
        ink = Image.open(path)
        if path.stem.startswith("cash_icon"):
            out = final_dir / "cash_icon.png"
            letterbox(ink, *CASH_SIZE).save(out)
            sizes["cash_icon"] = CASH_SIZE
        else:
            key = path.stem.replace("_56", "")
            out = final_dir / f"{key}.png"
            letterbox(ink, *GOODS_SIZE).save(out)
            sizes[key] = GOODS_SIZE
        pngs.append(out)

    xic_dir = ART / "xic-ui-icons"
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
        width, height = sizes[key]
        upsert_project_asset(data, key, width, height, digest)
        keys.append(key)
    preload = data.setdefault("project", {}).setdefault("manifest", {}).setdefault("preload_assets", [])
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
