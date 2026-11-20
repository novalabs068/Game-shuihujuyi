"""从像素小人的原图重新切一套战斗用的高清小人（art/pixel/battle/<名字>.png）。

    python tools/battle_sprites.py [原图名 ...]

大地图和场景里的小人只有 48 像素高左右，战斗里放大 4 倍就糊了。战斗用的这套按 2 倍高度切，
游戏里放大 2 倍显示：屏幕上一样大，细节多一倍。原图里哪个物件是谁，靠和 art/pixel/characters
里已有的小人比对认出来（缩到同样大小比颜色），不用再手写名单。需要 Pillow、numpy。
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixel_pipeline import add_outline, background_mask, find_boxes, pixelize  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "art/inbox"
SMALL = ROOT / "art/pixel/characters"
OUT = ROOT / "art/pixel/battle"
# 人物小人的原图
SHEETS = [
    "pixel_characters", "pixel_protagonists", "pixel_heroes2", "pixel_heroes3", "pixel_heroes4", "pixel_heroes5",
    "pixel_enemies", "pixel_wild_enemies", "pixel_ma_zei", "pixel_jianghu_people", "pixel_boss_a", "pixel_boss_b",
]
SCALE = 2
MAX_COLORS = 48
# 比对的颜色差超过这个就认为不是同一个人
MATCH_LIMIT = 2500.0


def interior(sprite: Image.Image) -> Image.Image:
    """去掉小人外面那 1 像素描边。"""
    return sprite.crop((1, 1, sprite.width - 1, sprite.height - 1))


def distance(crop: Image.Image, small: Image.Image) -> float:
    """原图物件缩到小人大小后，和小人逐像素比的平均颜色差（只比两边都不透明的地方）。"""
    a = np.asarray(crop.resize(small.size, Image.LANCZOS), dtype=np.float32)
    b = np.asarray(small, dtype=np.float32)
    both = (a[..., 3] > 128) & (b[..., 3] > 128)
    if both.sum() < 0.3 * (b[..., 3] > 128).sum():
        return float("inf")
    return float(((a[..., :3] - b[..., :3]) ** 2).sum(axis=2)[both].mean())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sheets", nargs="*", default=SHEETS)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    smalls = {p.stem: interior(Image.open(p).convert("RGBA")) for p in SMALL.glob("*.png")}
    best: dict[str, tuple[float, Image.Image]] = {}
    for sheet in args.sheets:
        path = INBOX / f"{sheet}.png"
        if not path.exists():
            print(f"没有原图 {path.name}，跳过")
            continue
        img = Image.open(path).convert("RGBA")
        mask = background_mask(img)
        img.putalpha(mask)
        for box in find_boxes(mask):
            crop = img.crop(box)
            scores = sorted((distance(crop, s), name) for name, s in smalls.items() if abs(crop.width / crop.height - s.width / s.height) < 0.25)
            if not scores or scores[0][0] > MATCH_LIMIT:
                continue
            d, name = scores[0]
            if name not in best or d < best[name][0]:
                best[name] = (d, crop)
    for name, (d, crop) in sorted(best.items()):
        h = smalls[name].height * SCALE
        w = max(1, round(crop.width * h / crop.height))
        sprite = add_outline(pixelize(crop, (w, h), MAX_COLORS, True, sharp=True))
        sprite.save(OUT / f"{name}.png")
        print(f"{name}: {w}×{h}（比对差 {d:.0f}）")
    missing = sorted(set(smalls) - set(best))
    print(f"切了 {len(best)} 个；没找到原图的：{'、'.join(missing) if missing else '无'}")


if __name__ == "__main__":
    main()
