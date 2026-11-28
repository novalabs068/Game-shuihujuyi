#!/usr/bin/env python3
"""重新生成游戏里打包的两种字体（只收 art/fonts/chars.txt 里的字）。

    python3 tools/make_fonts.py <字体原件所在目录>

原件从 google/fonts 下载（SIL OFL 1.1）：
  - ofl/notoserifsc/NotoSerifSC[wght].ttf  → art/fonts/NotoSerifSC.ttf（思源宋体，定成字重 600，正文用）
  - ofl/mashanzheng/MaShanZheng-Regular.ttf → art/fonts/MaShanZheng.ttf（马善政毛笔字，标题和按钮用）
毛笔字不收阿拉伯数字：毛笔的数字不好认，数字落到思源宋体。
加了新文字、测试 test_font_covers_text 报缺字时，先把新字补进 chars.txt 再跑一次。
需要 fonttools（pip3 install fonttools）。
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.varLib import instancer
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "art" / "fonts"
## 正文宋体的字重：600 在手机小字号下比 400 清楚，又不显得粗
SERIF_WEIGHT = 600


def chars() -> str:
    text = (FONTS / "chars.txt").read_text(encoding="utf-8")
    return "".join(sorted(set(text)))


def make_subset(font: TTFont, text: str, out: Path) -> None:
    options = subset.Options()
    options.layout_features = ["*"]
    options.hinting = False
    sub = subset.Subsetter(options)
    sub.populate(text=text)
    sub.subset(font)
    font.save(out)
    print(f"{out.relative_to(ROOT)}: {out.stat().st_size // 1024} KB")


def main() -> None:
    src = Path(sys.argv[1])
    text = chars()
    serif = instancer.instantiateVariableFont(TTFont(src / "NotoSerifSC[wght].ttf"), {"wght": SERIF_WEIGHT})
    make_subset(serif, text, FONTS / "NotoSerifSC.ttf")
    brush_text = "".join(c for c in text if not c.isdigit())
    make_subset(TTFont(src / "MaShanZheng-Regular.ttf"), brush_text, FONTS / "MaShanZheng.ttf")


if __name__ == "__main__":
    main()
