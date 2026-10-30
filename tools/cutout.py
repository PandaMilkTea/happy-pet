#!/usr/bin/env python3
"""把 AI 生成的实心背景立绘/帧序列抠成透明 PNG,并按「脚底 + 重心」对齐。

用法:
    # 批量模式(推荐): 把原图丢进 Resources/frames/,一键输出到 Resources/Assets/
    python3 tools/cutout.py --batch
    python3 tools/cutout.py --batch 输入目录 输出目录

    # 单张/成对模式
    python3 tools/cutout.py 输入1.png 输出1.png [输入2.png 输出2.png ...]

环境变量:
    TOL=38         背景容差,越大抠得越狠
    EDGE=7         线稿描边的梯度阈值,主体和背景同色(白猫/白爪)时靠它兜底,EDGE=0 关闭
    SEAL=4         描边缺口的封口半径(像素),白色从缺口漏出去时调大,SEAL=0 关闭
    ANCHOR=auto    对齐策略: auto(默认,漂了才对齐) / foot(强制脚底对齐) / bbox(原样并集)
    DRIFT_TOL=0.02 auto 模式下判定「漂了」的阈值(占人物高度比例)
    FOOT_BAND=0.12 取底部多少比例的像素来估算双脚重心
    ROLE=          只处理该角色的帧(文件名前缀,如 ROLE=cat 只处理 cat_*.png)
    REF=           参考立绘;默认取 Resources/Assets/<角色>_body.png,REF=none 关闭
    WM=0.2x0.06    抹掉右下角「宽占比 x 高占比」的 AI 水印区,WM=none 关闭

多角色注意:
    整组统一缩放是「同一角色」内部的归一,猫和人混在一批会被拉成同一身高。
    所以批量模式检测到多个前缀时会直接报错,请按角色分批:
        ROLE=cat ANCHOR=foot python3 tools/cutout.py --batch

为什么要脚底对齐:
    走路帧里手脚张开,整体包围盒会变宽变高;若按包围盒对齐,
    人物会在帧间上下漂移,看起来像「滑步」。
    改成把每帧的「脚底 y + 脚部重心 x」钉在画布同一点,
    切帧时下半身稳定,只有肢体在动。
    反之如果原图站位本来就一致(同 seed 图生图),强行对齐反而会被
    抠图毛边带偏,所以 auto 模式会先量一下漂移再决定。

抠图要点:
1. 以四边像素中位色作为背景参考色,阈值出「候选背景」;
2. 叠加梯度检测把线稿描边钉成「墙」并闭运算封口,再只保留与画布边界
   连通的区域作为真背景,最后填洞——这样白猫身体、白爪子这种和背景同色
   的部位才不会从描边缺口「漏」出去被整片删掉;
3. 边缘羽化 + C = (I - (1-a)*bg) / a 去背景色溢出,消除「白边」;
4. 所有帧输出同一画布尺寸,保证 SwiftUI 里切帧不跳。
"""

import glob
import os
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

TOL = float(os.environ.get("TOL", "38"))
# 白猫、白爪这类「主体和背景同色」的素材,光靠颜色容差必然会把身体当背景。
# 救命的是线稿描边:再淡的描边也有梯度。EDGE 把梯度大的像素钉成「墙」,
# SEAL 再把墙做一次闭运算,焊上描边的细小缺口,白色就漏不出画布了。
EDGE_TOL = float(os.environ.get("EDGE", "7"))
SEAL = int(os.environ.get("SEAL", "4"))
ANCHOR_MODE = os.environ.get("ANCHOR", "auto").lower()
FOOT_BAND = float(os.environ.get("FOOT_BAND", "0.12"))
ROW_THRESH = float(os.environ.get("ROW_THRESH", "0.04"))
DRIFT_TOL = float(os.environ.get("DRIFT_TOL", "0.02"))
FRAGMENT_RATIO = 0.01
PAD_RATIO = 0.05
# 参考立绘:帧画布会被归一到和它完全一致的「人物高度占比 + 脚底位置」,
# 这样 SwiftUI 里从立绘切到帧动画时人物不会忽大忽小。REF=none 可关闭。
# 不显式指定 REF 时,按当前批次的角色取 Resources/Assets/<role>_body.png
ROLE = os.environ.get("ROLE", "").strip().lower()
REF_PATH = os.environ.get("REF", "").strip()
# AI 作图工具常在右下角压水印,小块水印会逃过碎片过滤被当成人物抠进来,
# 把画布横向撑得很宽。WM=<宽占比>x<高占比> 指定右下角要抹平的区域(默认 0.2x0.06),
# WM=none 关闭。按比例定义以同时兼容横版/竖版原图。
WM_SPEC = os.environ.get("WM", "0.2x0.06").strip().lower()
DEFAULT_SRC_DIR = "Resources/frames"
DEFAULT_DST_DIR = "Resources/Assets"
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")


def watermark_ratio():
    """解析 WM 规格,返回 (宽占比, 高占比);关闭时返回 None"""
    if WM_SPEC in ("none", "no", "off", "0"):
        return None
    m = re.fullmatch(r"([0-9.]+)x([0-9.]+)", WM_SPEC)
    if not m:
        raise SystemExit(f"❌ WM 格式应为 <宽占比>x<高占比>,例如 0.2x0.06,收到 {WM_SPEC!r}")
    return float(m.group(1)), float(m.group(2))


def wipe_watermark(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """把右下角水印区域填成背景色,避免被当成前景"""
    ratio = watermark_ratio()
    if ratio is None:
        return rgb
    h, w = rgb.shape[:2]
    x0 = max(0, int(round(w * (1.0 - ratio[0]))))
    y0 = max(0, int(round(h * (1.0 - ratio[1]))))
    patch = rgb[y0:, x0:]
    if patch.size == 0:
        return rgb
    dirty = (np.abs(patch.astype(np.int16) - bg.astype(np.int16)).max(axis=2) > TOL).mean()
    out = rgb.copy()
    out[y0:, x0:] = bg.astype(rgb.dtype)
    print(f"  抹除右下角水印区 x≥{x0} y≥{y0}(该区非背景像素 {100.0 * dirty:.1f}%)")
    return out


def estimate_bg_color(rgb: np.ndarray) -> np.ndarray:
    """四条边界像素的中位色"""
    edges = np.concatenate([
        rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]
    ], axis=0)
    return np.median(edges, axis=0)


def build_foreground_mask(rgb: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """返回 True = 前景(人物)

    难点在「白猫站在白底上」这种主体与背景同色的素材:单纯按颜色容差,
    猫身体会落进背景候选,再从描边的某个缺口和画布外的白底连通,整片被删。
    所以这里不直接用颜色判定,而是分三步:
      1. 墙 = 颜色明显偏离背景的像素 ∪ 梯度大的像素(线稿描边再淡也有梯度);
      2. 把墙做闭运算焊住细缺口,此时「与画布边界连通的非墙区域」才是真背景;
      3. 闭运算让墙胖了一圈,再把背景朝回膨胀,但只允许吃背景色像素,不碰主体。
    最后填洞,把被描边围住的同色区域(白猫肚子、白爪子)补回来。
    """
    rgb_f = rgb.astype(np.float32)
    dist = np.abs(rgb_f - bg).mean(axis=2)
    bg_like = dist <= TOL
    wall = ~bg_like

    if EDGE_TOL > 0:
        gray = rgb_f.mean(axis=2)
        gx = ndimage.sobel(gray, axis=1, mode="nearest")
        gy = ndimage.sobel(gray, axis=0, mode="nearest")
        edge = np.hypot(gx, gy) / 4.0 > EDGE_TOL
        wall |= edge

    cross = ndimage.generate_binary_structure(2, 2)
    sealed = wall
    if SEAL > 0:
        sealed = ndimage.binary_closing(wall, structure=cross, iterations=SEAL)

    open_space = ~sealed
    labels, count = ndimage.label(open_space)
    if count == 0:
        return np.ones(rgb.shape[:2], dtype=bool)
    border = np.concatenate([
        labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]
    ])
    border_ids = np.unique(border)
    border_ids = border_ids[border_ids != 0]
    outside = np.isin(labels, border_ids)

    # 闭运算把墙加厚了 SEAL 圈,背景也就瘦了 SEAL 圈。朝回膨胀补偿,
    # mask=bg_like 保证只能收回背景色像素,主体轮廓一根头发都不会少。
    if SEAL > 0 and outside.any():
        outside = ndimage.binary_dilation(
            outside, structure=cross, iterations=SEAL, mask=bg_like
        )

    fg = ndimage.binary_fill_holes(~outside)

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
    a = np.clip((a - 0.12) / 0.76, 0.0, 1.0)

    rgb_f = rgb.astype(np.float32)
    partial = (a > 0.02) & (a < 0.98)
    if partial.any():
        a3 = a[..., None]
        unmixed = (rgb_f - (1.0 - a3) * bg) / np.maximum(a3, 0.02)
        rgb_f = np.where(partial[..., None], np.clip(unmixed, 0, 255), rgb_f)

    rgba = np.zeros(rgb.shape[:2] + (4,), dtype=np.uint8)
    rgba[..., :3] = rgb_f.round().astype(np.uint8)
    rgba[..., 3] = (a * 255).round().astype(np.uint8)
    rgba[a <= 0.0, :3] = 0
    return rgba


def bbox_of(rgba: np.ndarray):
    solid = rgba[..., 3] > 8
    rows = np.where(solid.any(axis=1))[0]
    cols = np.where(solid.any(axis=0))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return int(rows[0]), int(rows[-1]), int(cols[0]), int(cols[-1])


def anchor_of(rgba: np.ndarray, box):
    """锚点 = (脚部重心 x, 脚底 y)。

    脚底不能直接取「最后一行可见像素」——抠图毛边、淡淡的裙摆余晖会让它
    在帧之间抖十几个像素。这里用行 alpha 总量的 ROW_THRESH 比例做鲁棒判定,
    稀疏的尾巴直接忽略。重心取底部 FOOT_BAND 高度内 alpha 加权的 x 均值,
    约等于双脚中点。"""
    top, bottom, left, right = box
    alpha = rgba[..., 3].astype(np.float32) / 255.0
    rows = alpha[top:bottom + 1, left:right + 1].sum(axis=1)
    thresh = max(rows.max() * ROW_THRESH, 0.5)
    solid_rows = np.where(rows >= thresh)[0]
    if len(solid_rows):
        bottom = top + int(solid_rows[-1])
    height = bottom - top + 1
    band = max(1, int(round(height * FOOT_BAND)))
    band_top = max(top, bottom - band + 1)
    strip = alpha[band_top:bottom + 1, left:right + 1]
    weight = strip.sum()
    if weight < 1e-3:
        strip = alpha[top:bottom + 1, left:right + 1]
        weight = max(strip.sum(), 1e-3)
    xs = np.arange(left, right + 1, dtype=np.float32)
    cx = float((strip.sum(axis=0) * xs).sum() / weight)
    return cx, float(bottom)


def natural_key(path: str):
    """girl_walk_2.png 排在 girl_walk_10.png 前面"""
    name = os.path.splitext(os.path.basename(path))[0]
    parts = re.split(r"(\d+)", name)
    return [int(p) if p.isdigit() else p for p in parts]


def role_of(path: str) -> str:
    """文件名 girl_walk_1.png → girl;没有下划线就算 ''(无角色)"""
    name = os.path.splitext(os.path.basename(path))[0]
    return name.split("_", 1)[0].lower() if "_" in name else ""


def collect_pairs(args):
    """返回 [(输入路径, 输出路径), ...]"""
    global REF_PATH
    if args and args[0] == "--batch":
        src_dir = args[1] if len(args) > 1 else DEFAULT_SRC_DIR
        dst_dir = args[2] if len(args) > 2 else DEFAULT_DST_DIR
        if not os.path.isdir(src_dir):
            print(f"❌ 找不到目录 {src_dir}")
            print(f"   请先把 AI 生成的原图放进 {src_dir}/,文件名形如 girl_walk_1.png")
            return None
        files = [
            p for p in glob.glob(os.path.join(src_dir, "*"))
            if os.path.splitext(p)[1].lower() in IMAGE_EXTS
        ]
        if not files:
            print(f"❌ {src_dir} 里没有图片")
            return None
        if ROLE:
            files = [p for p in files if role_of(p) == ROLE]
            if not files:
                print(f"❌ {src_dir} 里没有 {ROLE}_ 开头的图片")
                return None
        roles = sorted({role_of(p) for p in files})
        # 整组统一缩放是按「同一个角色」算的,混批会把猫和人拉成一个身高
        if len(roles) > 1:
            print(f"❌ 检测到多个角色: {', '.join(r or '(无前缀)' for r in roles)}")
            print("   整组统一缩放只能按单个角色进行,请分批处理,例如:")
            print(f"   ROLE={roles[0]} ANCHOR=foot python3 tools/cutout.py --batch")
            return None
        role = roles[0]
        if not REF_PATH and role:
            REF_PATH = os.path.join(DEFAULT_DST_DIR, f"{role}_body.png")
        files.sort(key=natural_key)
        print(f"📂 {src_dir} → {dst_dir},角色 {role or '(无前缀)'},共 {len(files)} 张")
        return [
            (p, os.path.join(
                dst_dir, os.path.splitext(os.path.basename(p))[0] + ".png"))
            for p in files
        ]

    if len(args) < 2 or len(args) % 2 != 0:
        print(__doc__)
        return None
    pairs = [(args[i], args[i + 1]) for i in range(0, len(args), 2)]
    if not REF_PATH:
        role = role_of(pairs[0][1]) or role_of(pairs[0][0])
        if role:
            REF_PATH = os.path.join(DEFAULT_DST_DIR, f"{role}_body.png")
    return pairs


def process_one(src: str, dst: str):
    print(f"🧽 处理 {os.path.basename(src)}")
    img = Image.open(src)
    if img.mode in ("RGBA", "LA") and np.asarray(img)[..., -1].min() < 250:
        # 已经是透明图,直接沿用现成 alpha
        rgba = np.asarray(img.convert("RGBA")).copy()
        print("  已是透明 PNG,跳过抠图")
    else:
        rgb = np.asarray(img.convert("RGB"))
        bg = estimate_bg_color(rgb)
        print(f"  背景参考色 RGB({bg[0]:.0f}, {bg[1]:.0f}, {bg[2]:.0f})")
        rgb = wipe_watermark(rgb, bg)
        fg = build_foreground_mask(rgb, bg)
        print(f"  去除背景像素 {100.0 * (1.0 - fg.mean()):.1f}%")
        if fg.mean() < 0.02:
            print("  ⚠️ 前景几乎没剩,TOL 太大,跳过这张")
            return None
        if fg.mean() > 0.98:
            print("  ⚠️ 几乎没抠掉东西,TOL 太小,跳过这张")
            return None
        rgba = make_rgba(rgb, fg, bg)

    box = bbox_of(rgba)
    if box is None:
        print("  ⚠️ 没有可见内容,跳过这张")
        return None
    ax, ay = anchor_of(rgba, box)
    print(f"  锚点 脚底 y={ay:.0f} 重心 x={ax:.0f}  "
          f"内容 {box[3] - box[2] + 1}x{box[1] - box[0] + 1}")
    return {"dst": dst, "rgba": rgba, "box": box, "ax": ax, "ay": ay}


def choose_mode(frames):
    """auto: 原图站位已经一致就别乱动(抠图毛边会让脚底估计差几十像素),
    只有真漂了才启用脚底对齐。"""
    if ANCHOR_MODE in ("foot", "bbox"):
        return ANCHOR_MODE
    if len({f["rgba"].shape[:2] for f in frames}) > 1:
        print("  原图尺寸不一致 → 脚底对齐")
        return "foot"
    if len(frames) == 1:
        return "bbox"
    tall = max(f["box"][1] - f["box"][0] for f in frames)
    axs = [f["ax"] for f in frames]
    ays = [f["ay"] for f in frames]
    drift = max(max(axs) - min(axs), max(ays) - min(ays))
    limit = tall * DRIFT_TOL
    print(f"  帧间站位漂移 {drift:.0f}px(阈值 {limit:.0f}px)")
    return "foot" if drift > limit else "bbox"


def layout(frames):
    """算出统一画布尺寸和锚点在画布中的位置"""
    mode = choose_mode(frames)
    if mode == "bbox":
        # 直接沿用原图坐标系求并集:站位本来一致,不做任何平移
        for f in frames:
            f["ax"] = 0.0
            f["ay"] = 0.0
    l = max(f["ax"] - f["box"][2] for f in frames)
    r = max(f["box"][3] - f["ax"] for f in frames)
    t = max(f["ay"] - f["box"][0] for f in frames)
    b = max(f["box"][1] - f["ay"] for f in frames)
    w = int(np.ceil(l + r)) + 1
    h = int(np.ceil(t + b)) + 1
    pad = int(round(max(w, h) * PAD_RATIO))
    return {
        "w": w + pad * 2,
        "h": h + pad * 2,
        "ax": l + pad,
        "ay": t + pad,
        "mode": mode,
    }


def load_reference(dsts):
    """读参考立绘,拿到「画布尺寸 / 锚点 / 人物高度」三件套"""
    if REF_PATH.strip().lower() in ("", "none", "off", "0"):
        return None
    path = REF_PATH
    if not os.path.exists(path) or os.path.abspath(path) in dsts:
        return None
    try:
        rgba = np.array(Image.open(path).convert("RGBA"))
    except Exception as exc:
        print(f"⚠️  参考立绘读取失败 {path}: {exc}")
        return None
    box = bbox_of(rgba)
    if box is None:
        return None
    ax, ay = anchor_of(rgba, box)
    h, w = rgba.shape[:2]
    person = ay - box[0] + 1
    if person < 8:
        return None
    print(f"📐 参考立绘 {path} {w}x{h},人物高 {person:.0f}(占 {person / h:.1%})")
    return {"w": w, "h": h, "ax": ax, "ay": ay, "person": person}


def render_with_reference(frames, ref):
    """按参考立绘的像素尺度统一所有帧:
    1. 整组共用一个缩放系数(取各帧身高中位数做基准)——按每帧自己的身高缩放
       会把蜷缩/跳起的帧放大,人物就一帧一个大小了;
    2. 每帧的「脚底 + 脚部重心」钉到参考立绘的同一锚点,腾空交给程序的 jump;
    3. 甩手/跳起撑出画布时整组按同一因子放大画布,像素尺度不变。"""
    heights = sorted(f["ay"] - f["box"][0] + 1 for f in frames)
    base = heights[len(heights) // 2]          # 中位身高,抗异常帧
    scale = ref["person"] / max(base, 1.0)
    spread = (heights[-1] - heights[0]) / max(base, 1.0)
    print(f"📏 整组统一缩放 {scale:.3f}×(基准身高 {base:.0f},帧间身高差 {spread:.1%})")

    plans = []
    for f in frames:
        top, bottom, left, right = f["box"]
        ox = (f["ax"] - left) * scale          # 锚点在缩放后内容里的 x
        oy = (f["ay"] - top) * scale
        cw = (right - left + 1) * scale
        chh = (bottom - top + 1) * scale
        plans.append({"f": f, "scale": scale, "ox": ox, "oy": oy, "cw": cw, "ch": chh})
    # 画布只往需要的方向扩:水平保持「锚点居中」(不然人物会左右漂),
    # 垂直只加高顶部、底部留白锁死成立绘的值 —— 这样渲染层按
    # 「画布高 / 立绘高」换算显示尺寸时,脚底位置和人物高度都和立绘严丝合缝。
    half = max(ref["ax"], ref["w"] - ref["ax"])
    half = max([half] + [max(p["ox"], p["cw"] - p["ox"]) for p in plans])
    bot = max([ref["h"] - ref["ay"]] + [p["ch"] - p["oy"] for p in plans])
    top_m = max([ref["ay"]] + [p["oy"] for p in plans])
    W, H = int(round(half * 2)), int(round(top_m + bot))
    AX, AY = half, top_m
    grow = f"{W / ref['w']:.2f}×宽 {H / ref['h']:.2f}×高"
    print(f"🔗 {len(frames)} 帧共用 {W}x{H} 画布(参考立绘归一,{grow})")

    for p in plans:
        f = p["f"]
        top, bottom, left, right = f["box"]
        cropped = f["rgba"][top:bottom + 1, left:right + 1]
        nw = max(1, int(round(p["cw"])))
        nh = max(1, int(round(p["ch"])))
        if abs(p["scale"] - 1.0) > 1e-3:
            cropped = np.array(
                Image.fromarray(cropped, mode="RGBA").resize((nw, nh), Image.LANCZOS)
            )
        nh, nw = cropped.shape[:2]
        x0 = int(round(AX - p["ox"]))
        y0 = int(round(AY - p["oy"]))
        x0 = max(0, min(x0, W - nw))
        y0 = max(0, min(y0, H - nh))

        canvas = np.zeros((H, W, 4), dtype=np.uint8)
        canvas[y0:y0 + nh, x0:x0 + nw] = cropped
        os.makedirs(os.path.dirname(os.path.abspath(f["dst"])), exist_ok=True)
        Image.fromarray(canvas, mode="RGBA").save(f["dst"], optimize=True)
        print(f"✅ {f['dst']}  缩放 {p['scale']:.3f}× 人物高 {nh}")


def main() -> int:
    pairs = collect_pairs(sys.argv[1:])
    if pairs is None:
        return 1

    frames = []
    for src, dst in pairs:
        f = process_one(src, dst)
        if f is not None:
            frames.append(f)
    if not frames:
        print("❌ 一张都没成功")
        return 1

    ref = load_reference({os.path.abspath(d) for _, d in pairs})
    if ref is not None:
        render_with_reference(frames, ref)
        return 0

    plan = layout(frames)
    mode = "包围盒并集" if plan["mode"] == "bbox" else "脚底+重心"
    print(f"🔗 {len(frames)} 帧共用 {plan['w']}x{plan['h']} 画布({mode}对齐)")

    for f in frames:
        top, bottom, left, right = f["box"]
        cropped = f["rgba"][top:bottom + 1, left:right + 1]
        ch, cw = cropped.shape[:2]
        x0 = int(round(plan["ax"] - (f["ax"] - left)))
        y0 = int(round(plan["ay"] - (f["ay"] - top)))
        x0 = max(0, min(x0, plan["w"] - cw))
        y0 = max(0, min(y0, plan["h"] - ch))

        canvas = np.zeros((plan["h"], plan["w"], 4), dtype=np.uint8)
        canvas[y0:y0 + ch, x0:x0 + cw] = cropped

        os.makedirs(os.path.dirname(os.path.abspath(f["dst"])), exist_ok=True)
        Image.fromarray(canvas, mode="RGBA").save(f["dst"], optimize=True)
        coverage = 100.0 * (canvas[..., 3] > 8).mean()
        print(f"✅ {f['dst']}  人物占画布 {coverage:.0f}%")

    return 0


if __name__ == "__main__":
    sys.exit(main())