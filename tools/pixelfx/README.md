# pixelfx 特效

游戏里的像素特效（比如走路扬起的土）用 [pixelfx](https://github.com/patch-gg/pixelfx)（MIT License, Copyright (c) 2026 Patch）的工具画出来，再导出成序列帧图放进 `art/fx/`。这里只放我们自己写的特效源码。

重新生成：

```bash
git clone --depth 1 https://github.com/patch-gg/pixelfx.git /tmp/pixelfx
mkdir -p /tmp/pixelfx/src/fx/shuihu && cp tools/pixelfx/*.js /tmp/pixelfx/src/fx/shuihu/
cd /tmp/pixelfx && node tools/render.mjs shuihu/step-dust --sheet --no-actor --out /tmp/pixelfx-out
cp /tmp/pixelfx-out/shuihu/step-dust/step-dust.png art/fx/step_dust.png
```

| 特效 | 源码 | 序列帧 | 用在 |
|---|---|---|---|
| 脚步扬土 | `step-dust.js` | `art/fx/step_dust.png`（32×16 一帧，每行 3 帧，共 13 帧，24 帧/秒，脚底在 (22, 13)） | `scripts/ui/map_actor.gd` |

战斗特效直接用 pixelfx 自带的效果导出，再用 `fx_cut.py` 截掉后面淡出的空帧（灼烧另外染成火焰色），参数登记在 `scripts/ui/fx_sheets.gd`：

```bash
cd /tmp/pixelfx && node tools/render.mjs explosions/small-explosion --sheet --no-actor --out /tmp/pixelfx-out
python tools/pixelfx/fx_cut.py /tmp/pixelfx-out/explosions/small-explosion/small-explosion.png explosion 66 no
```

| 特效 | pixelfx 效果 | 截取 | 用在 |
|---|---|---|---|
| 爆炸 `explosion` | `explosions/small-explosion` | 前 66 帧 | 凌振「轰天雷」 |
| 震地 `ground_slam` | `impacts/ground-slam` | 前 64 帧 | 呼延灼「连环马阵」、秦明「霹雳火」 |
| 重劈 `heavy_cleave` | `melee/heavy-cleave` | 全部 58 帧 | 李逵「双斧乱砍」 |
| 灼烧 `burning` | `fire/spirit-flame` | 全部 90 帧，染成火焰色（`fire`） | 身上着火的状态 |
