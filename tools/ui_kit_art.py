"""古风界面的公共零件图（宋风：乌木、黑漆、宣纸、锦缎、朱印、铜扣）。

    python3 tools/ui_kit_art.py

输出到 art/ui/kit_*.png，游戏里用 StyleBoxTexture 九宫格拉伸（边距见 scripts/ui/ui_kit.gd 的 KIT_MARGINS）：
- kit_slip.png     挂木签（竖着的乌木签，顶上一个系绳的小孔，金边；主菜单「招募、好汉、编队、江湖榜」用）
- kit_slip_red.png 选中的木签（朱漆）
- kit_lacquer.png  黑漆金边框（匾额、题签、资源条、名牌）
- kit_panel.png    宣纸面板：石青锦缎包边、四角回纹（弹窗、详情页）
- kit_note.png     宣纸字条：细金线框（提示条、告示）
- kit_seal.png     圆朱印（「归」返回键、号令）
- kit_copper.png   铜扣圆钮（设置等小图标钮）
- kit_tab.png / kit_tab_on.png 书签页签（乌木 / 朱漆，上圆下平）
- kit_slot.png     装备木匣格
需要 Pillow、numpy。
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "ui"
## 九宫格零件按 1 倍出图（StyleBoxTexture 的边按图上的像素原样画，不缩放）
S = 1
## 圆钮整张拉伸显示，画 2 倍更细腻
DISC_SCALE = 2

GILT = (201, 162, 90)
GILT_DIM = (154, 116, 52)
CINNABAR = (168, 41, 29)
PAPER = (236, 224, 195)


def noise(rng: np.random.Generator, h: int, w: int, blur: float, stretch=(1, 1)) -> np.ndarray:
    small = rng.random((max(h // stretch[0], 1), max(w // stretch[1], 1)))
    img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    img = img.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(img, dtype=np.float32) / 255.0
    return (a - a.min()) / max(a.max() - a.min(), 1e-6)


def wood(w: int, h: int, base: tuple, seed: int, vertical=True) -> np.ndarray:
    """木纹：顺着长边的细纹 + 中间亮两边暗的圆柱感。"""
    rng = np.random.default_rng(seed)
    grain = noise(rng, h, w, 1.2, (16, 1) if vertical else (1, 16))
    across = np.linspace(-1, 1, w if vertical else h)
    shade = 1.0 - 0.35 * across ** 2
    shade = shade[None, :] if vertical else shade[:, None]
    rgb = np.array(base, dtype=np.float32)[None, None, :] * (0.78 + 0.32 * grain[..., None]) * shade[..., None]
    return np.clip(rgb, 0, 255)


def to_image(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb.astype(np.uint8), a]), "RGBA")


def round_mask(w: int, h: int, r_top: int, r_bottom: int) -> np.ndarray:
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle((0, 0, w - 1, h - 1 + r_top), radius=r_top, fill=255)
    m2 = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m2).rounded_rectangle((0, -r_bottom, w - 1, h - 1), radius=r_bottom, fill=255)
    return np.minimum(np.asarray(m), np.asarray(m2)).astype(np.float32) / 255.0


def slip(base: tuple, seed: int, name: str) -> None:
    w, h = 64 * S, 160 * S
    rgb = wood(w, h, base, seed)
    img = to_image(rgb, round_mask(w, h, 9 * S, 4 * S))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((2 * S, 2 * S, w - 1 - 2 * S, h - 1 - 2 * S), radius=7 * S, outline=GILT + (150,), width=2 * S)
    cx = w // 2
    d.ellipse((cx - 5 * S, 9 * S, cx + 5 * S, 19 * S), fill=(29, 18, 10, 255), outline=GILT + (255,), width=2 * S)
    img.save(OUT / name)


def lacquer() -> None:
    w, h = 96 * S, 64 * S
    rng = np.random.default_rng(3)
    g = np.linspace(1.0, 0.62, h)[:, None]
    n = noise(rng, h, w, 3)
    rgb = np.array((44, 30, 19), np.float32)[None, None, :] * (g * (0.9 + 0.2 * n))[..., None]
    img = to_image(rgb, np.ones((h, w), np.float32))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(20, 12, 6, 255), width=1 * S)
    d.rectangle((1 * S, 1 * S, w - 1 - 1 * S, h - 1 - 1 * S), outline=GILT + (255,), width=2 * S)
    d.rectangle((5 * S, 5 * S, w - 1 - 5 * S, h - 1 - 5 * S), outline=GILT + (110,), width=1 * S)
    img.save(OUT / "kit_lacquer.png")


def paper(w: int, h: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    fib = noise(rng, h, w, 0.8, (1, 6))
    blot = noise(rng, h, w, 18)
    rgb = np.array(PAPER, np.float32)[None, None, :] * (0.94 + 0.05 * fib[..., None] - 0.05 * blot[..., None])
    return np.clip(rgb, 0, 255)


def huiwen(d: ImageDraw.ImageDraw, x: int, y: int, sx: int, sy: int, color: tuple) -> None:
    """一个回纹角（L 形外框 + 往里勾的小钩），sx/sy 是朝向（±1）。"""
    L, t = 16 * S, 3 * S
    def rect(x0, y0, x1, y1):
        d.rectangle((min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)), fill=color)
    rect(x, y, x + sx * L, y + sy * t)
    rect(x, y, x + sx * t, y + sy * L)
    i = 6 * S
    rect(x + sx * i, y + sy * i, x + sx * (i + 7 * S), y + sy * (i + 2 * S))
    rect(x + sx * (i + 5 * S), y + sy * i, x + sx * (i + 7 * S), y + sy * (i + 7 * S))


def brocade_border(img: Image.Image, width: int) -> None:
    tile = Image.open(OUT / "result_brocade.png").convert("RGBA").resize((18, 18), Image.LANCZOS)
    w, h = img.size
    band = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for yy in range(0, h, tile.height):
        for xx in range(0, w, tile.width):
            band.alpha_composite(tile, (xx, yy))
    mask = Image.new("L", (w, h), 255)
    ImageDraw.Draw(mask).rectangle((width, width, w - 1 - width, h - 1 - width), fill=0)
    img.paste(band, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=GILT_DIM + (255,), width=1 * S)
    d.rectangle((width, width, w - 1 - width, h - 1 - width), outline=GILT + (255,), width=1 * S)


def panel() -> None:
    w = h = 128 * S
    img = to_image(paper(w, h, 7), np.ones((h, w), np.float32))
    b = 10 * S
    brocade_border(img, b)
    d = ImageDraw.Draw(img)
    o = b + 5 * S
    for sx, sy, x, y in [(1, 1, o, o), (-1, 1, w - 1 - o, o), (1, -1, o, h - 1 - o), (-1, -1, w - 1 - o, h - 1 - o)]:
        huiwen(d, x, y, sx, sy, GILT_DIM + (255,))
    img.save(OUT / "kit_panel.png")


def note() -> None:
    w, h = 96 * S, 64 * S
    img = to_image(paper(w, h, 11), np.ones((h, w), np.float32))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=GILT_DIM + (255,), width=1 * S)
    d.rectangle((4 * S, 4 * S, w - 1 - 4 * S, h - 1 - 4 * S), outline=GILT_DIM + (120,), width=1 * S)
    img.save(OUT / "kit_note.png")


def disc(name: str, inner: tuple, outer: tuple, ring: tuple, ring2: tuple | None, seed: int, rough: bool) -> None:
    n = 128 * DISC_SCALE
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2
    r = np.hypot(xx - c, yy - c) / c
    rng = np.random.default_rng(seed)
    edge = 0.97 - (0.025 * noise(rng, n, n, 2) if rough else 0)
    alpha = np.clip((edge - r) * 60, 0, 1)
    t = np.clip(r, 0, 1)[..., None]
    lit = np.hypot(xx - c * 0.85, yy - c * 0.8) / c
    rgb = np.array(inner, np.float32) * (1 - t) + np.array(outer, np.float32) * t
    rgb *= (1.08 - 0.15 * np.clip(lit, 0, 1))[..., None]
    if rough:
        rgb *= (0.9 + 0.12 * noise(rng, n, n, 1.5))[..., None]
    img = to_image(np.clip(rgb, 0, 255), alpha)
    d = ImageDraw.Draw(img)
    m = 7 * DISC_SCALE
    d.ellipse((m, m, n - 1 - m, n - 1 - m), outline=ring, width=3 * DISC_SCALE)
    if ring2:
        m2 = 3 * DISC_SCALE
        d.ellipse((m2, m2, n - 1 - m2, n - 1 - m2), outline=ring2, width=2 * DISC_SCALE)
    img.save(OUT / name)


def tab(name: str, base: tuple, seed: int) -> None:
    w, h = 96 * S, 48 * S
    rgb = wood(w, h, base, seed, vertical=False)
    img = to_image(rgb, round_mask(w, h, 9 * S, 0))
    ImageDraw.Draw(img).rounded_rectangle((1 * S, 1 * S, w - 1 - 1 * S, h + 10 * S), radius=8 * S, outline=GILT + (170,), width=1 * S)
    img.save(OUT / name)


def slot() -> None:
    w = h = 72 * S
    rgb = wood(w, h, (78, 50, 29), 21, vertical=False) * 0.8
    img = to_image(rgb, np.ones((h, w), np.float32))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=GILT + (255,), width=2 * S)
    d.rectangle((6 * S, 6 * S, w - 1 - 6 * S, h - 1 - 6 * S), outline=(20, 12, 6, 200), width=2 * S)
    img.save(OUT / "kit_slot.png")


def main() -> None:
    slip((122, 82, 51), 1, "kit_slip.png")
    slip((168, 41, 29), 2, "kit_slip_red.png")
    lacquer()
    panel()
    note()
    disc("kit_seal.png", (196, 58, 42), (150, 34, 24), (247, 231, 198, 220), None, 5, True)
    disc("kit_copper.png", (70, 48, 30), (26, 17, 10), GILT + (255,), None, 6, False)
    tab("kit_tab.png", (70, 48, 30), 8)
    tab("kit_tab_on.png", (168, 41, 29), 9)
    slot()
    print("done")


if __name__ == "__main__":
    main()
