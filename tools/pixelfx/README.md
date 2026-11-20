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
