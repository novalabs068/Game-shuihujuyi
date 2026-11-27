"""招募画面用的图：做旧的聚义令（字刻进去、描金磨掉一些）、卡背、职业徽章。

    python tools/recruit_marks.py [--preview 目录]

字体（SIL OFL 1.1，从 google/fonts 下载到 tools/fonts_src/，只出图用，游戏里不打包）：
- Yuji Syuku / Yuji Boku（毛笔楷书，有繁体「義」）
- Zen Antique（宋体字形，像刻出来的）
- Ma Shan Zheng（毛笔楷书，只有简体）
输出到 art/ui/：
- juyi_token_old.png 做旧的聚义令（底图是 art/ui/juyi_token.png）：铜边氧化出铜绿、高处磨亮，乌木牌面有划痕、裂纹、污渍，「聚義」刻进木里、描金剥落
- card_back.png 卡背（440×660，游戏里缩到 220×330）
- role_<n>.png 五个职业徽章（n 是 UnitData.Role 的序号：战、刺、射、道、医）
--preview 时不写 art/ui，而是把几种候选拼成对比图放到给定目录（当初给用户挑的几版）。
需要 Pillow、numpy。
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "ui"
FONTS = ROOT / "tools" / "fonts_src"
SYUKU = FONTS / "YujiSyuku-Regular.ttf"
BOKU = FONTS / "YujiBoku-Regular.ttf"
CARVE = FONTS / "ZenAntique-Regular.ttf"
MASHAN = FONTS / "MaShanZheng-Regular.ttf"
GOLD = np.array([214, 172, 84], np.float32)
GOLD_DARK = np.array([120, 84, 30], np.float32)
SEAL_RED = (172, 38, 28)
## 职业徽章的珐琅色：战朱红、刺黛紫、射松绿、道靛蓝、医青绿（和 UiKit.ROLE_TAGS 顺序一致）
ROLE_GLYPHS = ["戰", "刺", "射", "道", "醫"]
ROLE_ENAMEL = [(160, 44, 32), (92, 56, 120), (58, 104, 56), (44, 74, 132), (36, 112, 102)]


# ---------- 工具 ----------

def noise(rng: np.random.Generator, h: int, w: int, blur: float, stretch=(1, 1)) -> np.ndarray:
    """平滑噪声 0～1；stretch 让纹理顺某个方向拉长。"""
    small = rng.random((max(h // stretch[0], 1), max(w // stretch[1], 1)))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255.0
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


def glyph_mask(text: str, font_path: Path, size: int, canvas: tuple, vertical=True, gap=0.0) -> np.ndarray:
    """几个字（竖排）居中写在 canvas 上，返回 0～1 遮罩。"""
    font = ImageFont.truetype(str(font_path), size)
    w, h = canvas
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    boxes = [d.textbbox((0, 0), ch, font=font) for ch in text]
    if vertical:
        total = sum(b[3] - b[1] for b in boxes) + gap * size * (len(text) - 1)
        y = (h - total) / 2
        for ch, b in zip(text, boxes):
            d.text(((w - (b[2] - b[0])) / 2 - b[0], y - b[1]), ch, font=font, fill=255)
            y += b[3] - b[1] + gap * size
    else:
        total = sum(b[2] - b[0] for b in boxes) + gap * size * (len(text) - 1)
        x = (w - total) / 2
        for ch, b in zip(text, boxes):
            d.text((x - b[0], (h - (b[3] - b[1])) / 2 - b[1]), ch, font=font, fill=255)
            x += b[2] - b[0] + gap * size
    return np.asarray(img, np.float32) / 255.0


def shift(a: np.ndarray, dx: int, dy: int) -> np.ndarray:
    return np.roll(np.roll(a, dy, 0), dx, 1)


def to_img(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


# ---------- 聚义令 ----------

## 牌面空白区（见 art/ui/juyi_token.png）
FACE = (30, 67, 138, 326)


def aged_token(seed: int = 3) -> np.ndarray:
    """把原来的聚义令做旧，返回 RGBA float 数组。"""
    src = np.asarray(Image.open(OUT / "juyi_token.png").convert("RGBA"), np.float32)
    rgb, a = src[..., :3].copy(), src[..., 3] / 255.0
    h, w = a.shape
    rng = np.random.default_rng(seed)
    lum = rgb.mean(-1) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    sat = (rgb.max(-1) - rgb.min(-1)) / 255.0
    yy, xx = np.mgrid[0:h, 0:w]
    in_face = (xx >= FACE[0]) & (xx < FACE[2]) & (yy >= FACE[1]) & (yy < FACE[3])
    tassel = (yy > 440)
    brass = (~in_face) & (~tassel) & (r > b + 8)

    # 铜：凹处长铜绿，高处磨得发亮，整体暗一点、色偏旧
    n1 = noise(rng, h, w, 1.5)
    n2 = noise(rng, h, w, 4)
    crevice = np.clip((0.32 - lum) / 0.2, 0, 1)
    patch = np.clip((n2 - 0.45) / 0.2, 0, 1)
    verdigris = np.clip(crevice * (0.3 + n1 * 0.7) * patch, 0, 1) * brass
    vg = np.array([84, 118, 92], np.float32)
    rgb = rgb * (1 - verdigris[..., None] * 0.6) + vg * verdigris[..., None] * 0.6
    high = np.clip((lum - 0.55) / 0.3, 0, 1) * brass
    rgb = rgb + high[..., None] * np.array([40, 30, 10], np.float32)
    gray = rgb.mean(-1, keepdims=True)
    rgb = np.where(brass[..., None], rgb * 0.82 + gray * 0.18, rgb) * np.where(brass[..., None], 0.92, 1.0)

    # 木：顺着木纹的裂纹、横竖划痕、四周的污渍
    face = in_face.astype(np.float32)
    grime = noise(rng, h, w, 10) * 0.5 + 0.5 * np.clip(
        np.minimum.reduce([xx - FACE[0], FACE[2] - xx, yy - FACE[1], FACE[3] - yy]) / 26.0, 0, 1)
    rgb = rgb * (1 - face[..., None] * (1 - grime[..., None]) * 0.3)
    marks = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(marks)
    for _ in range(3):  # 裂纹：竖着、弯弯曲曲
        x = rng.uniform(FACE[0] + 10, FACE[2] - 10)
        y = rng.uniform(FACE[1], FACE[3] - 80)
        pts = [(x, y)]
        for _ in range(int(rng.uniform(12, 30))):
            x += rng.normal(0, 0.7)
            y += rng.uniform(2, 5)
            pts.append((x, min(y, FACE[3] - 2)))
        d.line(pts, fill=255, width=1)
    crack = np.asarray(marks, np.float32) / 255.0 * face
    rgb = rgb * (1 - crack[..., None] * 0.7)
    rgb = rgb + (shift(crack, 1, 0) * (1 - crack))[..., None] * 18  # 裂口一边带一点亮
    marks = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(marks)
    for _ in range(26):  # 浅划痕
        x, y = rng.uniform(FACE[0], FACE[2]), rng.uniform(FACE[1], FACE[3])
        ang = rng.normal(0.4, 0.8)
        ln = rng.uniform(6, 30)
        d.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)], fill=int(rng.uniform(60, 160)), width=1)
    scratch = np.asarray(marks, np.float32) / 255.0 * face
    rgb = rgb + scratch[..., None] * np.array([46, 38, 30], np.float32)

    # 红穗：褪色、发灰
    t = tassel.astype(np.float32)[..., None]
    gray = rgb.mean(-1, keepdims=True)
    rgb = rgb * (1 - t) + (rgb * 0.75 + gray * 0.25) * 0.88 * t

    # 整块：边上一圈暗
    vign = np.clip(1 - (((xx - w / 2) / (w * 0.6)) ** 2 + ((yy - 220) / 300.0) ** 2) * 0.35, 0.6, 1)
    rgb = rgb * vign[..., None]
    return np.dstack([rgb, a])


def engrave(base: np.ndarray, text: str, font: Path, size: int, gap: float, seed: int, wear: float) -> Image.Image:
    """把字刻进牌面：刻槽里先压暗、左上投影；再描金，描金按 wear 剥落、露出木头。"""
    rgb, a = base[..., :3].copy(), base[..., 3]
    h, w = a.shape
    fw, fh = FACE[2] - FACE[0], FACE[3] - FACE[1]
    m = np.zeros((h, w), np.float32)
    m[FACE[1]:FACE[3], FACE[0]:FACE[2]] = glyph_mask(text, font, size, (fw, fh), gap=gap)
    rng = np.random.default_rng(seed)
    # 刻槽：槽底暗，上沿投下阴影，下沿反一点光
    soft = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    rgb = rgb * (1 - soft[..., None] * 0.55)
    inner_shadow = np.clip(soft - shift(soft, 2, 2), 0, 1)
    rgb = rgb * (1 - inner_shadow[..., None] * 0.5)
    rim = np.clip(shift(soft, -1, -1) - soft, 0, 1)
    rgb = rgb + rim[..., None] * 34
    # 描金：中间厚、边缘薄，噪声决定哪里剥落
    core = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)), np.float32) / 255
    flake = noise(rng, h, w, 1.5) * 0.3 + noise(rng, h, w, 6) * 0.7
    keep = np.clip((flake - wear) / 0.08, 0, 1) * np.clip(core * 1.2, 0, 1)
    shade = np.clip(0.55 + (noise(rng, h, w, 6) - 0.5) * 0.7 + (1 - (np.mgrid[0:h, 0:w][0] - FACE[1]) / fh) * 0.25, 0, 1)
    gold = GOLD_DARK + (GOLD - GOLD_DARK) * shade[..., None]
    gold = gold + inner_shadow[..., None] * -50
    rgb = rgb * (1 - keep[..., None]) + gold * keep[..., None]
    return to_img(rgb, a)


# ---------- 卡背 ----------

def _key_band(d: ImageDraw.ImageDraw, x0, y0, x1, y1, step: int, col, width=2) -> None:
    """一条回纹带（四边）。"""
    def key(x, y, s, horizontal):
        if horizontal:
            pts = [(x, y + s), (x, y), (x + s, y), (x + s, y + s * 0.66), (x + s * 0.33, y + s * 0.66), (x + s * 0.33, y + s * 0.33)]
        else:
            pts = [(x + s, y), (x, y), (x, y + s), (x + s * 0.66, y + s), (x + s * 0.66, y + s * 0.33), (x + s * 0.33, y + s * 0.33)]
        d.line(pts, fill=col, width=width, joint="curve")
    s = step
    x = x0
    while x + s <= x1:
        key(x, y0, s * 0.8, True)
        key(x, y1 - s * 0.8, s * 0.8, True)
        x += s
    y = y0 + s
    while y + s <= y1 - s:
        key(x0, y, s * 0.8, False)
        key(x1 - s * 0.8, y, s * 0.8, False)
        y += s


def _cloud(d: ImageDraw.ImageDraw, cx, cy, r, col, width=3, flip=(1, 1)) -> None:
    """一朵如意云头：三瓣卷云。"""
    fx, fy = flip
    for ox, oy, rr in [(0, 0, r), (r * 0.9, r * 0.35, r * 0.7), (-r * 0.2, r * 0.95, r * 0.6)]:
        c = (cx + ox * fx, cy + oy * fy)
        d.arc([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], 0, 300, fill=col, width=width)
        d.arc([c[0] - rr * 0.45, c[1] - rr * 0.45, c[0] + rr * 0.45, c[1] + rr * 0.45], 90, 360, fill=col, width=width)


def lacquer(w: int, h: int, seed: int, base=(46, 20, 14)) -> np.ndarray:
    """乌漆底：深红黑，有断纹（漆面年久的细裂）和光泽。"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    n = noise(rng, h, w, 18) * 0.6 + noise(rng, h, w, 3) * 0.4
    rgb = np.array(base, np.float32) * (0.7 + n[..., None] * 0.55)
    # 断纹：随机多边形网格的边
    crack = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(crack)
    for _ in range(140):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        ang = rng.choice([0, math.pi / 2]) + rng.normal(0, 0.35)
        ln = rng.uniform(10, 40)
        d.line([(x, y), (x + math.cos(ang) * ln, y + math.sin(ang) * ln)], fill=255, width=1)
    c = np.asarray(crack, np.float32) / 255 * 0.35
    rgb = rgb * (1 - c[..., None])
    sheen = np.exp(-(((xx - w * 0.3) / (w * 0.5)) ** 2 + ((yy - h * 0.25) / (h * 0.4)) ** 2)) * 26
    return rgb + sheen[..., None]


def card_back_a(w=440, h=660, seed=7) -> Image.Image:
    """乌漆描金：漆底断纹、金色回纹边、四角云头，中间一枚朱红圆印「義」，外面一圈金环和放射细线。"""
    rgb = lacquer(w, h, seed)
    gold_layer = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(gold_layer)
    d.rounded_rectangle([10, 10, w - 11, h - 11], 18, outline=255, width=5)
    d.rounded_rectangle([24, 24, w - 25, h - 25], 12, outline=200, width=2)
    _key_band(d, 34, 34, w - 34, h - 34, 22, 190, 2)
    d.rounded_rectangle([62, 62, w - 63, h - 63], 8, outline=200, width=2)
    for (cx, cy, f) in [(90, 92, (1, 1)), (w - 90, 92, (-1, 1)), (90, h - 92, (1, -1)), (w - 90, h - 92, (-1, -1))]:
        _cloud(d, cx, cy, 16, 210, 3, f)
    cx, cy = w / 2, h / 2
    for i in range(48):  # 放射细线
        ang = i / 48 * math.tau
        d.line([(cx + math.cos(ang) * 112, cy + math.sin(ang) * 112), (cx + math.cos(ang) * 150, cy + math.sin(ang) * 150)], fill=120, width=2)
    d.ellipse([cx - 104, cy - 104, cx + 104, cy + 104], outline=230, width=4)
    d.ellipse([cx - 96, cy - 96, cx + 96, cy + 96], outline=150, width=2)
    gm = np.asarray(gold_layer.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255
    rng = np.random.default_rng(seed + 1)
    wear = 0.75 + noise(rng, h, w, 2) * 0.35
    gm = gm * np.clip(wear, 0, 1)
    rgb = rgb * (1 - gm[..., None]) + (GOLD * (0.85 + noise(rng, h, w, 8)[..., None] * 0.3)) * gm[..., None]
    # 朱印
    seal = Image.new("L", (w, h), 0)
    ImageDraw.Draw(seal).ellipse([cx - 84, cy - 84, cx + 84, cy + 84], fill=255)
    sm = np.asarray(seal, np.float32) / 255
    ink = noise(rng, h, w, 1.5)
    sm = sm * np.clip(0.75 + ink * 0.5, 0, 1)
    txt = glyph_mask("義", CARVE, 118, (w, h))
    sm_face = sm * (1 - txt * np.clip(ink * 1.4 + 0.3, 0, 1))  # 白文：字是空的
    rgb = rgb * (1 - sm_face[..., None]) + np.array(SEAL_RED, np.float32) * sm_face[..., None]
    rgb = rgb + (sm * txt)[..., None] * np.array([40, 26, 16], np.float32) * 0
    rgb = rgb * (1 - (sm * txt)[..., None]) + (sm * txt)[..., None] * np.array([232, 214, 180], np.float32)
    return to_img(rgb, np.ones((h, w)))


def card_back_b(w=440, h=660, seed=9) -> Image.Image:
    """靛青锦缎：回纹锦缎平铺做底，中间一条宣纸竖签写墨色「聚義」，钤一方小朱印，金边。"""
    tile = Image.open(OUT / "result_brocade.png").convert("RGB").resize((44, 44), Image.NEAREST)
    bg = Image.new("RGB", (w, h))
    for y in range(0, h, 44):
        for x in range(0, w, 44):
            bg.paste(tile, (x, y))
    rgb = np.asarray(bg, np.float32) * 0.8
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    vign = 1 - np.clip(((xx - w / 2) / (w * 0.7)) ** 2 + ((yy - h / 2) / (h * 0.7)) ** 2, 0, 1) * 0.5
    rgb = rgb * vign[..., None]
    gl = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(gl)
    d.rounded_rectangle([10, 10, w - 11, h - 11], 18, outline=255, width=6)
    d.rounded_rectangle([26, 26, w - 27, h - 27], 12, outline=210, width=2)
    sx0, sx1, sy0, sy1 = w / 2 - 70, w / 2 + 70, 90, h - 90
    d.rectangle([sx0 - 8, sy0 - 8, sx1 + 8, sy1 + 8], outline=230, width=3)
    gm = np.asarray(gl, np.float32) / 255 * np.clip(0.75 + noise(rng, h, w, 2) * 0.35, 0, 1)
    rgb = rgb * (1 - gm[..., None]) + GOLD * gm[..., None]
    paper = (xx >= sx0) & (xx <= sx1) & (yy >= sy0) & (yy <= sy1)
    pcol = np.array([226, 208, 172], np.float32) * (0.88 + noise(rng, h, w, 3)[..., None] * 0.18)
    rgb = np.where(paper[..., None], pcol, rgb)
    txt = glyph_mask("聚義", BOKU, 150, (w, h), gap=-0.05)
    txt = txt * paper
    rgb = rgb * (1 - txt[..., None] * 0.92) + np.array([24, 18, 14], np.float32) * txt[..., None] * 0.92
    seal = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(seal)
    sd.rectangle([sx1 - 46, sy1 - 56, sx1 - 12, sy1 - 22], fill=255)
    sm = np.asarray(seal, np.float32) / 255 * np.clip(0.7 + noise(rng, h, w, 1.2) * 0.5, 0, 1)
    rgb = rgb * (1 - sm[..., None]) + np.array(SEAL_RED, np.float32) * sm[..., None]
    corner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(corner).rounded_rectangle([0, 0, w - 1, h - 1], 16, fill=255)
    return to_img(rgb, np.asarray(corner, np.float32) / 255)


def card_back_c(w=440, h=660, seed=11) -> Image.Image:
    """替天行道：乌漆底，杏黄大旗迎风，旗上墨字「替天行道」，下面几道水波（梁山泊），金边。"""
    rgb = lacquer(w, h, seed, base=(30, 24, 22))
    rng = np.random.default_rng(seed)
    flag = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(flag)
    pole_x = 120
    top, bottom = 110, 400
    pts = []
    for i in range(21):
        t = i / 20
        pts.append((pole_x + 6 + t * 210, top + math.sin(t * 5) * 14 + t * 10))
    for i in range(20, -1, -1):
        t = i / 20
        pts.append((pole_x + 6 + t * 210, bottom + math.sin(t * 5 + 0.6) * 16 - t * 10))
    d.polygon(pts, fill=255)
    fm = np.asarray(flag.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    fold = 0.8 + 0.25 * np.sin(np.mgrid[0:h, 0:w][1] / 210 * math.pi * 5)[..., None]
    fcol = np.array([206, 160, 60], np.float32) * fold * (0.9 + noise(rng, h, w, 4)[..., None] * 0.2)
    rgb = rgb * (1 - fm[..., None]) + fcol * fm[..., None]
    txt = np.zeros((h, w), np.float32)
    sub = glyph_mask("替天行道", SYUKU, 64, (120, 280), gap=-0.08)
    txt[top + 5:top + 285, pole_x + 70:pole_x + 190] = sub
    txt = txt * fm
    rgb = rgb * (1 - txt[..., None] * 0.9) + np.array([30, 20, 14], np.float32) * txt[..., None] * 0.9
    gl = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(gl)
    d.line([(pole_x, top - 30), (pole_x, h - 150)], fill=220, width=7)
    d.polygon([(pole_x - 9, top - 30), (pole_x, top - 56), (pole_x + 9, top - 30)], fill=240)
    for k in range(4):  # 水波
        y = h - 140 + k * 22
        pts = [(x, y + math.sin(x / 26 + k) * 6) for x in range(40, w - 40, 4)]
        d.line(pts, fill=170 - k * 25, width=3)
    d.rounded_rectangle([10, 10, w - 11, h - 11], 18, outline=255, width=6)
    d.rounded_rectangle([26, 26, w - 27, h - 27], 12, outline=200, width=2)
    gm = np.asarray(gl.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255 * np.clip(0.75 + noise(rng, h, w, 2) * 0.35, 0, 1)
    rgb = rgb * (1 - gm[..., None]) + GOLD * gm[..., None]
    return to_img(rgb, np.ones((h, w)))


# ---------- 职业徽章 ----------

def _metal(mask: np.ndarray, rng, base=(176, 132, 62)) -> np.ndarray:
    """铜面：上亮下暗加一点斑驳。"""
    h, w = mask.shape
    yy = np.mgrid[0:h, 0:w][0] / h
    shade = 1.25 - yy * 0.6 + (noise(rng, h, w, 1.5) - 0.5) * 0.25
    return np.array(base, np.float32) * shade[..., None]


def _poly(n: int, cx, cy, r, rot=0.0):
    return [(cx + math.cos(rot + i / n * math.tau) * r, cy + math.sin(rot + i / n * math.tau) * r) for i in range(n)]


def badge_glyph(role: int, shape: str, size=128, seed=1) -> Image.Image:
    """铜边珐琅徽章，中间一个职业字。shape：octagon 八角、shield 盾形。"""
    rng = np.random.default_rng(seed + role)
    s = size
    outer = Image.new("L", (s, s), 0)
    inner = Image.new("L", (s, s), 0)
    do, di = ImageDraw.Draw(outer), ImageDraw.Draw(inner)
    c = s / 2
    if shape == "octagon":
        do.polygon(_poly(8, c, c, s * 0.48, math.pi / 8), fill=255)
        di.polygon(_poly(8, c, c, s * 0.38, math.pi / 8), fill=255)
    else:
        def shield(m):
            return [(s * 0.12 + m, s * 0.08 + m), (s * 0.88 - m, s * 0.08 + m), (s * 0.88 - m, s * 0.5),
                    (c, s * 0.94 - m * 1.3), (s * 0.12 + m, s * 0.5)]
        do.polygon(shield(0), fill=255)
        di.polygon(shield(s * 0.09), fill=255)
    om = np.asarray(outer.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255
    im = np.asarray(inner.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255
    rgb = _metal(om, rng)
    enamel = np.array(ROLE_ENAMEL[role], np.float32) * (0.85 + noise(rng, s, s, 3)[..., None] * 0.3)
    rgb = rgb * (1 - im[..., None]) + enamel * im[..., None]
    edge = np.clip(im - shift(im, 2, 2), 0, 1)
    rgb = rgb * (1 - edge[..., None] * 0.5)
    txt = glyph_mask(ROLE_GLYPHS[role], CARVE, int(s * 0.5), (s, s)) * im
    sh = shift(txt, 2, 3) * (1 - txt)
    rgb = rgb * (1 - sh[..., None] * 0.6)
    rgb = rgb * (1 - txt[..., None]) + np.array([244, 220, 160], np.float32) * txt[..., None]
    return to_img(rgb, om)


def _icon_mask(role: int, s: int) -> Image.Image:
    """职业小图：剑、匕首、弓、太极、葫芦。白色画在黑底上。"""
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    c = s / 2
    if role == 0:  # 双剑交叉
        for sgn in (1, -1):
            ang = math.radians(45 * sgn)
            ux, uy = math.sin(ang), -math.cos(ang)
            px, py = -uy, ux
            tip = (c + ux * s * 0.34, c + uy * s * 0.34)
            base = (c - ux * s * 0.18, c - uy * s * 0.18)
            bw = s * 0.045
            d.polygon([tip, (base[0] + px * bw, base[1] + py * bw), (base[0] - px * bw, base[1] - py * bw)], fill=255)
            g = (c - ux * s * 0.18, c - uy * s * 0.18)
            d.line([(g[0] + px * s * 0.1, g[1] + py * s * 0.1), (g[0] - px * s * 0.1, g[1] - py * s * 0.1)], fill=255, width=int(s * 0.05))
            d.line([g, (c - ux * s * 0.32, c - uy * s * 0.32)], fill=255, width=int(s * 0.05))
    elif role == 1:  # 匕首（斜）
        ux, uy = math.sin(math.radians(35)), -math.cos(math.radians(35))
        px, py = -uy, ux
        tip = (c + ux * s * 0.36, c + uy * s * 0.36)
        base = (c - ux * s * 0.05, c - uy * s * 0.05)
        bw = s * 0.08
        d.polygon([tip, (base[0] + px * bw, base[1] + py * bw), (base[0] - px * bw, base[1] - py * bw)], fill=255)
        d.line([(base[0] + px * s * 0.14, base[1] + py * s * 0.14), (base[0] - px * s * 0.14, base[1] - py * s * 0.14)], fill=255, width=int(s * 0.06))
        d.line([base, (c - ux * s * 0.3, c - uy * s * 0.3)], fill=255, width=int(s * 0.07))
        e = (c - ux * s * 0.34, c - uy * s * 0.34)
        d.ellipse([e[0] - s * 0.05, e[1] - s * 0.05, e[0] + s * 0.05, e[1] + s * 0.05], fill=255)
    elif role == 2:  # 弓和箭
        d.arc([c - s * 0.42, c - s * 0.34, c + s * 0.14, c + s * 0.34], -70, 70, fill=255, width=int(s * 0.09))
        top = (c - s * 0.14 + s * 0.28 * math.cos(math.radians(-70)), c + s * 0.34 * math.sin(math.radians(-70)))
        bot = (top[0], c - (top[1] - c))
        d.line([top, bot], fill=255, width=max(2, int(s * 0.03)))
        d.line([(c - s * 0.3, c), (c + s * 0.3, c)], fill=255, width=int(s * 0.035))
        d.polygon([(c + s * 0.38, c), (c + s * 0.26, c - s * 0.07), (c + s * 0.26, c + s * 0.07)], fill=255)
    elif role == 3:  # 太极
        r = s * 0.32
        d.ellipse([c - r, c - r, c + r, c + r], outline=255, width=int(s * 0.04))
        d.pieslice([c - r, c - r, c + r, c + r], 90, 270, fill=255)
        d.ellipse([c - r / 2, c - r, c + r / 2, c], fill=255)
        d.ellipse([c - r / 2, c, c + r / 2, c + r], fill=0)
        d.ellipse([c - r * 0.12, c - r * 0.62, c + r * 0.12, c - r * 0.38], fill=0)
        d.ellipse([c - r * 0.12, c + r * 0.38, c + r * 0.12, c + r * 0.62], fill=255)
        d.ellipse([c - r, c - r, c + r, c + r], outline=255, width=int(s * 0.04))
    else:  # 葫芦
        d.ellipse([c - s * 0.2, c - s * 0.02, c + s * 0.2, c + s * 0.36], fill=255)
        d.ellipse([c - s * 0.13, c - s * 0.24, c + s * 0.13, c + s * 0.04], fill=255)
        d.rectangle([c - s * 0.03, c - s * 0.34, c + s * 0.03, c - s * 0.22], fill=255)
        d.line([(c - s * 0.12, c - s * 0.02), (c + s * 0.12, c - s * 0.02)], fill=0, width=int(s * 0.03))
        d.arc([c + s * 0.0, c - s * 0.40, c + s * 0.2, c - s * 0.26], 180, 360, fill=255, width=int(s * 0.03))
    return m


def badge_icon(role: int, size=128, seed=1) -> Image.Image:
    """圆形铜章，外圈一圈连珠，里面珐琅底、金色职业小图。"""
    rng = np.random.default_rng(seed + role)
    s = size
    c = s / 2
    outer = Image.new("L", (s, s), 0)
    inner = Image.new("L", (s, s), 0)
    ImageDraw.Draw(outer).ellipse([s * 0.02, s * 0.02, s * 0.98, s * 0.98], fill=255)
    ImageDraw.Draw(inner).ellipse([s * 0.13, s * 0.13, s * 0.87, s * 0.87], fill=255)
    om = np.asarray(outer.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255
    im = np.asarray(inner.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255
    rgb = _metal(om, rng)
    beads = Image.new("L", (s, s), 0)
    bd = ImageDraw.Draw(beads)
    for i in range(20):
        a = i / 20 * math.tau
        x, y = c + math.cos(a) * s * 0.42, c + math.sin(a) * s * 0.42
        bd.ellipse([x - s * 0.022, y - s * 0.022, x + s * 0.022, y + s * 0.022], fill=255)
    bm = np.asarray(beads, np.float32) / 255
    rgb = rgb + bm[..., None] * 50
    enamel = np.array(ROLE_ENAMEL[role], np.float32) * (0.85 + noise(rng, s, s, 3)[..., None] * 0.3)
    rgb = rgb * (1 - im[..., None]) + enamel * im[..., None]
    edge = np.clip(im - shift(im, 2, 2), 0, 1)
    rgb = rgb * (1 - edge[..., None] * 0.5)
    icon = np.asarray(_icon_mask(role, int(s * 0.74)).filter(ImageFilter.GaussianBlur(0.5)), np.float32) / 255
    ic = np.zeros((s, s), np.float32)
    o = (s - icon.shape[0]) // 2
    ic[o:o + icon.shape[0], o:o + icon.shape[1]] = icon
    ic = ic * im
    sh = shift(ic, 2, 3) * (1 - ic)
    rgb = rgb * (1 - sh[..., None] * 0.6)
    rgb = rgb * (1 - ic[..., None]) + np.array([246, 222, 160], np.float32) * ic[..., None]
    return to_img(rgb, om)


# ---------- 对比图 ----------

def label(img: Image.Image, text: str, xy, size=22, fill=(240, 228, 200)) -> None:
    font = ImageFont.truetype("/Library/Fonts/Arial Unicode.ttf", size)
    ImageDraw.Draw(img).text(xy, text, font=font, fill=fill)


def preview(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    base = aged_token()
    orig = Image.open(OUT / "juyi_token.png").convert("RGBA")
    # 原来的：游戏里用思源黑体金字描边，这里近似画一下
    old = orig.copy()
    od = ImageDraw.Draw(old)
    f = ImageFont.truetype("/Library/Fonts/Arial Unicode.ttf", 76)
    for i, ch in enumerate("聚义"):
        od.text((84, 120 + i * 92), ch, font=f, fill=(232, 192, 96), anchor="mm", stroke_width=4, stroke_fill=(42, 20, 8))
    tokens = [
        ("现在", old),
        ("① 毛笔楷书 聚義", engrave(base, "聚義", SYUKU, 92, 0.12, 1, 0.3)),
        ("② 行书 聚义", engrave(base, "聚义", FONTS / "LongCang-Regular.ttf", 104, 0.0, 2, 0.3)),
        ("③ 宋刻体 聚義", engrave(base, "聚義", CARVE, 90, 0.16, 3, 0.3)),
        ("④ 毛笔楷书 聚义\n（简体）", engrave(base, "聚义", MASHAN, 96, 0.08, 4, 0.3)),
    ]
    sheet = Image.new("RGBA", (1280, 720), (34, 26, 20, 255))
    label(sheet, "聚义令：换字体 + 做旧（铜边长铜绿、木面划痕裂纹、字刻进去、描金剥落）", (30, 18), 26)
    for i, (name, im) in enumerate(tokens):
        x = 40 + i * 245
        sheet.alpha_composite(im, (x + 30, 70))
        label(sheet, name, (x + 20, 610), 22)
    sheet.save(out_dir / "1_token.png")

    sheet = Image.new("RGBA", (1280, 720), (34, 26, 20, 255))
    label(sheet, "卡背（游戏里 220×330）", (30, 18), 26)
    old_back = Image.new("RGBA", (220, 330), (58, 29, 20, 255))
    d = ImageDraw.Draw(old_back)
    d.rounded_rectangle([0, 0, 219, 329], 8, outline=(214, 176, 90), width=3)
    d.ellipse([70, 125, 150, 205], fill=SEAL_RED, outline=(236, 220, 188), width=3)
    d.text((110, 165), "义", font=ImageFont.truetype("/Library/Fonts/Arial Unicode.ttf", 46), fill=(236, 220, 188), anchor="mm")
    backs = [("现在", old_back), ("A 乌漆描金·朱印", card_back_a()), ("B 靛青锦缎·题签", card_back_b()), ("C 替天行道旗", card_back_c())]
    for i, (name, im) in enumerate(backs):
        x = 50 + i * 305
        sheet.alpha_composite(im.resize((220, 330), Image.LANCZOS) if im.width != 220 else im, (x, 80))
        label(sheet, name, (x, 430), 24)
    sheet.save(out_dir / "2_back.png")

    sheet = Image.new("RGBA", (1280, 720), (34, 26, 20, 255))
    label(sheet, "左上角职业徽章（战 刺 射 道 医）；下面一排是卡上实际大小", (30, 18), 26)
    rows = [("甲 八角铜章+字", lambda r: badge_glyph(r, "octagon")),
            ("乙 盾形铜章+字", lambda r: badge_glyph(r, "shield")),
            ("丙 圆章+图样", lambda r: badge_icon(r))]
    for j, (name, fn) in enumerate(rows):
        y = 80 + j * 210
        label(sheet, name, (30, y + 50), 24)
        for r in range(5):
            b = fn(r)
            sheet.alpha_composite(b, (250 + r * 140, y))
            sheet.alpha_composite(b.resize((34, 34), Image.LANCZOS), (250 + r * 140 + 47, y + 140))
    sheet.save(out_dir / "3_badge.png")


def main() -> None:
    if len(sys.argv) > 2 and sys.argv[1] == "--preview":
        preview(Path(sys.argv[2]))
        return
    # 定稿（2026-11-27 用户选的）：毛笔楷书「聚義」、靛青锦缎题签卡背、圆章图样徽章
    engrave(aged_token(), "聚義", SYUKU, 92, 0.12, 1, 0.3).save(OUT / "juyi_token_old.png")
    card_back_b().save(OUT / "card_back.png")
    for r in range(len(ROLE_GLYPHS)):
        badge_icon(r, 96).save(OUT / f"role_{r}.png")


if __name__ == "__main__":
    main()
