#!/usr/bin/env python3
"""把 AI 生成的实心背景立绘抠成透明 PNG,并按内容自动裁切。

用法:
    python3 tools/cutout.py 输入1.png 输出1.png [输入2.png 输出2.png ...]
    TOL=38 python3 tools/cutout.py ...          # 调整背景容差

要点:
1. 以四边像素中位色作为背景参考色,阈值出「候选背景」;
2. 只保留与图像边界连通的候选区域,避免误删人物内部的同色区块
   (例如白背景 + 白裙子);
3. 边缘做羽化,并用 C = (I - (1-a)*bg) / a 去掉半透明边上的背景色溢出,
   消除俗称的「白边」;
4. 多张同尺寸的图共用同一个并集裁切框,保证睁眼/闭眼帧切换时人物不位移。
"""

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

TOL = float(os.environ.get("TOL", "38"))
# 面积小于「最大前景块 * 该比例」的碎片会被丢弃
FRAGMENT_RATIO = 0.01
PAD_RATIO = 0.05


def estimate_bg_color(rgb: np.ndarray) -> np.ndarray:
    """四条边界像素的中位色"""
    edges = np.concatenate([
        rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]
    ], axis=0)
    return np.median(edges, axis=0)


def build_foreground_mask(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """返回 True = 前景(人物)"""
    dist = np.abs(rgb.astype(np.float32) - bg).mean(axis=2)
    candidate = dist <= TOL

    # 只有和画面边界连通的候选区域才算背景
    labels, count = ndimage.label(candidate)
    if count == 0:
        return np.ones(rgb.shape[:2], dtype=bool)
    border = np.concatenate([
        labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]
    ])
    border_ids = np.unique(border)
    border_ids = border_ids[border_ids != 0]
    bg_mask = np.isin(labels, border_ids)

    fg = ~bg_mask

    # 丢掉背景里零碎的噪点块
    fg_labels, fg_count = ndimage.label(fg)
    if fg_count > 1:
        sizes = ndimage.sum(fg, fg_labels, range(1, fg_count + 1))
        keep = np.where(sizes >= sizes.max() * FRAGMENT_RATIO)[0] + 1
        fg = np.isin(fg_labels, keep)
        dropped = fg_count - len(keep)
        if dropped:
            print(f"  丢弃 {dropped} 个零碎块")

    return fg


def make_rgba(rgb: np.ndarray, fg: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """羽化边缘 + 去背景色溢出,返回 uint8 的 RGBA"""
    a = ndimage.gaussian_filter(fg.astype(np.float32), sigma=0.8)
    # 稍微收紧,让边缘干净一点
    a = np.clip((a - 0.12) / 0.76, 0.0, 1.0)

    rgb_f = rgb.astype(np.float32)
    # 半透明区域里把混进来的背景色反解掉
    partial = (a > 0.02) & (a < 0.98)
    if partial.any():
        a3 = a[..., None]
        unmixed = (rgb_f - (1.0 - a3) * bg) / np.maximum(a3, 0.02)
        rgb_f = np.where(partial[..., None], np.clip(unmixed, 0, 255), rgb_f)

    rgba = np.zeros(rgb.shape[:2] + (4,), dtype=np.uint8)
    rgba[..., :3] = rgb_f.round().astype(np.uint8)
    rgba[..., 3] = (a * 255).round().astype(np.uint8)
    # 全透明处把颜色也清零,避免某些缩放算法把背景色渗回边缘
    rgba[a <= 0.0, :3] = 0
    return rgba


def bbox_of(rgba: np.ndarray):
    solid = rgba[..., 3] > 8
    rows = np.where(solid.any(axis=1))[0]
    cols = np.where(solid.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return int(rows[0]), int(rows[-1]), int(cols[0]), int(cols[-1])


def main() -> int:
    args = sys.argv[1:]
    if len(args) < 2 or len(args) % 2 != 0:
        print(__doc__)
        return 1

    pairs = [(args[i], args[i + 1]) for i in range(0, len(args), 2)]
    frames = []

    for src, dst in pairs:
        print(f"🧽 处理 {src}")
        img = Image.open(src).convert("RGB")
        rgb = np.asarray(img)
        bg = estimate_bg_color(rgb)
        print(f"  背景参考色 RGB({bg[0]:.0f}, {bg[1]:.0f}, {bg[2]:.0f})")

        fg = build_foreground_mask(rgb, bg)
        ratio = 100.0 * (1.0 - fg.mean())
        print(f"  去除背景像素 {ratio:.1f}%")
        if fg.mean() < 0.02:
            print("  ⚠️ 前景几乎没剩,TOL 太大")
            return 1
        if fg.mean() > 0.98:
            print("  ⚠️ 几乎没抠掉东西,TOL 太小")
            return 1

        rgba = make_rgba(rgb, fg, bg)
        box = bbox_of(rgba)
        if box is None:
            print("  ⚠️ 没有可见内容")
            return 1
        frames.append({"dst": dst, "rgba": rgba, "box": box})

    # 同尺寸的帧共用并集裁切框,避免切帧时人物跳动
    shapes = {f["rgba"].shape[:2] for f in frames}
    if len(frames) > 1 and len(shapes) == 1:
        top = min(f["box"][0] for f in frames)
        bottom = max(f["box"][1] for f in frames)
        left = min(f["box"][2] for f in frames)
        right = max(f["box"][3] for f in frames)
        for f in frames:
            f["box"] = (top, bottom, left, right)
        print(f"🔗 {len(frames)} 帧共用裁切框 {right - left + 1}x{bottom - top + 1}")

    for f in frames:
        top, bottom, left, right = f["box"]
        cropped = f["rgba"][top:bottom + 1, left:right + 1]
        h, w = cropped.shape[:2]
        pad = int(round(max(w, h) * PAD_RATIO))
        canvas = np.zeros((h + pad * 2, w + pad * 2, 4), dtype=np.uint8)
        canvas[pad:pad + h, pad:pad + w] = cropped

        out = Image.fromarray(canvas, mode="RGBA")
        os.makedirs(os.path.dirname(os.path.abspath(f["dst"])), exist_ok=True)
        out.save(f["dst"], optimize=True)

        alpha = canvas[..., 3]
        coverage = 100.0 * (alpha > 8).mean()
        print(f"✅ {f['dst']}  {canvas.shape[1]}x{canvas.shape[0]}  人物占画布 {coverage:.0f}%")

    return 0


if __name__ == "__main__":
    sys.exit(main())