# 字体

两种字体都只收 `chars.txt` 里的字（游戏脚本和数据里出现的所有字、GB2312 一级常用字 3755 个、常用标点和符号），
都是 SIL Open Font License 1.1，原件从 google/fonts 下载：

- `NotoSerifSC.ttf`：思源宋体（Noto Serif SC），正文用。从可变字重版定成字重 600（见 `OFL_NotoSerifSC.txt`）。
- `MaShanZheng.ttf`：马善政毛笔楷书（Ma Shan Zheng），标题、按钮、名字用（见 `OFL_MaShanZheng.txt`）。
  不收阿拉伯数字，数字落到思源宋体（毛笔字体的数字不好认）。

加了新文字后如果出现方框（测试 `test_font_covers_text` 会报缺字），把新字补进 `chars.txt`，重新生成：

```
python3 tools/make_fonts.py <放字体原件的目录>
```

原件：`ofl/notoserifsc/NotoSerifSC[wght].ttf`、`ofl/mashanzheng/MaShanZheng-Regular.ttf`。需要 `pip3 install fonttools`。
