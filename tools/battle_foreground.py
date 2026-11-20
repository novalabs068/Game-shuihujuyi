"""画战斗画面的前景：左右下角几丛虚化的水墨草，给画面一点景深。

    python tools/battle_foreground.py

输出 art/ui/battle_foreground.png（1280×260，透明底），BattleView 把它铺在战场最前面、底栏上方。需要 Pillow。
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = (1280, 260)
INK = (26, 22, 18)


def clump(draw: ImageDraw.ImageDraw, cx: float, rng: random.Random, blades: int, reach: float) -> None:
    """一丛草：从底边 cx 附近长出来的一把弯弯的草叶。"""
    for _ in range(blades):
        x0 = cx + rng.uniform(-reach * 0.35, reach * 0.35)
        height = rng.uniform(60, 230)
        lean = rng.uniform(-0.9, 0.9)
        width = rng.uniform(3, 9)
        alpha = rng.randint(110, 230)
        points = []
        for i in range(12):
            t = i / 11
            x = x0 + lean * height * t * t
            y = SIZE[1] - height * t
            points.append((x, y))
        for i in range(len(points) - 1):
            w = max(1, round(width * (1 - i / len(points))))
            draw.line([points[i], points[i + 1]], fill=INK + (alpha,), width=w)


def main() -> None:
    rng = random.Random(7)
    img = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for cx, blades, reach in [(40, 70, 260), (190, 40, 200), (1240, 70, 260), (1090, 40, 200)]:
        clump(draw, cx, rng, blades, reach)
    # 底边一抹淡墨，像近处的地面
    ground = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    for y in range(SIZE[1] - 40, SIZE[1]):
        a = int(150 * ((y - (SIZE[1] - 40)) / 40) ** 1.5)
        gd.line([(0, y), (SIZE[0], y)], fill=INK + (a,))
    img = Image.alpha_composite(ground, img)
    # 离镜头近，虚一点
    img = img.filter(ImageFilter.GaussianBlur(3.2))
    out = ROOT / "art/ui/battle_foreground.png"
    img.save(out, optimize=True)
    print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
