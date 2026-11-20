"""把江湖大地图拼清楚：原图（1280×720 的整幅水墨）放大当底，每个地点换成单独出的高清水墨小景。

    python tools/map_compose.py

底图：art/inbox/world_map_2.png 放大到 2048×1152（远山、云雾虚一点不要紧）。
小景：art/inbox/map_lm_<地点>.png（白纸中间一处景，见 art/prompts/map_lm_*.txt）。
做法：先把小景的纸色校成纯白，再在底图上用一个羽化的圆把原来糊的那处景淡掉，
最后用「正片叠底」把小景叠上去（白纸的地方等于没叠，墨色叠出来），边缘羽化融进底图。
输出 art/maps/jianghu.jpg。地点的落脚点坐标不变（在 data/maps/ch1.tres）。需要 numpy、Pillow。
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = (2048, 1152)
# 地点小景的中心和大小（地图坐标，和原图上那处景的位置对齐）
LANDMARKS = {
    "weizhou": ((272, 150), 520),
    "shizipo": ((130, 520), 380),
    "kuaihuolin": ((304, 900), 500),
    "dongjing": ((704, 486), 780),
    "huangnigang": ((768, 1010), 440),
    "yezhulin": ((1152, 210), 580),
    "jingyanggang": ((1192, 750), 540),
    "yanggu": ((1440, 808), 400),
    "cangzhou": ((1680, 240), 580),
    "liangshan": ((1720, 480), 580),
    "erlongshan": ((1888, 832), 480),
}


def paper_color(a: np.ndarray) -> np.ndarray:
    """纸的颜色：四边一圈里最亮那部分的平均色。"""
    border = np.concatenate([a[:8].reshape(-1, 3), a[-8:].reshape(-1, 3), a[:, :8].reshape(-1, 3), a[:, -8:].reshape(-1, 3)])
    lum = border.mean(axis=1)
    return border[lum >= np.percentile(lum, 70)].mean(axis=0)


def feather(size: int, inner: float, outer: float) -> np.ndarray:
    """中间是 1、往外羽化到 0 的圆形遮罩。"""
    y, x = np.mgrid[0:size, 0:size]
    r = np.hypot(x - size / 2, y - size / 2) / size
    return np.clip((outer - r) / (outer - inner), 0, 1)[..., None]


def main() -> None:
    base = np.asarray(Image.open(ROOT / "art/inbox/world_map_2.png").convert("RGB").resize(SIZE, Image.LANCZOS), dtype=np.float32) / 255
    paper = paper_color(base)
    done = []
    for name, ((cx, cy), size) in LANDMARKS.items():
        path = ROOT / f"art/inbox/map_lm_{name}.png"
        if not path.exists():
            continue
        lm = np.asarray(Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS), dtype=np.float32) / 255
        lm = np.clip(lm / paper_color(lm), 0, 1)
        x0, y0 = cx - size // 2, cy - size // 2
        # 裁到地图范围里
        sx0, sy0 = max(0, -x0), max(0, -y0)
        sx1, sy1 = size - max(0, x0 + size - SIZE[0]), size - max(0, y0 + size - SIZE[1])
        region = base[y0 + sy0 : y0 + sy1, x0 + sx0 : x0 + sx1]
        lm = lm[sy0:sy1, sx0:sx1]
        erase = feather(size, 0.18, 0.42)[sy0:sy1, sx0:sx1]
        blend = feather(size, 0.30, 0.48)[sy0:sy1, sx0:sx1]
        region[:] = region * (1 - erase * 0.9) + paper * (erase * 0.9)
        region[:] = region * (1 - blend + blend * lm)
        done.append(name)
    out = ROOT / "art/maps/jianghu.jpg"
    Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).save(out, quality=92, optimize=True)
    print(f"换了 {len(done)} 处：{'、'.join(done)} → {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
