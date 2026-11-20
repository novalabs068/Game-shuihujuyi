"""把 art/inbox 里的人物原图处理成游戏用的三种图。

    python tools/art_pipeline.py [--sheet 预览图.png] [id ...]

每个 id（对应 art/prompts/<id>.txt）输出：
    art/portraits/<id>.png  抠掉白底、裁掉空白、高 1024 的立绘
    art/busts/<id>.png      256×256 半身像，用在战斗卡片和选人卡片
    art/faces/<id>.png      128×128 头像，用在出手顺序条
头部位置是自动找的；不准时在 art/crops.json 里按 id 微调：
    {"wu_song": {"dx": -0.03, "dy": 0.02, "zoom": 1.1}}
dx/dy 是占立绘宽高的比例，zoom > 1 裁得更近。需要 Pillow（tools/requirements.txt）。
"""

import argparse
import json
import statistics
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "art"
PORTRAIT_HEIGHT = 1024
BUST_SIZE = 256
FACE_SIZE = 128
# 立绘存成 128 色调色板 PNG：版画是平涂，看不出差别，文件从 1.5 MB 左右降到 250 KB 左右
PORTRAIT_COLORS = 128
BG_TOLERANCE = 30
SHEET_BG = (27, 29, 34)


def remove_background(img: Image.Image) -> Image.Image:
    """从四条边往里漫水填充，把和边缘颜色接近的连通区域变透明。"""
    img = img.convert("RGB")
    w, h = img.size
    px = img.load()
    border = [px[x, 0] for x in range(w)] + [px[x, h - 1] for x in range(w)]
    border += [px[0, y] for y in range(h)] + [px[w - 1, y] for y in range(h)]
    bg = tuple(int(statistics.median(c[i] for c in border)) for i in range(3))
    limit = BG_TOLERANCE * BG_TOLERANCE

    mask = Image.new("L", (w, h), 255)
    m = mask.load()
    seen = bytearray(w * h)
    queue = deque([(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)])
    while queue:
        x, y = queue.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        c = px[x, y]
        if (c[0] - bg[0]) ** 2 + (c[1] - bg[1]) ** 2 + (c[2] - bg[2]) ** 2 > limit:
            continue
        m[x, y] = 0
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                queue.append((nx, ny))

    # 收一圈边再羽化，去掉白边
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1))
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out.crop(mask.getbbox())


def find_head(alpha: Image.Image) -> tuple[float, float]:
    """返回头顶的 (中心 x, 顶端 y)，以立绘宽高的比例表示。

    从上往下找第一行「足够宽」的不透明区（窄的是枪尖之类的兵器），
    再取下面一段里每行最宽那一段的中点平均，当作头的中心。
    """
    w, h = alpha.size
    a = alpha.load()

    def widest_run(y: int) -> tuple[int, int]:
        best, start = (0, 0), None
        for x in range(w + 1):
            solid = x < w and a[x, y] > 128
            if solid and start is None:
                start = x
            elif not solid and start is not None:
                if x - start > best[1] - best[0]:
                    best = (start, x)
                start = None
        return best

    top = 0
    for y in range(h):
        x0, x1 = widest_run(y)
        if x1 - x0 > w * 0.12:
            top = y
            break
    centers = []
    for y in range(top, min(h, top + int(h * 0.2)), 4):
        x0, x1 = widest_run(y)
        centers.append((x0 + x1) / 2)
    return statistics.mean(centers) / w, top / h


def square_crop(img: Image.Image, cx: float, top: float, side: float, size: int) -> Image.Image:
    """以 (cx, top) 为头顶中心，取边长 side（占立绘高度的比例）的正方形，超出部分透明。"""
    w, h = img.size
    s = side * h
    left = cx * w - s / 2
    upper = top * h - s * 0.06
    box = tuple(round(v) for v in (left, upper, left + s, upper + s))
    canvas = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    canvas.paste(img, (-box[0], -box[1]))
    return canvas.resize((size, size), Image.LANCZOS)


def process(hero_id: str, crops: dict) -> Image.Image | None:
    sources = [p for p in ART.glob(f"inbox/{hero_id}.*") if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp")]
    if not sources:
        print(f"跳过 {hero_id}：art/inbox 里没有原图")
        return None
    figure = remove_background(Image.open(sources[0]))
    figure = figure.resize((round(figure.width * PORTRAIT_HEIGHT / figure.height), PORTRAIT_HEIGHT), Image.LANCZOS)

    cx, top = find_head(figure.getchannel("A"))
    tweak = crops.get(hero_id, {})
    cx += tweak.get("dx", 0.0)
    top += tweak.get("dy", 0.0)
    zoom = tweak.get("zoom", 1.0)

    for folder in ("portraits", "busts", "faces"):
        (ART / folder).mkdir(exist_ok=True)
    save_palette(figure, ART / "portraits" / f"{hero_id}.png")
    square_crop(figure, cx, top, 0.52 / zoom, BUST_SIZE).save(ART / "busts" / f"{hero_id}.png")
    square_crop(figure, cx, top, 0.30 / zoom, FACE_SIZE).save(ART / "faces" / f"{hero_id}.png")
    print(f"{hero_id}: 立绘 {figure.size}，头部中心 x={cx:.2f} 顶 y={top:.2f}")
    return figure


def save_palette(img: Image.Image, path: Path) -> None:
    """压成调色板 PNG（保留透明度）。同一张图每次压出来完全一样。"""
    img.convert("RGBA").quantize(colors=PORTRAIT_COLORS, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)


def contact_sheet(ids: list[str], path: Path) -> None:
    """每人一列：立绘、半身像、头像，铺在游戏的深色背景上，方便一眼检查。"""
    col, fig_h = 220, 300
    sheet = Image.new("RGB", (col * len(ids) + 20, fig_h + BUST_SIZE // 2 + FACE_SIZE // 2 + 60), SHEET_BG)
    draw = ImageDraw.Draw(sheet)
    for i, hero_id in enumerate(ids):
        x0 = 10 + i * col
        portrait = Image.open(ART / "portraits" / f"{hero_id}.png").convert("RGBA")
        portrait = portrait.resize((round(portrait.width * fig_h / portrait.height), fig_h), Image.LANCZOS)
        sheet.paste(portrait, (x0 + (col - portrait.width) // 2, 10), portrait)
        bust = Image.open(ART / "busts" / f"{hero_id}.png").resize((BUST_SIZE // 2,) * 2)
        face = Image.open(ART / "faces" / f"{hero_id}.png").resize((FACE_SIZE // 2,) * 2)
        y = fig_h + 25
        draw.rectangle((x0, y, x0 + bust.width, y + bust.height), fill=(52, 70, 95))
        sheet.paste(bust, (x0, y), bust)
        draw.rectangle((x0 + bust.width + 10, y, x0 + bust.width + 10 + face.width, y + face.height), fill=(90, 52, 52))
        sheet.paste(face, (x0 + bust.width + 10, y), face)
    sheet.save(path)
    print(f"预览图：{path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", help="只处理这些 id；默认处理 art/prompts 里的全部")
    parser.add_argument("--sheet", type=Path, help="另外输出一张预览图")
    args = parser.parse_args()
    ids = args.ids or sorted(p.stem for p in (ART / "prompts").glob("*.txt"))
    crops_file = ART / "crops.json"
    crops = json.loads(crops_file.read_text(encoding="utf-8")) if crops_file.exists() else {}
    done = [hero_id for hero_id in ids if process(hero_id, crops) is not None]
    if args.sheet and done:
        contact_sheet(done, args.sheet)


if __name__ == "__main__":
    main()
