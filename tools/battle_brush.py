"""画一笔横向的毛笔笔触（放绝招、组合技时招式名下面那一笔）。

    python tools/battle_brush.py

输出 art/ui/brush_stroke.png（1000×200，白色、透明底，游戏里染色）：起笔重、收笔飞白，边缘毛糙。需要 Pillow、numpy。
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
W, H = 1000, 200


def smooth(a: np.ndarray, k: int) -> np.ndarray:
    return np.convolve(a, np.ones(k) / k, mode="same")


def main() -> None:
    rng = np.random.default_rng(11)
    x = np.linspace(0, 1, W)
    # 笔画上下边：起笔粗、收笔细，边缘按列加一点毛糙
    top_edge = 72 * (1 - 0.4 * x ** 1.5) + smooth(rng.normal(0, 4, W), 9)
    bottom_edge = 70 * (1 - 0.45 * x ** 1.5) + smooth(rng.normal(0, 4, W), 9)
    center = H / 2 + 6 * np.sin(x * 3.5 + 0.4)
    yy = np.arange(H)[:, None]
    above = (center[None, :] - yy) / top_edge[None, :]
    below = (yy - center[None, :]) / bottom_edge[None, :]
    dist = np.where(yy < center[None, :], above, below)
    alpha = np.clip((1 - dist) * 7, 0, 1)
    # 飞白：每一行是一根笔毛，到某处墨干了就断开，越往后断得越多
    dry_from = 0.45 + 0.55 * rng.random(H) ** 0.7
    hair = (x[None, :] < dry_from[:, None]).astype(float)
    # 断开处不是一刀切，带一点零星的墨点
    speckle = rng.random((H, W)) < 0.25 * np.clip((x[None, :] - dry_from[:, None]) * -6 + 1, 0, 1)
    alpha *= np.maximum(hair, speckle)
    # 墨色有浓淡
    alpha *= 0.82 + 0.18 * smooth(rng.random(W), 25)[None, :]
    # 起笔圆头
    alpha[:, :16] *= np.linspace(0.2, 1, 16)[None, :] ** 0.5
    img = np.zeros((H, W, 4), dtype=np.uint8)
    # 白色，游戏里按需要染色（绝招朱红、组合技金赭）
    img[..., 0] = 255
    img[..., 1] = 255
    img[..., 2] = 255
    img[..., 3] = (np.clip(alpha, 0, 1) * 240).astype(np.uint8)
    out = Image.fromarray(img, "RGBA").filter(ImageFilter.GaussianBlur(0.7))
    path = ROOT / "art/ui/brush_stroke.png"
    out.save(path, optimize=True)
    print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
