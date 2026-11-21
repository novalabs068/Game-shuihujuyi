"""从场景地面图集（art/tiles/xiangguosi.png）调色出别的季节和地貌，再给松树加一层积雪。

    python tools/tile_variants.py

输出：
    art/tiles/snow.png    雪地：草地变雪、土路变踩实的雪路、水结冰、菜地和石板落一层雪
    art/tiles/loess.png   黄土山地：草地变成干枯的黄草
    art/pixel/props/song_shu_snow.png  顶上积雪的松树
图集是一行 12 个 64×64 的图块，顺序同 SceneData.TERRAIN 的 tile 序号。需要 Pillow、numpy。
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TILE = 64
GRASS = [0, 4, 5, 9, 10]
DIRT = [1, 7]
WATER = [2]
FARM = [6]
STONE = [8, 11]


def luminance(a: np.ndarray) -> np.ndarray:
    return (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11) / 255


def recolor(tile: np.ndarray, base: tuple, contrast: float) -> np.ndarray:
    """按原图的明暗，把图块换成以 base 为主色的颜色（保留纹理）。"""
    lum = luminance(tile)
    k = 1 + (lum - lum.mean()) * contrast
    out = tile.copy()
    for c in range(3):
        out[..., c] = np.clip(base[c] * k, 0, 255)
    return out


def mix(tile: np.ndarray, color: tuple, amount: float) -> np.ndarray:
    out = tile.copy()
    for c in range(3):
        out[..., c] = tile[..., c] * (1 - amount) + color[c] * amount
    return out


def variant(atlas: np.ndarray, rules: dict) -> np.ndarray:
    out = atlas.copy()
    for index, fn in rules.items():
        x = index * TILE
        out[:, x:x + TILE] = fn(atlas[:, x:x + TILE])
    return out


def snow_cap(sprite: np.ndarray) -> np.ndarray:
    """不透明像素上面两格是透明的，就涂成雪（枝头积雪）。"""
    out = sprite.copy()
    alpha = sprite[..., 3] > 0
    h = sprite.shape[0]
    for y in range(h):
        above = alpha[max(y - 2, 0):y].any(axis=0) if y > 0 else np.zeros(alpha.shape[1], bool)
        cap = alpha[y] & ~above
        out[y, cap, :3] = (236, 240, 246)
        if y + 1 < h:
            below = alpha[y + 1] & cap
            out[y + 1, below, :3] = (210, 218, 228)
    return out


def main() -> None:
    atlas = np.asarray(Image.open(ROOT / "art/tiles/xiangguosi.png").convert("RGBA")).astype(np.float32)
    snow = {i: (lambda t: recolor(t, (226, 232, 240), 0.9)) for i in GRASS}
    snow.update({i: (lambda t: recolor(t, (176, 166, 158), 0.8)) for i in DIRT})
    snow.update({i: (lambda t: recolor(t, (176, 206, 226), 0.6)) for i in WATER})
    snow.update({i: (lambda t: mix(t, (232, 236, 242), 0.6)) for i in FARM})
    snow.update({i: (lambda t: mix(t, (230, 234, 240), 0.4)) for i in STONE})
    loess = {i: (lambda t: recolor(t, (170, 150, 92), 1.1)) for i in GRASS}
    loess.update({i: (lambda t: mix(t, (120, 96, 70), 0.25)) for i in FARM})
    for name, rules in [("snow", snow), ("loess", loess)]:
        out = variant(atlas, rules).astype(np.uint8)
        Image.fromarray(out, "RGBA").save(ROOT / f"art/tiles/{name}.png")
        print(f"art/tiles/{name}.png")
    pine = np.asarray(Image.open(ROOT / "art/pixel/props/song_shu.png").convert("RGBA"))
    Image.fromarray(snow_cap(pine), "RGBA").save(ROOT / "art/pixel/props/song_shu_snow.png")
    print("art/pixel/props/song_shu_snow.png")


if __name__ == "__main__":
    main()
