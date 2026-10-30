#!/usr/bin/env python3
"""把 Resources/Assets 里的角色帧图按「角色整组同一比例」缩到屏幕真正需要的尺寸。

为什么要整组同比例:
    渲染层(PetView.layer)按「自身像素高 ÷ 角色基准像素高 × 显示高度」算尺寸,
    同一角色的所有帧共用一个基准(pixelUnit = <角色>_body.png 的像素高)。
    所以每张单独按自身尺寸归一化会让人物一帧一个大小,必须整组乘同一个 factor。

目标尺寸:
    基准图像素高 = 角色显示高度(pt) × SCALE。SCALE 默认 2.5
    (Retina 2x 再留一点余量),其余帧按同一 factor 等比缩放。

用法:
    python3 tools/shrink_assets.py              # 缩角色帧图
    python3 tools/shrink_assets.py --photos     # 连合照一起缩
    SCALE=3 python3 tools/shrink_assets.py      # 想更清晰就把倍率调大
    ROLE=cat python3 tools/shrink_assets.py     # 只处理某个角色
    DRY=1 python3 tools/shrink_assets.py        # 只报告不改文件

幂等: 已经缩到目标尺寸的角色会直接跳过,重复执行不会越缩越小。
原图在 Resources/frames/,要反悔就重跑 tools/cutout.py --batch。
"""

import os
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "Assets"
PHOTOS = ASSETS / "photos"

# 和 PetRole.displayHeight 保持一致(Sources/HappyPet/PetConfig.swift)
DISPLAY_HEIGHT = {
    "girl": 185.0,
    "boy": 196.0,
    "cat": 104.0,
    "dog": 120.0,
}

SCALE = float(os.environ.get("SCALE", "2.5"))
ONLY_ROLE = os.environ.get("ROLE", "").strip()
DRY = os.environ.get("DRY", "") not in ("", "0", "false")
PHOTO_MAX = int(os.environ.get("PHOTO_MAX", "1600"))
PHOTO_QUALITY = int(os.environ.get("PHOTO_QUALITY", "86"))


def human(size: int) -> str:
    return f"{size / 1024 / 1024:.1f}MB"


def role_files(role: str):
    return sorted(p for p in ASSETS.glob(f"{role}_*.png") if p.is_file())


def reference_file(role: str, files):
    """和 RoleAssets 的取值口径一致: body 优先, 然后 idle 首帧, 最后字典序首帧。"""
    body = ASSETS / f"{role}_body.png"
    if body.exists():
        return body
    idle = ASSETS / f"{role}_idle_1.png"
    if idle.exists():
        return idle
    return files[0] if files else None


def shrink_role(role: str) -> tuple[int, int]:
    files = role_files(role)
    if not files:
        return 0, 0

    ref = reference_file(role, files)
    with Image.open(ref) as img:
        ref_height = img.height

    target = round(DISPLAY_HEIGHT[role] * SCALE)
    if ref_height <= target * 1.02:
        print(f"  {role}: 基准 {ref_height}px 已 ≤ 目标 {target}px,跳过")
        return 0, 0

    factor = target / ref_height
    print(f"  {role}: 基准 {ref.name} {ref_height}px → {target}px (×{factor:.4f}), {len(files)} 张")

    before = after = 0
    for path in files:
        before += path.stat().st_size
        with Image.open(path) as img:
            img = img.convert("RGBA")
            w = max(1, round(img.width * factor))
            h = max(1, round(img.height * factor))
            if DRY:
                print(f"    {path.name}: {img.width}x{img.height} → {w}x{h}")
                after += path.stat().st_size
                continue
            # 先转预乘 alpha 再缩放:抠图后的透明像素底色还在,直缩会把白边糊到轮廓上
            resized = img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
            resized.save(path, "PNG", optimize=True)
        after += path.stat().st_size
    return before, after


def shrink_photos() -> tuple[int, int]:
    if not PHOTOS.is_dir():
        return 0, 0
    files = sorted(p for p in PHOTOS.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    before = after = 0
    touched = 0
    for path in files:
        before += path.stat().st_size
        with Image.open(path) as img:
            longest = max(img.width, img.height)
            if longest <= PHOTO_MAX:
                after += path.stat().st_size
                continue
            factor = PHOTO_MAX / longest
            w = max(1, round(img.width * factor))
            h = max(1, round(img.height * factor))
            touched += 1
            if DRY:
                print(f"    {path.name}: {img.width}x{img.height} → {w}x{h}")
                after += path.stat().st_size
                continue
            resized = img.resize((w, h), Image.LANCZOS)
            if path.suffix.lower() == ".png":
                resized.convert("RGBA").save(path, "PNG", optimize=True)
            else:
                resized.convert("RGB").save(path, "JPEG", quality=PHOTO_QUALITY, optimize=True)
        after += path.stat().st_size
    print(f"  photos: {len(files)} 张,缩了 {touched} 张")
    return before, after


def main() -> int:
    if not ASSETS.is_dir():
        print(f"✗ 找不到素材目录 {ASSETS}")
        return 1

    print(f"素材瘦身 SCALE={SCALE}{' (DRY RUN)' if DRY else ''}")
    roles = [ONLY_ROLE] if ONLY_ROLE else list(DISPLAY_HEIGHT)
    total_before = total_after = 0
    for role in roles:
        if role not in DISPLAY_HEIGHT:
            print(f"  ✗ 未知角色 {role},可选: {' '.join(DISPLAY_HEIGHT)}")
            continue
        b, a = shrink_role(role)
        total_before += b
        total_after += a

    if "--photos" in sys.argv:
        b, a = shrink_photos()
        total_before += b
        total_after += a

    if total_before:
        saved = total_before - total_after
        print(f"✓ {human(total_before)} → {human(total_after)},省了 {human(saved)}")
    else:
        print("✓ 没什么要缩的")
    return 0


if __name__ == "__main__":
    sys.exit(main())