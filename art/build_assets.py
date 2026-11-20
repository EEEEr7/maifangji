"""Ink, compose, and replace 夜市置业 XIC assets at original pixel sizes."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(r"d:\workspace\XTApp AI\maifangji")
ART = ROOT / "art"
INK_PY = Path(r"C:\Users\Administrator\.cursor\skills\doubao-seedream-image\scripts\ink.py")
PNG2XIC = Path(r"d:\workspace\XTApp AI\png2xic-kit\png2xic.py")
SRC = ART / "src"
INK = ART / "ink"
INK_SCENE = ART / "ink-scene"
FINAL = ART / "final"
PROJECT_JSON = ROOT / "xtapp-studio" / "project.json"

GOODS = [
    ART / "goods-layers_1.png",
    ART / "goods-layers_2.png",
    ART / "goods-layers_3.png",
    ART / "goods-layers_4.png",
    ART / "goods-layers_5.png",
    ART / "goods-layers_6.png",
    ART / "goods-layers_7.png",
    ART / "goods-layers_8.png",
]
ACTIONS = [
    ("lantern", ART / "actions-layers_1.png", True),
    ("basket", ART / "actions-layers_2.png", False),
    ("crates", ART / "actions-layers_3.png", False),
    ("bank", ART / "actions-layers_4.png", False),
    ("medkit", ART / "actions-layers_5.png", False),
    ("house", ART / "actions-layers_6.png", False),
    ("key", ART / "actions-layers_7.png", False),
    ("manual", ART / "actions-layers_8.png", False),
    ("flag", ART / "actions-layers_9.png", False),
    ("ledger", ART / "actions-layers_10.png", False),
]


def run(cmd, env=None):
    print(">", " ".join(str(part) for part in cmd))
    subprocess.check_call(cmd, env=env)


def crop_alpha(image: Image.Image, pad: int = 0) -> Image.Image:
    image = image.convert("RGBA")
    alpha = np.asarray(image.split()[-1])
    ys, xs = np.where(alpha > 16)
    if xs.size == 0:
        return image
    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(image.width, right + pad)
    bottom = min(image.height, bottom + pad)
    return image.crop((left, top, right, bottom))


def drop_hanging_pole(image: Image.Image) -> Image.Image:
    image = crop_alpha(image)
    width, height = image.size
    if height <= int(width * 1.25):
        return image
    keep = max(width, int(height * 0.62))
    top = height - keep
    return crop_alpha(image.crop((0, top, width, height)))


def white_to_transparent(image: Image.Image, threshold: int = 246) -> Image.Image:
    image = image.convert("RGBA")
    pixels = np.asarray(image).copy()
    white = (
        (pixels[:, :, 0] >= threshold)
        & (pixels[:, :, 1] >= threshold)
        & (pixels[:, :, 2] >= threshold)
    )
    pixels[white, 3] = 0
    return crop_alpha(Image.fromarray(pixels, "RGBA"), pad=2)


def crop_story(image: Image.Image) -> Image.Image:
    width, height = image.size
    side = min(width, height)
    top = height - side
    return image.crop((0, top, width, height)).convert("RGBA")


def crop_agency_plate(image: Image.Image) -> Image.Image:
    gray = np.asarray(image.convert("L"))
    mask = gray > 170
    ys, xs = np.where(mask)
    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    pad = 8
    left = max(0, left - pad)
    top = max(0, top - pad)
    right = min(image.width, right + pad)
    bottom = min(image.height, bottom + pad)
    return image.crop((left, top, right, bottom)).convert("RGBA")


def fit_icon(icon: Image.Image, box_w: int, box_h: int) -> Image.Image:
    icon = crop_alpha(icon)
    if icon.width == 0 or icon.height == 0:
        return icon
    scale = min(box_w / icon.width, box_h / icon.height)
    size = (
        max(1, int(round(icon.width * scale))),
        max(1, int(round(icon.height * scale))),
    )
    return icon.resize(size, Image.Resampling.NEAREST)


def button(width: int, height: int, icon: Image.Image, reserve_bottom: int = 0) -> Image.Image:
    canvas = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, width - 1, height - 1), outline=(0, 0, 0, 255), width=2)
    area_w = max(8, width - 8)
    area_h = max(8, height - 6 - reserve_bottom)
    fitted = fit_icon(icon, area_w, area_h)
    x = (width - fitted.width) // 2
    y = 3 + max(0, (area_h - fitted.height) // 2)
    canvas.alpha_composite(fitted, (x, y))
    return canvas.convert("RGB")


def letterbox(image: Image.Image, width: int, height: int, fill=(255, 255, 255)) -> Image.Image:
    canvas = Image.new("RGB", (width, height), fill)
    src = image.convert("RGBA")
    scale = min(width / src.width, height / src.height)
    size = (
        max(1, int(round(src.width * scale))),
        max(1, int(round(src.height * scale))),
    )
    fitted = src.resize(size, Image.Resampling.NEAREST)
    x = (width - fitted.width) // 2
    y = (height - fitted.height) // 2
    if fitted.mode == "RGBA":
        canvas.paste(fitted.convert("RGB"), (x, y), fitted)
    else:
        canvas.paste(fitted.convert("RGB"), (x, y))
    return canvas


def cover(image: Image.Image, width: int, height: int) -> Image.Image:
    src = image.convert("RGB")
    scale = max(width / src.width, height / src.height)
    size = (
        max(1, int(round(src.width * scale))),
        max(1, int(round(src.height * scale))),
    )
    fitted = src.resize(size, Image.Resampling.NEAREST)
    x = (fitted.width - width) // 2
    y = (fitted.height - height) // 2
    return fitted.crop((x, y, x + width, y + height))


def flatten_ink(path: Path, width: int, height: int, mode: str = "letterbox") -> Image.Image:
    image = Image.open(path)
    if mode == "cover":
        return cover(image, width, height)
    return letterbox(image, width, height)


def prepare_sources() -> dict[str, Path]:
    if SRC.exists():
        shutil.rmtree(SRC)
    SRC.mkdir(parents=True)
    mapping = {}
    for index, path in enumerate(GOODS, start=1):
        dest = SRC / f"goods-{index:02d}.png"
        crop_alpha(Image.open(path)).save(dest)
        mapping[f"goods-{index:02d}"] = dest
    for name, path, trim_pole in ACTIONS:
        image = Image.open(path)
        image = drop_hanging_pole(image) if trim_pole else crop_alpha(image)
        dest = SRC / f"action-{name}.png"
        image.save(dest)
        mapping[f"action-{name}"] = dest
    hero = white_to_transparent(Image.open(ART / "hero_0.png"))
    dest = SRC / "hero.png"
    hero.save(dest)
    mapping["hero"] = dest
    crop_story(Image.open(ART / "story_0.png")).save(SRC / "story.png")
    Image.open(ART / "splash_0.png").convert("RGBA").save(SRC / "splash.png")
    Image.open(ART / "mainbg_0.png").convert("RGBA").save(SRC / "mainbg.png")
    crop_agency_plate(Image.open(ART / "agency_0.png")).save(SRC / "agency.png")
    mapping["story"] = SRC / "story.png"
    mapping["splash"] = SRC / "splash.png"
    mapping["mainbg"] = SRC / "mainbg.png"
    mapping["agency"] = SRC / "agency.png"
    return mapping


def ink_icons(mapping: dict[str, Path]) -> None:
    if INK.exists():
        shutil.rmtree(INK)
    goods = ",".join(str(mapping[f"goods-{index:02d}"]) for index in range(1, 9))
    actions = ",".join(str(mapping[f"action-{name}"]) for name, _, _ in ACTIONS)
    env = os.environ.copy()
    env.update(
        INK_WHITE="205",
        INK_BLACK="40",
        INK_GAMMA="0.9",
        INK_DARK="0.4",
        INK_FLOOR="5",
    )
    run(
        [
            sys.executable,
            str(INK_PY),
            str(INK),
            f"goods|32|{goods}",
            f"actions|32|{actions}",
            f"hero|96|{mapping['hero']}",
        ],
        env=env,
    )


def ink_scenes(mapping: dict[str, Path]) -> None:
    if INK_SCENE.exists():
        shutil.rmtree(INK_SCENE)
    env = os.environ.copy()
    env.update(
        INK_WHITE="205",
        INK_BLACK="40",
        INK_GAMMA="0.9",
        INK_DARK="0.4",
        INK_FLOOR="20",
    )
    run(
        [
            sys.executable,
            str(INK_PY),
            str(INK_SCENE),
            f"story|480|{mapping['story']}|fs",
            f"splash|400|{mapping['splash']}|fs",
            f"mainbg|480|{mapping['mainbg']}|fs",
            f"agency|427|{mapping['agency']}|fs",
        ],
        env=env,
    )


def find_ink(stem: str, directory: Path) -> Path:
    matches = list(directory.glob(f"{stem}_*.png"))
    matches = [path for path in matches if path.name != "ink_sheet.png"]
    if not matches:
        raise FileNotFoundError(f"missing ink output for {stem} in {directory}")
    return matches[0]


def save_rgb(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(path)


def compose() -> list[Path]:
    if FINAL.exists():
        shutil.rmtree(FINAL)
    FINAL.mkdir(parents=True)
    goods_icons = [find_ink(f"goods-{index:02d}", INK) for index in range(1, 9)]
    action_icons = {name: find_ink(f"action-{name}", INK) for name, _, _ in ACTIONS}
    hero_icon = find_ink("hero", INK)
    story = find_ink("story", INK_SCENE)
    splash = find_ink("splash", INK_SCENE)
    mainbg = find_ink("mainbg", INK_SCENE)
    agency = find_ink("agency", INK_SCENE)

    outputs: dict[str, Image.Image] = {}
    for index, icon_path in enumerate(goods_icons, start=1):
        icon = Image.open(icon_path)
        tile = button(100, 40, icon, reserve_bottom=0)
        suffix = f"{index:02d}"
        outputs[f"goods_m_{suffix}"] = tile
        outputs[f"goods_w_{suffix}"] = tile

    main_map = {
        "main_market1": ("lantern", 133, 60, 24),
        "main_market2": ("basket", 133, 60, 24),
        "main_market3": ("crates", 133, 60, 24),
        "main_help": ("manual", 133, 60, 24),
        "main_start": ("flag", 133, 60, 24),
        "main_records": ("ledger", 133, 60, 24),
        "main_end": ("flag", 133, 60, 24),
        "main_bank": ("bank", 100, 60, 24),
        "main_hospital": ("medkit", 100, 60, 24),
        "main_houses": ("house", 100, 60, 24),
        "main_agency": ("key", 100, 60, 24),
        "story_continue": ("lantern", 100, 51, 22),
        "agency_deal": ("key", 67, 39, 0),
        "agency_leave": ("flag", 67, 39, 0),
        "agency_edit": ("manual", 80, 40, 0),
    }
    for key, (name, width, height, reserve) in main_map.items():
        outputs[key] = button(width, height, Image.open(action_icons[name]), reserve)

    outputs["app_icon_s"] = letterbox(Image.open(hero_icon), 100, 100)
    outputs["app_icon_l"] = letterbox(Image.open(hero_icon), 200, 150)
    outputs["splash"] = flatten_ink(splash, 400, 225, "cover")
    outputs["story_bg"] = flatten_ink(story, 480, 480, "cover")
    outputs["main_bg"] = flatten_ink(mainbg, 480, 395, "cover")
    outputs["agency_bg"] = flatten_ink(agency, 427, 127, "cover")
    outputs["status_1_bg"] = Image.new("RGB", (480, 89), (0, 0, 0))
    outputs["status_2_bg"] = Image.new("RGB", (480, 58), (0, 0, 0))

    pressed_only = {
        "story_continue",
        "agency_deal",
        "agency_leave",
        *[f"goods_m_{index:02d}" for index in range(1, 9)],
        *[f"goods_w_{index:02d}" for index in range(1, 9)],
    }
    pressed_and_disabled = {
        "main_market1",
        "main_market2",
        "main_market3",
        "main_help",
        "main_start",
        "main_records",
        "main_end",
        "main_bank",
        "main_hospital",
        "main_houses",
        "main_agency",
    }
    variants = []
    for key, image in outputs.items():
        path = FINAL / f"{key}.png"
        save_rgb(image, path)
        variants.append(path)
        extra = []
        if key in pressed_only:
            extra = ["_p"]
        elif key in pressed_and_disabled:
            extra = ["_p", "_d"]
        for suffix in extra:
            target = FINAL / f"{key}{suffix}.png"
            save_rgb(image, target)
            variants.append(target)
    return variants


def convert_xic(pngs: list[Path]) -> Path:
    xic_dir = ART / "xic"
    if xic_dir.exists():
        shutil.rmtree(xic_dir)
    xic_dir.mkdir(parents=True)
    batch = []
    for path in pngs:
        batch.append(str(path))
        if len(batch) >= 12:
            run([sys.executable, str(PNG2XIC), "--out-dir", str(xic_dir), *batch])
            batch = []
    if batch:
        run([sys.executable, str(PNG2XIC), "--out-dir", str(xic_dir), *batch])
    return xic_dir


def install_xic(xic_dir: Path) -> dict[str, str]:
    hashes = {}
    destinations = [ROOT / "assets", ROOT / "assets" / "xic"]
    for source in sorted(xic_dir.glob("*.xic")):
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        hashes[source.stem] = digest
        for dest_dir in destinations:
            dest_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest_dir / source.name)
    return hashes


def update_hashes(hashes: dict[str, str]) -> None:
    data = json.loads(PROJECT_JSON.read_text(encoding="utf-8"))
    refs = data.get("project", {}).get("assetRefs", {})
    for key, digest in hashes.items():
        if key in refs:
            refs[key]["contentHash"] = digest
    for item in data.get("assets", []):
        key = item.get("key")
        if key in hashes:
            item["contentHash"] = hashes[key]
    PROJECT_JSON.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sync_lua() -> None:
    shutil.copy2(ROOT / "project-files" / "index.lua", ROOT / "index.lua")
    shutil.copy2(ROOT / "project-files" / "manifest.json", ROOT / "manifest.json")


def main() -> int:
    mapping = prepare_sources()
    ink_icons(mapping)
    ink_scenes(mapping)
    pngs = compose()
    xic_dir = convert_xic(pngs)
    hashes = install_xic(xic_dir)
    update_hashes(hashes)
    sync_lua()
    print(f"Wrote {len(pngs)} PNG, {len(hashes)} XIC")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
