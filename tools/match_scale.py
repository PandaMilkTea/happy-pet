#!/usr/bin/env python3
"""把新增动作帧的「人物像素尺度」对齐到同角色已有帧,作为 cutout.py 的前置步骤。

为什么需要:
    cutout.py 的「整组统一缩放」对一个角色只算一个系数(取各帧身高中位数做基准),
    因为按每帧自己的身高缩放会把蜷缩/跳起的帧放大。
    但如果新帧的出图分辨率和老帧不一样(例如 2368x1776 vs 1792x1344),
    新帧里人物的像素身高就会整体偏大,中位数基准救不回来 —— 切帧时人物会突然变大。
    这里先把新帧等比缩到「人物身高和老帧一致」,再交给 cutout.py 统一归一。

用法:
    python3 tools/match_scale.py <角色> <新动作> [新动作 ...]
    python3 tools/match_scale.py girl eat purr

说明:
    - 直接覆盖写回 Resources/frames/<角色>_<动作>_<序号>.png;
    - 身高用「非背景像素的行投影」粗估(抹掉右下角水印区),够精确到百分之几,
      剩下的误差 cutout.py 会再按参考立绘归一掉。
"""

import glob
import os
import sys

import numpy as np
from PIL import Image

SRC_DIR = "Resources/frames"
WM_W, WM_H = 0.2, 0.06      # 右下角水印区占比,和 cutout.py 默认一致
TOL = 24                    # 背景容差
ROW_RATIO = 0.005           # 一行里非背景像素超过这个比例才算「有人」


def person_height(path: str) -> int:
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    h, w = rgb.shape[:2]
    bg = np.median(np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]), axis=0)
    mask = np.abs(rgb - bg).max(axis=2) > TOL
    mask[int(h * (1 - WM_H)):, int(w * (1 - WM_W)):] = False   # 抹掉水印区
    rows = np.flatnonzero(mask.sum(axis=1) > w * ROW_RATIO)
    return int(rows[-1] - rows[0] + 1) if rows.size else 0


def heights(paths):
    return {p: person_height(p) for p in paths}


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    role, actions = sys.argv[1], set(sys.argv[2:])

    new_paths, base_paths = [], []
    for path in sorted(glob.glob(os.path.join(SRC_DIR, f"{role}_*.png"))):
        stem = os.path.basename(path)[len(role) + 1:-4]
        action = "_".join(stem.split("_")[:-1])
        (new_paths if action in actions else base_paths).append(path)
    if not new_paths or not base_paths:
        raise SystemExit(f"❌ {role}: 新帧 {len(new_paths)} 张,基准帧 {len(base_paths)} 张,无法对齐")

    base = float(np.median(list(heights(base_paths).values())))
    new = heights(new_paths)
    ratio = float(np.median(list(new.values())))
    k = base / max(ratio, 1.0)
    print(f"📐 {role}: 基准身高 {base:.0f}(老帧 {len(base_paths)} 张) "
          f"新帧身高 {ratio:.0f} → 缩放 {k:.4f}×")
    if abs(k - 1) < 0.02:
        print("   已经一致,跳过")
        return

    for path, hgt in new.items():
        img = Image.open(path).convert("RGB")
        size = (max(1, round(img.width * k)), max(1, round(img.height * k)))
        img.resize(size, Image.LANCZOS).save(path)
        print(f"   ✅ {os.path.basename(path)} 身高 {hgt} → {round(hgt * k)}  画布 {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()