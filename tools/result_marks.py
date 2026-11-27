"""战斗结算用的毛笔大字和印章（宋朝风味：繁体「勝」「敗」，钤一方「大捷」朱印）。

    python tools/result_marks.py [字体目录]

字体（都是 SIL OFL 1.1，从 google/fonts 下载；只在出图时用，游戏里不打包）：
- 大字用 Yuji Boku（ofl/yujiboku，毛笔楷书；中文毛笔字体大多没有繁体「勝」「敗」，这款有）
- 印章用 Zen Antique（ofl/zenantique，宋体字形，像刻出来的）
默认到 tools/fonts_src/ 找（不提交，自己下载），也可以把字体目录作为参数传进来。

输出到 art/ui/（白色、透明底，游戏里染色；印章自带朱红）：
- result_win.png  「勝」：浓墨起笔、边缘飞白
- result_lose.png 「敗」：枯笔、墨色更淡更散
- result_seal.png 「大捷」方印：白文（字是空的），边缘有崩口，印泥不匀
- result_stroke.png 「勝」字背后的一笔横刷：起笔圆头、收笔飞白（白色，游戏里染朱红）
- result_paper.png 结算卷轴的宣纸：米黄底、纤维纹和淡淡的水渍
- result_rod.png 卷轴两头的木轴（竖着的圆柱，左右暗、偏左高光；游戏里竖着拉长）
- result_cap.png 木轴上下的玉色轴头
- result_brocade.png 包首锦缎的一块花样（靛青底、金色回纹小格，游戏里平铺）
- result_plaque.png / result_plaque_red.png 云头木牌按钮（两头像如意云头，金边、木纹；朱漆的是主按钮）
- result_tassel.png 主按钮下面垂的红穗
需要 Pillow、numpy。
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "ui"
FONT_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools" / "fonts_src"
BRUSH = FONT_DIR / "YujiBoku-Regular.ttf"
CARVE = FONT_DIR / "ZenAntique-Regular.ttf"
SEAL_RED = (178, 38, 30)


def glyph(ch: str, size: int, canvas: int, font_path: Path = BRUSH) -> np.ndarray:
    """一个字的灰度遮罩（0～1），字居中。"""
    font = ImageFont.truetype(str(font_path), size)
    img = Image.new("L", (canvas, canvas), 0)
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), ch, font=font)
    x = (canvas - (box[2] - box[0])) / 2 - box[0]
    y = (canvas - (box[3] - box[1])) / 2 - box[1]
    d.text((x, y), ch, font=font, fill=255)
    return np.asarray(img, dtype=np.float32) / 255.0


def noise(rng: np.random.Generator, shape: tuple, blur: float, stretch: tuple = (1, 1)) -> np.ndarray:
    """平滑的随机噪声（0～1）；stretch 让纹理顺着某个方向拉长（笔毛的方向）。"""
    h, w = shape
    small = rng.random((max(h // stretch[0], 1), max(w // stretch[1], 1)))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    img = img.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(img, dtype=np.float32) / 255.0
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


def brush_char(ch: str, seed: int, dry: float, canvas: int = 420) -> Image.Image:
    """毛笔字：边缘飞白（笔画边上被横向拉长的纹理咬掉一些），墨有浓淡。dry 越大越枯。"""
    rng = np.random.default_rng(seed)
    m = glyph(ch, int(canvas * 0.84), canvas)
    # 笔画内部离边缘多远：飞白只出在边上，越靠边越枯
    soft = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(7)), dtype=np.float32) / 255.0
    edge = np.clip((1 - soft) * 3.0 - 0.9, 0, 1) * m
    # 笔毛：斜着拉长的细纹（行笔大多是横画、往右下走）
    hair = noise(rng, m.shape, 0.8, (2, 40))
    hair = np.asarray(Image.fromarray((hair * 255).astype(np.uint8)).rotate(-12, resample=Image.BICUBIC), dtype=np.float32) / 255.0
    bite = np.clip((dry - hair) * 8, 0, 1) * edge
    alpha = m * (1 - bite)
    # 墨色浓淡
    alpha *= 0.88 + 0.12 * noise(rng, m.shape, 20)
    # 零星溅出的小墨点（圆的，挨着笔画）
    dots = Image.new("L", m.shape[::-1], 0)
    dd = ImageDraw.Draw(dots)
    near = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(31)), dtype=np.float32) / 255.0
    ys, xs = np.nonzero((near > 0.5) & (m < 0.1))
    for i in rng.choice(len(ys), size=min(26, len(ys)), replace=False):
        r = rng.uniform(1.2, 3.6)
        dd.ellipse((xs[i] - r, ys[i] - r, xs[i] + r, ys[i] + r), fill=int(rng.uniform(150, 255)))
    alpha = np.maximum(alpha, np.asarray(dots, dtype=np.float32) / 255.0)
    a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    out = Image.new("RGBA", m.shape[::-1], (255, 255, 255, 0))
    out.putalpha(a)
    return out


def seal(text: str, seed: int, size: int = 220) -> Image.Image:
    """白文方印：朱红印面，字是空的（竖排，右起）；边缘崩口，印泥不匀。"""
    rng = np.random.default_rng(seed)
    s = size
    body = np.zeros((s, s), np.float32)
    m = 10
    body[m:s - m, m:s - m] = 1
    # 两个字竖排
    for i, ch in enumerate(text):
        g = glyph(ch, int(s * 0.41), s, CARVE)
        g = np.roll(g, int((i - 0.5) * s * 0.40), axis=0)
        g = np.asarray(Image.fromarray((g * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)), dtype=np.float32) / 255.0
        body *= 1 - g
    # 边缘崩口：外框按噪声往里咬
    yy, xx = np.mgrid[0:s, 0:s]
    dist_edge = np.minimum(np.minimum(xx, yy), np.minimum(s - 1 - xx, s - 1 - yy)) - m
    chip = noise(rng, (s, s), 3) * 14 - 4
    body *= ((dist_edge > chip) | (dist_edge > 10)).astype(np.float32)
    # 印泥不匀：有的地方没沾上
    ink = noise(rng, (s, s), 2.5)
    body *= (ink > 0.18).astype(np.float32) * (0.82 + 0.18 * noise(rng, (s, s), 10))
    a = Image.fromarray((np.clip(body, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.new("RGBA", (s, s), SEAL_RED + (0,))
    out.putalpha(a)
    return out


def stroke(w: int = 1100, h: int = 240, seed: int = 21) -> Image.Image:
    """一笔横刷：起笔顿一下（圆头），中段饱满略有起伏，往右墨渐干、一根根笔毛断开成飞白。"""
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 1, w)
    k = np.ones(15) / 15
    wobble = lambda sd: np.convolve(rng.normal(0, sd, w), k, mode="same")
    # 半宽：起笔处圆头（四分之一圆），往右慢慢收细
    head = np.sqrt(np.clip(x / 0.07, 0, 1) * (2 - np.clip(x / 0.07, 0, 1)))
    half = h * 0.36 * head * (1 - 0.35 * x ** 1.6)
    top = half + wobble(5)
    bottom = half * 0.9 + wobble(5)
    center = h / 2 + 7 * np.sin(x * 3.2 + 0.6)
    yy = np.arange(h)[:, None]
    d = np.where(yy < center[None, :], (center[None, :] - yy) / np.maximum(top, 1)[None, :], (yy - center[None, :]) / np.maximum(bottom, 1)[None, :])
    alpha = np.clip((1 - d) * 8, 0, 1)
    # 飞白：每一行一根笔毛，墨到某处干了就断，越往右断得越多
    dry_from = 0.5 + 0.5 * rng.random(h) ** 0.6
    hair = (x[None, :] < dry_from[:, None]).astype(np.float32)
    speckle = rng.random((h, w)) < 0.3 * np.clip(1 - (x[None, :] - dry_from[:, None]) * 8, 0, 1)
    alpha *= np.maximum(hair, speckle)
    alpha *= 0.85 + 0.15 * noise(rng, (h, w), 16)
    a = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    # 起笔斜着下笔：整笔往右上错一点（上边比下边靠右）
    pad = int(h * 0.35)
    wide = Image.new("L", (w + pad, h), 0)
    wide.paste(a, (0, 0))
    a = wide.transform((w + pad, h), Image.AFFINE, (1, -0.35, 0, 0, 1, 0), resample=Image.BICUBIC)
    out = Image.new("RGBA", (w + pad, h), (255, 255, 255, 0))
    out.putalpha(a)
    return out


def paper(w: int = 640, h: int = 400, seed: int = 5) -> Image.Image:
    """宣纸：米黄底，细纤维和淡水渍。"""
    rng = np.random.default_rng(seed)
    base = np.array([236, 224, 196], np.float32)
    tone = noise(rng, (h, w), 40) * 14 - 7
    fiber = (noise(rng, (h, w), 0.5, (1, 10)) - 0.5) * 10
    grain = rng.normal(0, 3, (h, w))
    img = base[None, None, :] + (tone + fiber + grain)[:, :, None] * np.array([1, 1, 1.2])[None, None, :]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def cylinder(w: int, h: int, dark: tuple, light: tuple) -> Image.Image:
    """竖着的圆柱：左右两边暗，偏左一条高光。"""
    x = np.linspace(-1, 1, w)
    k = np.clip(1 - ((x + 0.3) / 1.1) ** 2, 0, 1) ** 0.8
    col = np.array(dark)[None, :] * (1 - k[:, None]) + np.array(light)[None, :] * k[:, None]
    arr = np.repeat(col[None, :, :], h, axis=0)
    return Image.fromarray(arr.astype(np.uint8), "RGB").convert("RGBA")


def rod() -> Image.Image:
    im = cylinder(48, 64, (60, 34, 18), (150, 98, 58))
    # 一点竖向木纹
    rng = np.random.default_rng(31)
    arr = np.asarray(im).astype(np.float32)
    arr[:, :, :3] *= (0.92 + 0.12 * noise(rng, (64, 48), 0.8, (16, 1)))[:, :, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def cap() -> Image.Image:
    im = cylinder(64, 32, (110, 132, 104), (226, 236, 210))
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 63, 31), radius=12, fill=255)
    im.putalpha(m)
    return im


def brocade() -> Image.Image:
    """锦缎花样的一块（36×36，两行错开，平铺不露缝）：靛青底，金色回纹小方格，中间一点。"""
    gold = (206, 166, 86)
    im = Image.new("RGBA", (36, 36), (38, 56, 84, 255))
    d = ImageDraw.Draw(im)
    for x, y in ((4, 4), (22, 22)):
        d.rectangle((x, y, x + 9, y + 9), outline=gold + (150,), width=1)
        d.rectangle((x + 4, y + 4, x + 5, y + 5), fill=gold + (210,))
    return im


def plaque(primary: bool, w: int = 380, h: int = 120) -> Image.Image:
    """云头木牌：中间一块圆角长板，两头各鼓出三个小圆像如意云头；金边，里面一圈细金线，有横向木纹。"""
    rng = np.random.default_rng(41 if primary else 43)
    s = 2  # 先画两倍大再缩小，边缘平滑
    W, H = w * s, h * s
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    pad = 3 * s  # 留边，不然贴着图边的地方腐蚀不出金边
    r = H // 2 - pad
    d.rounded_rectangle((r // 2 + pad, pad, W - r // 2 - pad, H - 1 - pad), radius=10 * s, fill=255)
    for cx in (r // 2 + 2 * s + pad, W - r // 2 - 2 * s - pad):
        for dy in (-r * 0.55, 0, r * 0.55):
            rr = r * 0.42
            d.ellipse((cx - rr, H / 2 + dy - rr, cx + rr, H / 2 + dy + rr), fill=255)
    fill = (150, 34, 24) if primary else (66, 44, 28)
    body = np.zeros((H, W, 4), np.float32)
    body[:, :, :3] = np.array(fill) * (0.86 + 0.22 * noise(rng, (H, W), 1.0, (1, 30)))[:, :, None]
    gold = np.array([206, 166, 86], np.float32)
    shrink = lambda im, k: im.filter(ImageFilter.MinFilter(k))
    inner = shrink(m, 5 * s + 1)          # 金边以内是木头
    ring = shrink(inner, 3 * s + 1)
    thin = np.asarray(ring, np.float32) - np.asarray(shrink(ring, 2 * s + 1), np.float32)  # 里面一圈细金线
    a_all = np.asarray(m, np.float32) / 255
    a_wood = np.asarray(inner, np.float32) / 255
    rgb = gold[None, None, :] * (1 - a_wood[:, :, None]) + body[:, :, :3] * a_wood[:, :, None]
    t = np.clip(thin / 255 * 0.65, 0, 1)[:, :, None]
    rgb = rgb * (1 - t) + gold[None, None, :] * t
    out = np.dstack([rgb, a_all * 255])
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return img.resize((w, h), Image.LANCZOS)


def tassel(w: int = 40, h: int = 110) -> Image.Image:
    """红穗：上面一颗金珠、一个小结，下面一绺红丝。"""
    s = 2
    im = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = w * s / 2
    d.line((cx, 0, cx, 18 * s), fill=(190, 40, 30, 255), width=2 * s)
    d.ellipse((cx - 6 * s, 14 * s, cx + 6 * s, 26 * s), fill=(214, 172, 90, 255))
    d.ellipse((cx - 5 * s, 28 * s, cx + 5 * s, 40 * s), fill=(176, 34, 26, 255))
    rng = np.random.default_rng(51)
    for k in np.linspace(-1, 1, 15):
        end = cx + k * 9 * s + rng.normal(0, s)
        d.line((cx + k * 3 * s, 38 * s, end, (h - 4 - abs(k) * 6) * s), fill=(196 - int(abs(k) * 30), 42, 32, 255), width=s)
    return im.resize((w, h), Image.LANCZOS)


def main() -> None:
    for f in (BRUSH, CARVE):
        if not f.exists():
            sys.exit(f"找不到字体 {f}：从 https://github.com/google/fonts/tree/main/ofl 下载")
    OUT.mkdir(parents=True, exist_ok=True)
    brush_char("勝", 3, 0.35).save(OUT / "result_win.png")
    brush_char("敗", 8, 0.55).save(OUT / "result_lose.png")
    seal("大捷", 13).save(OUT / "result_seal.png")
    stroke().save(OUT / "result_stroke.png")
    paper().save(OUT / "result_paper.png")
    rod().save(OUT / "result_rod.png")
    cap().save(OUT / "result_cap.png")
    brocade().save(OUT / "result_brocade.png")
    plaque(False).save(OUT / "result_plaque.png")
    plaque(True).save(OUT / "result_plaque_red.png")
    tassel().save(OUT / "result_tassel.png")
    print("已输出到", OUT)


if __name__ == "__main__":
    main()
