"""截取 pixelfx 导出序列帧的前 n 帧（可选染成火焰色），存到 art/fx/<名字>.png，并打印 FxSheets 里那一行。

    python tools/pixelfx/fx_cut.py <导出的 .png> <名字> <帧数> <fire|no>
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image
src, name, n, recolor = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "fire"
meta = json.load(open(src.replace(".png", ".json")))["meta"]["pixelfx"]
fw, fh = meta["frameSize"]; cols = meta["columns"]; n = min(n, meta["frames"])
img = Image.open(src).convert("RGBA")
oc = min(cols, n); orow = (n + oc - 1) // oc
out = Image.new("RGBA", (fw * oc, fh * orow))
for i in range(n):
    f = img.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh))
    out.paste(f, ((i % oc) * fw, (i // oc) * fh))
if recolor:
    a = np.asarray(out).astype(np.float32)
    lum = a[..., :3].mean(axis=2) / 255
    ramp = np.array([[90, 10, 0], [200, 50, 10], [255, 140, 30], [255, 220, 120], [255, 250, 230]], np.float32)
    t = np.clip(lum * 1.3, 0, 1) * (len(ramp) - 1)
    i0 = np.floor(t).astype(int).clip(0, len(ramp) - 2); fr = (t - i0)[..., None]
    a[..., :3] = ramp[i0] * (1 - fr) + ramp[i0 + 1] * fr
    out = Image.fromarray(a.astype(np.uint8))
out.save(str(Path(__file__).resolve().parents[2] / "art/fx" / f"{name}.png"), optimize=True)
px, py = meta["pivot"]
print(f'\t"{name}": [{fw}, {fh}, {oc}, {n}, {meta["fps"]}, {str(meta["loop"]).lower()}, {px}, {py}],')
