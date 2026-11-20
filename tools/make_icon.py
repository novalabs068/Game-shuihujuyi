"""把 art/inbox/app_icon_linchong.png（整幅的版画：林冲风雪山神庙的背影）做成游戏图标。

    python tools/make_icon.py [原图]

输出：
    icon.png                       512×512，Godot 项目图标（整幅画裁成圆角方块，细墨边）
    art/icon/android_192.png       安卓桌面图标
    art/icon/adaptive_bg_432.png   安卓自适应图标的背景层：整幅画
    art/icon/adaptive_fg_432.png   安卓自适应图标的前景层：透明（画都在背景层里）
自适应图标会被手机裁成圆形或圆角方形，只保留中间约 2/3，所以原图里人物要在正中间。需要 Pillow。
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art/inbox/app_icon_linchong.png"
INK = (30, 28, 26, 255)


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SOURCE
    art = Image.open(src).convert("RGBA")
    side = min(art.size)
    art = art.crop(((art.width - side) // 2, (art.height - side) // 2, (art.width + side) // 2, (art.height + side) // 2))
    (ROOT / "art/icon").mkdir(exist_ok=True)

    size = 512
    pic = art.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=96, fill=255)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(pic, (0, 0), mask)
    ImageDraw.Draw(icon).rounded_rectangle((3, 3, size - 4, size - 4), radius=94, outline=INK, width=8)
    icon.save(ROOT / "icon.png")
    icon.resize((192, 192), Image.LANCZOS).save(ROOT / "art/icon/android_192.png")

    art.resize((432, 432), Image.LANCZOS).save(ROOT / "art/icon/adaptive_bg_432.png")
    Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(ROOT / "art/icon/adaptive_fg_432.png")
    print("icon.png、art/icon/ 已生成")


if __name__ == "__main__":
    main()
