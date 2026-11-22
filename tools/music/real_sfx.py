"""用真实录音叠出战斗音效（录音来自 Kenney 的 RPG Audio、Impact Sounds，CC0，见 kenney/License.txt）。

    python tools/music/real_sfx.py [名字 ...]     # 默认全部生成，输出 audio/sfx/<名字>.ogg

每个音效是几段录音按「延迟（毫秒）、音量」叠在一起：先是挥动的风声，再是命中声、闷响。
其余音效（招募、界面、弓箭、绝招鼓点、胜利锣鼓）还是 make_sfx.py 合成的。需要 numpy、ffmpeg（带 libvorbis）。
"""

import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 44100
HERE = Path(__file__).resolve().parent
SRC = HERE / "kenney"
OUT = HERE.parents[1] / "audio" / "sfx"

# 名字 → [(录音, 延迟毫秒, 音量)]
SOUNDS = {
    # 刀剑、枪矛砍中：挥刀风声 + 刀切 + 闷响
    "hit_slash": [("cloth1", 0, 0.9), ("knifeSlice", 70, 1.2), ("impactSoft_medium_000", 90, 1.0)],
    # 斧、棒、禅杖砸中：风声 + 木棍砸击 + 重拳
    "hit_blunt": [("cloth3", 0, 0.8), ("impactWood_heavy_000", 100, 1.2), ("impactPunch_heavy_000", 105, 1.1)],
    # 拳脚、爪牙：衣袖风声 + 重拳
    "hit_fist": [("cloth2", 0, 0.6), ("impactPunch_heavy_001", 60, 1.3)],
    # 暴击：风声 + 金铁交鸣 + 刀切 + 重击
    "hit_crit": [("cloth4", 0, 0.8), ("impactMetal_heavy_000", 70, 1.1), ("knifeSlice2", 75, 1.2), ("impactPunch_heavy_002", 80, 1.0)],
    # 放绝招：拔刀出鞘（和合成的鼓点叠着放）
    "skill_draw": [("drawKnife1", 0, 1.3)],
}


def load(name: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(SRC / f"{name}.ogg"), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def mix(parts: list[tuple[str, int, float]]) -> np.ndarray:
    layers = [np.concatenate([np.zeros(int(SR * delay / 1000), np.float32), load(name) * gain]) for name, delay, gain in parts]
    y = np.zeros(max(len(x) for x in layers), np.float32)
    for x in layers:
        y[: len(x)] += x
    y *= 0.95 / max(np.abs(y).max(), 1e-6)
    # 剪掉尾巴上的静音
    loud = np.nonzero(np.abs(y) > 0.003)[0]
    return y[: loud[-1] + int(SR * 0.05)] if len(loud) else y


def main() -> None:
    for name in sys.argv[1:] or list(SOUNDS):
        y = mix(SOUNDS[name])
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(OUT / f"{name}.ogg")],
                       input=y.tobytes(), check=True)
        print(f"audio/sfx/{name}.ogg  {len(y) / SR:.2f}s")


if __name__ == "__main__":
    main()
