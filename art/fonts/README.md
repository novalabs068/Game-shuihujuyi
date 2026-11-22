# 字体

`NotoSansSC.ttf`：思源黑体（Noto Sans SC），SIL Open Font License 1.1（见 `OFL.txt`）。
从 google/fonts 的可变字重版定成字重 500，再用 fonttools 子集化：只收 `chars.txt` 里的字
（游戏脚本和数据里出现的所有字、GB2312 一级常用字 3755 个、常用标点和符号）。
加了新文字后如果出现方框，重新生成：

```
fonttools varLib.instancer NotoSansSC[wght].ttf wght=500 -o NotoSansSC-500.ttf
pyftsubset NotoSansSC-500.ttf --text-file=chars.txt --output-file=NotoSansSC.ttf --layout-features='*' --no-hinting
```
