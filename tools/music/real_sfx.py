"""用真实录音叠出全部音效。

    python3 tools/music/real_sfx.py [名字 ...]     # 默认全部生成，输出 audio/sfx/<名字>.ogg

录音来源（都是 CC0，可商用、不用署名）：
- kenney/：Kenney 的 RPG Audio、Impact Sounds（刀切、挥动、拳击、木棍、金属），见 kenney/License.txt
- freesound/：Freesound.org 上的南狮鼓、中国大鼓、框鼓、锣、中国戏曲的钹、场记板（两块木板相拍，像檀板）、法槌拍桌（当醒木）、
  翻纸、纸落、风声、衣袂、放箭、加美兰铜片琴（变调当方响），编号和原名见 freesound/License.txt

每个音效是几层录音叠在一起：(来源, 从第几秒截, 截多长, 延迟秒, 音量倍数, 变速倍数)。
变速同时变调（2 = 高八度），用来把一个铜片音变成宫商角徵羽。需要 numpy、ffmpeg（带 libvorbis）。
"""

import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 44100
HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "audio" / "sfx"

# 常用的截段
DRUM = ("freesound/878072", 0.0, 1.8)          # 南狮鼓（中国大鼓）一击
RIM = ("freesound/856560", 0.24, 0.6)          # 中国大鼓敲鼓边，叠在鼓声上加「哒」的槌头声
FRAME = ("freesound/345636", 0.0, 1.6)        # 框鼓：低沉的鼓身
GONG = ("freesound/18654", 0.0, 4.5)           # 锣
GONG_LOW = ("freesound/112507", 0.0, 4.5)      # 大锣，托低音
BO = ("freesound/452400", 0.0, 1.09)           # 戏曲铙钹
CLAP = ("freesound/194719", 0.0, 0.22)         # 两块木板一拍（檀板）
GAVEL = ("freesound/618138", 0.0, 1.0)         # 硬木拍桌（醒木）
METAL = ("freesound/210493", 0.0, 2.0)         # 铜片琴，基音约 1217Hz

# 方响：把铜片音变调到 D 宫五声（D6 E6 #F6 A6 B6 D7）
FANG = [1174.66 / 1217 * 2 ** (s / 12) for s in (0, 2, 4, 7, 9, 12)]

# 名字 → [(来源, 起点秒, 长度秒, 延迟秒, 音量, 变速)]
SOUNDS = {
    # 刀剑、枪矛砍中：挥刀风声 + 刀切 + 闷响
    "hit_slash": [("kenney/cloth1", 0, 9, 0, 0.9, 1), ("kenney/knifeSlice", 0, 9, 0.07, 1.2, 1), ("kenney/impactSoft_medium_000", 0, 9, 0.09, 1.0, 1)],
    # 斧、棒、禅杖砸中：风声 + 木棍砸击 + 重拳
    "hit_blunt": [("kenney/cloth3", 0, 9, 0, 0.8, 1), ("kenney/impactWood_heavy_000", 0, 9, 0.1, 1.2, 1), ("kenney/impactPunch_heavy_000", 0, 9, 0.105, 1.1, 1)],
    # 拳脚、爪牙：衣袖风声 + 重拳
    "hit_fist": [("kenney/cloth2", 0, 9, 0, 0.6, 1), ("kenney/impactPunch_heavy_001", 0, 9, 0.06, 1.3, 1)],
    # 暴击：风声 + 金铁交鸣 + 刀切 + 重击
    "hit_crit": [("kenney/cloth4", 0, 9, 0, 0.8, 1), ("kenney/impactMetal_heavy_000", 0, 9, 0.07, 1.1, 1), ("kenney/knifeSlice2", 0, 9, 0.075, 1.2, 1), ("kenney/impactPunch_heavy_002", 0, 9, 0.08, 1.0, 1)],
    # 放绝招：拔刀出鞘（和绝招鼓叠着放）
    "skill_draw": [("kenney/drawKnife1", 0, 9, 0, 1.3, 1)],

    # 按钮：两块木板轻轻一合（每按一下都响，音量放轻、略压高音）
    "ui_click": [(*CLAP, 0, 1.0, 1.0)],
    # 列传开场：醒木拍案
    "xingmu": [(*GAVEL, 0, 1.0, 1.0), (*FRAME, 0.005, 0.25, 1.6)],
    # 聚义令破空：风声 + 衣袂
    "token_whoosh": [("freesound/60013", 0, 9, 0, 1.0, 1.0), ("freesound/496188", 0, 9, 0.05, 0.6, 1.0)],
    # 聚义令落案：大鼓 + 框鼓低音 + 拍桌
    "token_slam": [(*DRUM, 0, 1.0, 0.92), (*FRAME, 0, 0.6, 0.85), (*GAVEL, 0.005, 0.4, 0.9)],
    # 宣纸卡片落下
    "card_drop": [("freesound/205911", 0.3, 0.55, 0, 1.0, 1.0)],
    # 翻开宣纸卡
    "card_flip": [("freesound/82379", 0.03, 0.4, 0, 1.0, 1.0)],
    # 稀有：方响一串上行（宫商角徵羽宫）
    "rare_shimmer": [(*METAL, i * 0.085, 0.75 + 0.05 * i, r) for i, r in enumerate(FANG)],
    # 甲等好汉：锣 + 大锣托底 + 钹 + 一记大鼓
    "jia_gong": [(*GONG, 0, 1.0, 1.0), (*GONG_LOW, 0, 0.5, 1.0), (*BO, 0, 0.5, 1.0), (*DRUM, 0, 0.6, 1.0)],
    # 放箭
    "arrow": [("freesound/443832", 0, 9, 0, 1.0, 1.0)],
    # 放绝招：擂三通鼓，最后一下加钹
    "skill_drum": [(*DRUM, 0, 0.7, 1.04), (*RIM, 0, 0.3, 1.0), (*DRUM, 0.13, 0.8, 1.0), (*RIM, 0.13, 0.3, 1.03),
                   (*DRUM, 0.26, 1.0, 0.95), (*RIM, 0.26, 0.4, 1.0), (*BO, 0.26, 0.45, 1.0)],
    # 胜利：得胜鼓由疏到密，大锣铙钹齐鸣
    "victory": [
        *[(*DRUM, at, 0.55 + 0.05 * i, 1.03 - 0.01 * (i % 3)) for i, at in enumerate([0.0, 0.2, 0.36, 0.49, 0.59, 0.67])],
        *[(*RIM, at, 0.25, 1.0) for at in [0.0, 0.2, 0.36, 0.49, 0.59, 0.67]],
        (*DRUM, 0.74, 1.0, 0.95), (*GONG, 0.74, 0.9, 1.0), (*GONG_LOW, 0.74, 0.4, 1.0), (*BO, 0.74, 0.55, 1.0),
    ],
}

# 每个音效最响那 0.1 秒的音量（dB，去掉 100Hz 以下）。合成版时代调好的响度，游戏里各处的音量不用改；
# 命中声（hit_*、skill_draw）不在表里，保持原样只做峰值归一。
PUNCH = {
    "token_whoosh": -12.8, "token_slam": -20.1, "card_drop": -20.9, "card_flip": -19.6, "rare_shimmer": -9.0,
    "jia_gong": -12.4, "arrow": -11.5, "skill_drum": -15.2, "victory": -12.8, "ui_click": -17.9, "xingmu": -15.0,
}


def load(name: str, start: float, length: float, rate: float) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(HERE / f"{name}.ogg"), "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).astype(float)
    x = x[int(start * SR): int((start + length) * SR)].copy()
    # 截断处淡出 30 毫秒，免得「咔」一声
    fade = min(len(x) // 4, int(SR * 0.03))
    x[-fade:] *= np.linspace(1, 0, fade)
    if rate != 1.0:
        pos = np.arange(0, len(x) - 1, rate)
        x = np.interp(pos, np.arange(len(x)), x)
    return x


def mix(parts: list) -> np.ndarray:
    layers = [(int(delay * SR), load(name, start, length, rate) * gain) for name, start, length, delay, gain, rate in parts]
    y = np.zeros(max(a + len(x) for a, x in layers))
    for a, x in layers:
        y[a:a + len(x)] += x
    return y


def highpass(x: np.ndarray, lo: float) -> np.ndarray:
    size = 1 << (len(x) - 1).bit_length()
    f = np.fft.rfftfreq(size, 1 / SR)
    return np.fft.irfft(np.fft.rfft(x, size) / (1 + (lo / np.maximum(f, 1)) ** 4), size)[: len(x)]


def punch(x: np.ndarray) -> float:
    x = highpass(x, 100)
    w = int(SR * 0.1)
    e = np.convolve(x ** 2, np.ones(w) / w, "valid") if len(x) > w else np.array([np.mean(x ** 2)])
    return 10 * np.log10(max(float(np.max(e)), 1e-12))


def level(x: np.ndarray, target: float) -> np.ndarray:
    """调到目标响度；峰值超过 0.7 的部分用 tanh 软压，最高不过 0.95。"""
    x = x / np.max(np.abs(x)) * 0.5
    for _ in range(4):
        x = x * 10 ** ((target - punch(x)) / 20)
        knee = 0.7
        over = np.abs(x) > knee
        x[over] = np.sign(x[over]) * (knee + 0.25 * np.tanh((np.abs(x[over]) - knee) / 0.25))
    return x


def build(name: str) -> np.ndarray:
    y = mix(SOUNDS[name])
    y = level(y, PUNCH[name]) if name in PUNCH else y * 0.95 / max(np.abs(y).max(), 1e-6)
    # 剪掉尾巴上的静音
    loud = np.nonzero(np.abs(y) > 0.003)[0]
    y = y[: loud[-1] + int(SR * 0.05)] if len(loud) else y
    fade = min(len(y) // 10, int(SR * 0.02))
    y[-fade:] *= np.linspace(1, 0, fade)
    return y


def main() -> None:
    names = sys.argv[1:]
    out_dir = OUT
    if names and names[0].startswith("--out="):
        out_dir = Path(names.pop(0)[6:])
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in names or list(SOUNDS):
        y = build(name).astype(np.float32)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(out_dir / f"{name}.ogg")],
                       input=y.tobytes(), check=True)
        print(f"{name}.ogg  {len(y) / SR:.2f}s")


if __name__ == "__main__":
    main()
