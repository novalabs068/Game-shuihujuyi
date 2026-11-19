"""把 AI 出的像素素材大图切成游戏用的小图。

    python tools/pixel_pipeline.py sprites <原图> <输出目录> <名字1:高度,名字2,...> --height 36
    python tools/pixel_pipeline.py tiles   <原图> <输出目录> <名字1,名字2,...> --size 64
    python tools/pixel_pipeline.py atlas   <输出图集.png> <输入目录> <名字1,名字2,...>

sprites：抠掉白底，按白色间隔找出一个个物件（从上到下、从左到右排序，依次对应名字），
         每个缩到指定的像素高度（名字后面写 :高度，否则用 --height），颜色压到 --max-colors 以内，背景透明。
         名字写 _ 表示跳过这个物件。加 --same-scale 时所有物件按同一比例缩放（最高的那个缩到 --height），
         保留原图里的高矮差别，适合一排站好的人物。
         --sharp 用 Lanczos 缩小（边缘更锐利，适合人物脸部），默认是平均缩小（适合纹理）；
         --outline 在物件外围加一圈 1 像素的深墨色描边，小尺寸下轮廓更清楚。
tiles：  找出一块块地面纹理，取中间部分缩成 size×size 的不透明图块。
         64×64 的图块在游戏里铺成 4×4 格（每格 16 像素）的循环图案，比每格都一样自然。
atlas：  把同样大小的图块按名字顺序横着拼成一张瓦片图集，顺序就是 SceneData.TERRAIN 的 tile 序号。
AI 画的「像素画」并不在真正的像素网格上，所以要缩小重采样再压色，才能得到干净的像素。
需要 Pillow（tools/requirements.txt）。
"""

import argparse
import statistics
from collections import deque
from pathlib import Path

from PIL import Image

BG_TOLERANCE = 34
# 连通区域分析时先缩小，加快速度
DETECT_SCALE = 4
# 外框面积不到中位数这个比例的区域算碎片（比如飘出去的花瓣），并到最近的物件上
FRAGMENT_RATIO = 0.15
MIN_AREA_RATIO = 0.002


def background_mask(img: Image.Image) -> Image.Image:
    """从四条边漫水填充找背景，返回物件为 255、背景为 0 的遮罩。"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
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
    return mask


def find_boxes(mask: Image.Image) -> list[tuple[int, int, int, int]]:
    """找出遮罩里的各个物件外框（原图坐标），离得很近的合并成一个。"""
    small = mask.resize((mask.width // DETECT_SCALE, mask.height // DETECT_SCALE), Image.BOX)
    w, h = small.size
    px = small.load()
    seen = bytearray(w * h)
    boxes = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy] < 128:
                continue
            x0, y0, x1, y1, area = sx, sy, sx, sy, 0
            queue = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while queue:
                x, y = queue.popleft()
                area += 1
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] >= 128:
                        seen[ny * w + nx] = 1
                        queue.append((nx, ny))
            if area >= w * h * MIN_AREA_RATIO:
                s = DETECT_SCALE
                boxes.append((x0 * s, y0 * s, (x1 + 1) * s, (y1 + 1) * s))
    if not boxes:
        return boxes
    area = lambda b: (b[2] - b[0]) * (b[3] - b[1])
    center = lambda b: ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
    limit = statistics.median(area(b) for b in boxes) * FRAGMENT_RATIO
    keep = [b for b in boxes if area(b) >= limit]
    for frag in (b for b in boxes if area(b) < limit):
        fx, fy = center(frag)
        i = min(range(len(keep)), key=lambda k: (center(keep[k])[0] - fx) ** 2 + (center(keep[k])[1] - fy) ** 2)
        k = keep[i]
        keep[i] = (min(k[0], frag[0]), min(k[1], frag[1]), max(k[2], frag[2]), max(k[3], frag[3]))
    boxes = keep
    return sort_reading_order(boxes)


def sort_reading_order(boxes: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    """按行（中心点高度相近的算一行）从上到下，行内从左到右。"""
    rows: list[list[tuple[int, int, int, int]]] = []
    for box in sorted(boxes, key=lambda b: (b[1] + b[3]) / 2):
        cy = (box[1] + box[3]) / 2
        if rows and abs(cy - statistics.mean((b[1] + b[3]) / 2 for b in rows[-1])) < (box[3] - box[1]) / 2:
            rows[-1].append(box)
        else:
            rows.append([box])
    return [b for row in rows for b in sorted(row, key=lambda b: b[0])]


OUTLINE_INK = (30, 26, 24, 255)


def pixelize(img: Image.Image, size: tuple[int, int], max_colors: int, keep_alpha: bool, sharp: bool = False) -> Image.Image:
    """缩到真正的像素尺寸，再把颜色压到 max_colors 以内；透明度只留全透明和不透明两档。"""
    small = img.resize(size, Image.LANCZOS if sharp else Image.BOX)
    rgb = small.convert("RGB").quantize(colors=max_colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    if keep_alpha:
        alpha = small.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
        rgb.putalpha(alpha)
    return rgb


def add_outline(img: Image.Image) -> Image.Image:
    """四周先留 1 像素空边，再把紧挨着物件的透明像素涂成深墨色。"""
    padded = Image.new("RGBA", (img.width + 2, img.height + 2), (0, 0, 0, 0))
    padded.paste(img, (1, 1))
    src = padded.load()
    out = padded.copy()
    dst = out.load()
    for y in range(padded.height):
        for x in range(padded.width):
            if src[x, y][3] != 0:
                continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < padded.width and 0 <= ny < padded.height and src[nx, ny][3] != 0:
                    dst[x, y] = OUTLINE_INK
                    break
    return out


def cmd_sprites(src: Path, out: Path, names: list[str], height: int, max_colors: int, same_scale: bool, sharp: bool = False, outline: bool = False) -> None:
    img = Image.open(src).convert("RGBA")
    mask = background_mask(img)
    boxes = find_boxes(mask)
    print(f"{src.name}：找到 {len(boxes)} 个物件，需要 {len(names)} 个")
    img.putalpha(mask)
    tallest = max(b[3] - b[1] for b in boxes) if boxes else 1
    for spec, box in zip(names, boxes):
        name, _, own_height = spec.partition(":")
        if name == "_":
            continue
        h = int(own_height) if own_height else height
        if same_scale and not own_height:
            h = max(1, round((box[3] - box[1]) * height / tallest))
        crop = img.crop(box)
        w = max(1, round(crop.width * h / crop.height))
        sprite = pixelize(crop, (w, h), max_colors, True, sharp)
        if outline:
            sprite = add_outline(sprite)
        sprite.save(out / f"{name}.png")
        print(f"  {name}: 原图 {crop.size} → {w}×{h}")


def cmd_tiles(src: Path, out: Path, names: list[str], size: int, max_colors: int) -> None:
    img = Image.open(src).convert("RGBA")
    boxes = find_boxes(background_mask(img))
    print(f"{src.name}：找到 {len(boxes)} 块，需要 {len(names)} 块")
    for name, (x0, y0, x1, y1) in zip(names, boxes):
        # 取中间的正方形，略去边缘一圈描边和留白
        side = int(min(x1 - x0, y1 - y0) * 0.94)
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        crop = img.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))
        pixelize(crop, (size, size), max_colors, False).save(out / f"{name}.png")
        print(f"  {name}: 原图 {side}×{side} → {size}×{size}")


def cmd_atlas(dest: Path, src_dir: Path, names: list[str]) -> None:
    blocks = [Image.open(src_dir / f"{n}.png").convert("RGBA") for n in names]
    w, h = blocks[0].size
    atlas = Image.new("RGBA", (w * len(blocks), h))
    for i, block in enumerate(blocks):
        atlas.paste(block, (i * w, 0))
    atlas.save(dest)
    print(f"图集 {dest}：{len(blocks)} 块，每块 {w}×{h}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["sprites", "tiles", "atlas"])
    parser.add_argument("src", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("names")
    parser.add_argument("--height", type=int, default=36, help="sprites：输出的像素高度")
    parser.add_argument("--size", type=int, default=16, help="tiles：瓦片边长")
    parser.add_argument("--max-colors", type=int, default=32)
    parser.add_argument("--same-scale", action="store_true", help="sprites：所有物件按同一比例缩放")
    parser.add_argument("--sharp", action="store_true", help="sprites：用 Lanczos 缩小，边缘更锐利")
    parser.add_argument("--outline", action="store_true", help="sprites：外围加 1 像素深墨色描边")
    args = parser.parse_args()
    names = [n.strip() for n in args.names.split(",") if n.strip()]
    if args.mode == "atlas":
        cmd_atlas(args.src, args.out, names)
        return
    args.out.mkdir(parents=True, exist_ok=True)
    if args.mode == "sprites":
        cmd_sprites(args.src, args.out, names, args.height, args.max_colors, args.same_scale, args.sharp, args.outline)
    else:
        cmd_tiles(args.src, args.out, names, args.size, args.max_colors)


if __name__ == "__main__":
    main()
